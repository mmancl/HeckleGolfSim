# Work Package 03 — Profile Identity, Primary Profile & Cloud Sync Engine

> **Prerequisite:** Read [`00_OVERVIEW.md`](00_OVERVIEW.md), [`01_FIREBASE_BACKEND_SCHEMA_RULES.md`](01_FIREBASE_BACKEND_SCHEMA_RULES.md), and [`02_GODOT_FIREBASE_CLIENT_AND_AUTH.md`](02_GODOT_FIREBASE_CLIENT_AND_AUTH.md).
> **Depends on:** Package 02 API stub (can start Day 1 against mock `FirestoreClient`).
> **Owns:** `Utils/Cloud/cloud_sync.gd` (Autoload `CloudSync`), `Utils/Cloud/stats_merger.gd`, profile registry migration & lifetime stat hooks in `Utils/MultiplayerManager.gd` and `Utils/AchievementManager.gd`, Primary Profile & Account UI bar in `UI/PlayersMenu/players_menu.gd`, `tests/test_cloud_sync_and_merge.gd`.

---

## 1. Scope & Goals

1. Migrate `user://players_registry.json` so every local profile has a stable `profile_id` (UUIDv4), optional `cloud_uid`, and `link_role` (`"none"`, `"primary"`, `"linked"`) without breaking existing name-keyed code (Hole H1).
2. Let the user select which local profile is their **Primary Profile** on the Players page, with clear confirmation dialogs when switching primary profiles (Hole H24).
3. Pull cloud data for the Primary Profile (and any approved Linked Profiles from Package 04) **on app startup**, merging it non-destructively with local data (Hole H3).
4. Push dirty local changes to Firebase **after every finished match** and **every 30 minutes of active foreground usage** (plus best-effort flush on quit / next launch if dirty) (Hole H23).
5. Solve the 10-match history cap (Hole H2) and 1 MiB Firestore document cap (Hole H4) by maintaining lifetime aggregates, immutable match summaries, a **200-shot-per-club** cloud window (`CLOUD_MAX_SHOTS_PER_CLUB = 200`), and `longest_putt_ft` tracking.

---

## 2. Local Registry & Stat Upgrades (Holes H1, H2, H20)

### 2.1 `user://players_registry.json` Migration
On load in `MultiplayerManager.get_registered_players()` (around `Utils/MultiplayerManager.gd` L2520), backfill missing fields on every entry:
```json
{
  "profile_id": "c4f19e82-7b1a-4c3e-9a21-8f30d2a1b904",
  "name": "Mike",
  "email": "user1@gmail.com",
  "avatar": "res://assets/images/avatars/golfer_1.png",
  "bag": ["Dr", "3W", "5i", "6i", "7i", "8i", "9i", "PW", "SW", "Pt"],
  "preferred_tee": "Blue",
  "skill_level": "mid_handicap",
  "handedness": 0,
  "ball_graphic": "single_line",
  "created_at": 1728000000,
  "cloud_uid": "uid_of_user1",
  "link_role": "primary",
  "last_synced_rev": 14,
  "last_synced_at": 1730003600,
  "cloud_lifetime_cache": {}
}
```
Helper methods to add to `MultiplayerManager`:
- `get_primary_player_name() -> String` (returns the profile with `link_role == "primary"`, or `""` if none set).
- `set_primary_player(player_name: String, cloud_uid: String) -> void` (ensures at most one local profile has `link_role == "primary"`).
- `get_player_by_cloud_uid(cloud_uid: String) -> Dictionary`.
- `rename_player_profile(old_name: String, new_name: String) -> bool` (renames the key across `players_registry.json`, `player_club_stats.json`, `player_achievements.json`, `player_swing_issues.json`, and `user://match_history/*.json` so renames never orphan data).

### 2.2 Shot Entry IDs, Timestamps, Source Tagging & Longest Putt (Holes H3, H20)
In `MultiplayerManager.record_global_shot()` (`Utils/MultiplayerManager.gd` L2993):
1. Add `"id"` (12-char hex string, e.g. `"%08x%04x" % [Time.get_unix_time_from_system(), randi() & 0xffff]`) and `"t"` (`int(Time.get_unix_time_from_system())`) to every new shot entry in `player_club_stats.json`. Backfill missing `id`s deterministically (`sha1(json_string).substr(0, 12)`) when loading existing shots.
2. Tag `"src": "lm"` when the shot came from `LaunchMonitorManager` vs `"src": "manual"` when triggered from the manual hit / debug shot injector. Only `"src": "lm"` (or legacy shots without `"src"`) update personal records (`_records.longest_drive`, `_records.longest_putt_ft`) for public leaderboards.
3. Track **`longest_putt_ft`** in `stats[target_key]["_records"]["longest_putt_ft"]` whenever a player **holes out** on the green with a putter (`MultiplayerManager.gd` L830–842, where `putt_dist` in yards is already calculated: `var putt_ft = putt_dist * 3.0`).
4. Record clear-history **tombstones** in `stats[target_key]["_tombstones"]`:
   - In `clear_player_ball_history(player_name)` (L2798): set `stats[target_key]["_tombstones"]["cleared_all_at"] = int(Time.get_unix_time_from_system())`.
   - In `clear_player_club_shot_data(player_name, club_name)` (L3065): set `stats[target_key]["_tombstones"]["cleared_clubs"][club_code] = int(Time.get_unix_time_from_system())`.
   - In `clear_player_swing_issues(player_name)` (L3896): store `_cleared_at` timestamp in `player_swing_issues.json`.

### 2.3 Merging Cloud Lifetime Stats into `calculate_player_stats()` (Hole H2)
Because `user://match_history` only retains the 10 most recent match files, update `MultiplayerManager.calculate_player_stats(player_name)` (`L3624`) so that if the profile has a `cloud_lifetime_cache` (populated from `profiles/{uid}.lifetime`), it combines local un-uploaded matches with `cloud_lifetime_cache` (taking the max of `matches_played`, `wins`, `longest_drive`, `longest_putt_ft`, and merging `best_courses` by lowest `diff`).

---

## 3. Non-Destructive Merge Algorithm (`Utils/Cloud/stats_merger.gd`)

`StatsMerger.merge_profile_stats(local_data: Dictionary, cloud_data: Dictionary) -> Dictionary` is a **pure, stateless function** (easy to unit-test) that merges local and cloud copies of a profile's data:

1. **Tombstones:**
   - `effective_cleared_all_at = max(local.tombstones.cleared_all_at, cloud.tombstones.cleared_all_at)`
   - For each club `C`: `effective_club_clear[C] = max(effective_cleared_all_at, local.tombstones.cleared_clubs[C], cloud.tombstones.cleared_clubs[C])`.
2. **Club Shots (`clubs.<club>[]`):**
   - Union `local.clubs[C]` and `cloud.clubs[C]` by shot `id`.
   - Filter out any shot with `t > 0 and t <= effective_club_clear[C]`.
   - Sort ascending by `t`, and keep the **most recent 200 shots** (`CLOUD_MAX_SHOTS_PER_CLUB = 200`, per Owner Decision D5) for the cloud payload (local file may retain all shots).
3. **Records (`longest_drive_yds`, `longest_putt_ft`):**
   - Take `max(local_val, cloud_val)` (unless `cleared_all_at` is newer than all shots and records were reset, in which case recompute from surviving shots).
4. **Achievements (`player_achievements.json`):**
   - Union unlocked achievement IDs; for each `ach_id`, `unlocked_at = min(local_ts, cloud_ts)`.
   - Union `heard_heckles` sets; if `heard_heckles.size() >= AchievementManager.get_total_heckles_count()`, unlock `all_heckles`.
5. **Swing Issues (`player_swing_issues.json`):**
   - Respect `cleared_swing_issues_at` tombstone.
   - For each `"YYYY-MM"` bucket and each issue name, take `max(local_count, cloud_count)` (since a user might record swings on two devices in the same month, or if tracking per-session IDs, union session counts).
6. **Best Courses:**
   - For each `course_title`, keep the entry with the strictly smaller `diff` (strokes to par).

---

## 4. Sync Engine (`Utils/Cloud/cloud_sync.gd` — Autoload `CloudSync`)

Register in `project.godot`:
`CloudSync="*res://Utils/Cloud/cloud_sync.gd"`

### 4.1 Signals & Methods
```gdscript
signal sync_started()
signal sync_completed(success: bool, synced_profiles: Array[String])
signal primary_profile_changed(player_name: String)

func mark_profile_dirty(player_name: String) -> void
func queue_completed_match(match_json: Dictionary) -> void
func sync_all_eligible_profiles(reason: String = "manual") -> void
func sync_single_profile(player_name: String, cloud_uid: String) -> Dictionary
```

### 4.2 Sync Triggers & Cost Discipline (Requirement G4 + Hole H23)
1. **On App Startup / Sign-In:**
   - When `CloudAuth.auth_state_changed` fires with `is_signed_in == true`, run `sync_all_eligible_profiles("startup")` in the background.
   - Eligible profiles = the local profile with `link_role == "primary"` + any local profiles with `link_role == "linked"` (Package 04).
   - **Cheap startup read optimization:** Read `profiles/{uid}` first (1 read). Only fetch `profiles/{uid}/sync/stats` (1 read) if `cloud_profile.rev != local_profile.last_synced_rev` OR the local profile has `dirty == true`.
2. **After Every Completed Match:**
   - Hook `MultiplayerManager.game_over` (or `save_current_match()` when `is_finished == true` and `not practice_mode_active`).
   - Extract a per-player match summary for each participant in the match whose local profile has `link_role in ["primary", "linked"]`, append it to `user://cloud_sync_state.json` (`pending_matches`), and immediately trigger `sync_all_eligible_profiles("match_finished")`.
3. **Every 30 Minutes of Active Foreground Usage:**
   - Maintain `_active_foreground_seconds: float = 0.0` in `_process(delta)`. Pause counting when the window is minimized/unfocused (`NOTIFICATION_APPLICATION_FOCUS_OUT` / `NOTIFICATION_APPLICATION_PAUSED`).
   - When `_active_foreground_seconds >= 1800.0` (30 minutes): reset timer, and **only if at least one synced profile is marked dirty**, call `sync_all_eligible_profiles("periodic_30m")`.
4. **Dirty Tracking & Crash Recovery:**
   - Persist `dirty_profiles` and `pending_matches` in `user://cloud_sync_state.json` whenever `record_global_shot`, `unlock_achievement`, `record_player_swing_issues`, `update_player_profile`, or `set_player_bag` runs for a synced profile.
   - If the user closes the app before the 30-minute timer fires, `NOTIFICATION_WM_CLOSE_REQUEST` / `NOTIFICATION_APPLICATION_PAUSED` saves `user://cloud_sync_state.json` immediately and attempts a fast non-blocking flush; anything still un-pushed is automatically pushed on next startup before pulling.

### 4.3 Idempotent Match Upload & Lifetime Counter Updates (Hole H2)
When uploading a pending match summary `M` for `cloud_uid`:
1. Send a single `FirestoreClient.commit_writes` batch containing:
   - **Write 1:** `CREATE` `profiles/{cloud_uid}/matches/{M.match_id}` with precondition `currentDocument.exists = false`.
   - **Write 2:** `TRANSFORM` on `profiles/{cloud_uid}`:
     - `lifetime.matches_played` → `increment(1)`
     - `lifetime.wins` / `losses` / `ties` / `single_player_completed` → `increment(1)`
     - `lifetime.holes_played` → `increment(M.holes_count)`
     - `lifetime.total_strokes` → `increment(M.strokes)`
     - `lifetime.total_par` → `increment(M.par)`
     - If valid par round: `lifetime.par_diff_sum` → `increment(M.to_par)`, `lifetime.par_diff_matches` → `increment(1)`
     - If 18-hole Standard round with `mulligans_used == 0`: `lifetime.best_to_par_18` → `minimum(M.to_par)`, `lifetime.best_gross_18` → `minimum(M.strokes)`
     - If 9-hole Standard round with `mulligans_used == 0`: `lifetime.best_to_par_9` → `minimum(M.to_par)`, `lifetime.best_gross_9` → `minimum(M.strokes)`
     - `lifetime.longest_drive_yds` → `maximum(M.longest_drive_yds)`
     - `lifetime.longest_putt_ft` → `maximum(M.longest_putt_ft)`
2. If Write 1 fails with `ALREADY_EXISTS` (HTTP 409), the match was already uploaded previously — remove it from `pending_matches` and do not double-increment!
3. Update `public_profiles/{cloud_uid}` with the latest leaderboard projection **only if at least one leaderboard field changed** compared to the last pushed projection (or delete `public_profiles/{cloud_uid}` if `leaderboard_opt_in == false`). Skipping redundant `public_profiles` writes when a 30-minute sync only updated club dispersion/swing issues saves 33% of periodic Firestore writes.

---

## 5. Players Menu UI Additions (`UI/PlayersMenu/players_menu.gd`)

1. **Top Cloud Account Bar:**
   - Displays current sign-in status: `"☁ Not Signed In — Sign In to Sync Stats"` button (opens `account_modal.tscn` from Package 02) vs `"☁ Signed in as user1@gmail.com [Sync Now] [Account]"`.
2. **Primary Profile Selector (on each player profile view in `_render_player_profile` L1374):**
   - If signed in:
     - Show a prominent badge/button in the profile header:
       - If this profile is the Primary Profile: green badge **`★ Primary Cloud Profile (Synced)`** with a subtle `"Unset Primary"` option.
       - If another profile (or none) is Primary: button **`☆ Set as Primary Cloud Profile`**.
     - Clicking **`Set as Primary Cloud Profile`** opens a confirmation dialog (Hole H24):
       - If cloud already has data for a different profile name, explain: *"Merge your cloud account stats with local profile '{player_name}' and make it your Primary Profile? Only your Primary Profile (and approved guest accounts) are synced to Firebase."*
     - When first signing in, if no local profile is marked Primary yet:
       - If a local profile's email matches `CloudAuth.get_email()`, or if only one local profile exists, prompt to link it as Primary, or create a new local profile from the cloud profile if the cloud account already has data from another device.
3. **Reserved Container for Package 04 & Full Controller Navigation:**
   - Inside `_render_player_profile`, create an `HBoxContainer` named `CloudLinkSection` right next to the Primary badge so Package 04 can inject its `"Link Secondary Account"` controls cleanly without merge conflicts.
   - Update `_update_controller_focus_navigation()` (`UI/PlayersMenu/players_menu.gd` L669) so the new Top Cloud Account Bar buttons (`Sign In / Account`, `Sync Now`), the `Primary Cloud Profile` button, and any buttons inside `CloudLinkSection` are seamlessly integrated into the D-pad / analog stick focus graph (`focus_neighbor_top/bottom/left/right`) with visible focus borders (`00_OVERVIEW.md` §6). Include `BudgetPausedBanner` from Package 02 at the top of the cloud bar so if the monthly $10 cloud budget is paused, the friendly pause notice is displayed automatically.

---

## 6. Verification & Unit Tests

Create `tests/test_cloud_sync_and_merge.gd`:
1. **Registry Migration & Rename:** Verify UUID assignment, primary role exclusivity, and that `rename_player_profile` updates club stats, achievements, and swing issues keys.
2. **StatsMerger Union & 200-Shot Cap:** Merge two diverging local/cloud shot lists (250 shots total), verify deduplication by `id`, chronological sorting, and capping at **200 shots** (`CLOUD_MAX_SHOTS_PER_CLUB = 200`) while preserving `_records.longest_drive_yds` and `_records.longest_putt_ft`.
3. **Tombstone Respect:** Verify that clearing club data on Device A at `t=200` deletes Device B's shots from `t=100` during merge while keeping shots hit at `t=250`.
4. **30-Minute Foreground Timer, Mobile Pause & Dirty Guard:** Verify that 30 minutes of simulated `_process` ticks with `dirty == false` performs **0** Firestore writes, with `dirty == true` performs **1** sync pass, and that backgrounding (`NOTIFICATION_APPLICATION_PAUSED` on Android/iOS) pauses the timer and saves `user://cloud_sync_state.json`.
5. **Controller Focus Navigation:** Instantiate `players_menu.tscn`, verify the Cloud Account Bar and Primary Profile buttons have `FOCUS_ALL` and valid focus neighbors in `_update_controller_focus_navigation()`.
