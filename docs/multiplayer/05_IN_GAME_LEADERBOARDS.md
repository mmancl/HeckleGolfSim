# Work Package 05 — Main Menu Tiles & In-Game Leaderboards

> **Prerequisite:** Read [`00_OVERVIEW.md`](00_OVERVIEW.md), [`01_FIREBASE_BACKEND_SCHEMA_RULES.md`](01_FIREBASE_BACKEND_SCHEMA_RULES.md), and [`02_GODOT_FIREBASE_CLIENT_AND_AUTH.md`](02_GODOT_FIREBASE_CLIENT_AND_AUTH.md).
> **Depends on:** Package 02 `FirestoreClient` API stub (can build & test immediately using mock data).
> **Owns:** `UI/MainMenu/main_menu.tscn`, `UI/MainMenu/main_menu.gd` (adding **both** new tiles: **Leaderboards** and **Multiplayer** so Package 07 doesn't collide on `main_menu`), `UI/Leaderboards/leaderboards_menu.tscn`, `UI/Leaderboards/leaderboards_menu.gd`, `Utils/Cloud/leaderboard_service.gd`, `tests/test_leaderboards_menu.gd`.

---

## 1. Scope & Goals

1. Add the two new main menu sections requested in G7 and G8 to `UI/MainMenu/main_menu.tscn` and `UI/MainMenu/main_menu.gd`:
   - **Multiplayer** tile → routes to `res://UI/OnlineMultiplayer/multiplayer_menu.tscn` (created by Package 07; if not yet present on the branch, show a friendly toast or fallback dialog).
   - **Leaderboards** tile → routes to `res://UI/Leaderboards/leaderboards_menu.tscn`.
2. Build the **Leaderboards Menu** (`UI/Leaderboards/leaderboards_menu.tscn/.gd`) showing global rankings across all requested categories:
   - **Longest Drive** (`longest_drive_yds` DESC)
   - **Longest Putt** (`longest_putt_ft` DESC)
   - **Lowest Score (18 Holes)** (`best_to_par_18` ASC, displaying both To-Par and Gross `best_gross_18`)
   - **Lowest Score (9 Holes)** (`best_to_par_9` ASC, displaying both To-Par and Gross `best_gross_9`)
   - **Most Achievements Earned** (`achievements_count` DESC)
   - **Most Games Played** (`matches_played` DESC)
   - **Most Wins** (`wins` DESC)
3. Work **without requiring sign-in** (reads world-readable `public_profiles`), while highlighting the signed-in user's row (and any local linked profiles' rows) when signed in.
4. Keep Firestore read cost low via a **10-minute in-memory + disk cache** (`user://leaderboard_cache.json`) and a `limit(25)` query cap (Hole H21).

---

## 2. Main Menu Layout Update (`UI/MainMenu/main_menu.tscn` & `.gd`)

Currently `main_menu.tscn` has 6 tiles inside `VerticalLayout/TilesRow`:
`CoursesTile`, `RangeTile`, `PracticeTile`, `MiniGamesTile`, `HistoryTile`, `PlayersTile`.

### 2.1 Adding `MultiplayerTile` and `LeaderboardsTile`
- Add two new `PanelContainer` tiles matching the exact card structure (`TextureRect` + `TextBackdrop` + `Button`) and styling loop in `main_menu.gd` (`L55–83`):
  1. `MultiplayerTile` (`MultiplayerButton`, label `"Multiplayer"`): place right after `CoursesTile` (or in a clean 2-row × 4-column grid / responsive `HFlowContainer` or 8-tile row depending on aspect ratio so cards never clip on 1728×972 or mobile screens).
  2. `LeaderboardsTile` (`LeaderboardsButton`, label `"Leaderboards"`): place next to `HistoryTile` / `PlayersTile`.
- Ensure controller focus navigation (`focus_neighbor_left`, `focus_neighbor_right`, `focus_neighbor_top`, `focus_neighbor_bottom`) connects all 8 tiles and the top bar buttons (`_settings_button`, `_credits_button`, `_exit_button`).
- Button handlers in `main_menu.gd`:
  ```gdscript
  func _on_multiplayer_pressed() -> void:
      const MP_SCENE := "res://UI/OnlineMultiplayer/multiplayer_menu.tscn"
      if ResourceLoader.exists(MP_SCENE):
          SceneManager.change_scene(MP_SCENE)
      else:
          push_warning("[MainMenu] Online Multiplayer scene not installed yet.")

  func _on_leaderboards_pressed() -> void:
      SceneManager.change_scene("res://UI/Leaderboards/leaderboards_menu.tscn")
  ```

---

## 3. Leaderboard Service (`Utils/Cloud/leaderboard_service.gd`)

```gdscript
class_name LeaderboardService
extends RefCounted

const CACHE_TTL_SEC := 600 # 10 minutes
const DEFAULT_LIMIT := 25

const CATEGORIES: Array[Dictionary] = [
    {
        "id": "longest_drive",
        "title": "Longest Drive",
        "field": "longest_drive_yds",
        "dir": "DESCENDING",
        "unit": "yds",
        "decimals": 1
    },
    {
        "id": "longest_putt",
        "title": "Longest Putt",
        "field": "longest_putt_ft",
        "dir": "DESCENDING",
        "unit": "ft",
        "decimals": 1
    },
    {
        "id": "lowest_score_18",
        "title": "Lowest Score (18H)",
        "field": "best_to_par_18",
        "secondary_field": "best_gross_18",
        "dir": "ASCENDING",
        "unit": "to_par",
        "decimals": 0
    },
    {
        "id": "lowest_score_9",
        "title": "Lowest Score (9H)",
        "field": "best_to_par_9",
        "secondary_field": "best_gross_9",
        "dir": "ASCENDING",
        "unit": "to_par",
        "decimals": 0
    },
    {
        "id": "most_achievements",
        "title": "Most Achievements",
        "field": "achievements_count",
        "dir": "DESCENDING",
        "unit": "count",
        "decimals": 0
    },
    {
        "id": "most_games",
        "title": "Most Games Played",
        "field": "matches_played",
        "dir": "DESCENDING",
        "unit": "games",
        "decimals": 0
    },
    {
        "id": "most_wins",
        "title": "Most Wins",
        "field": "wins",
        "dir": "DESCENDING",
        "unit": "wins",
        "decimals": 0
    }
]

# Returns {"ok": bool, "entries": Array[Dictionary], "from_cache": bool, "updated_at": int, "error": String}
func fetch_category(category_id: String, force_refresh: bool = false) -> Dictionary
func format_metric_value(category_def: Dictionary, doc: Dictionary) -> String
```

### 3.1 Query & Formatting Details
- Calls `CloudAuth.firestore.run_query("public_profiles", [], [{"field": cat.field, "dir": cat.dir}], DEFAULT_LIMIT)`.
- Note: `FirestoreClient.run_query` on `public_profiles` does **not** require an `Authorization` header (world-readable per `firestore.rules`), so signed-out users never need even an anonymous token just to view leaderboards.
- For `lowest_score_18` (`unit == "to_par"`):
  - Format `best_to_par_18 == 0` as `"E (72)"`, `-3` as `"-3 (69)"`, `+4` as `"+4 (76)"` using `best_gross_18` when present.
  - Break ties on `best_to_par_18` client-side by `best_gross_18` ascending.

---

## 4. Leaderboards Scene UI (`UI/Leaderboards/leaderboards_menu.gd`)

1. **Header Bar:**
   - `← Back` button (returns to `res://UI/MainMenu/main_menu.tscn`, wired to `ui_cancel`).
   - Title: `"Global Leaderboards"`.
   - Right side: `"Updated X min ago"` label + `↻ Refresh` button (throttled to at most once per 30 seconds) + `☁ Account` button (opens Package 02's `account_modal.tscn` so signed-out users can easily sign in to post their own scores).
2. **Category Tabs Bar (Horizontal scrollable / controller-navigable pill buttons):**
   - One pill button per entry in `LeaderboardService.CATEGORIES`.
3. **Leaderboard Table (`ScrollContainer` with `TouchScrollHelper`):**
   - Columns: **Rank (`#1` 🥇, `#2` 🥈, `#3` 🥉, `#4`…)** | **Player (Avatar + Display Name + Skill badge)** | **Stat Value (Primary + Secondary subtitle)**.
   - Highlight rows where `entry.uid == CloudAuth.get_uid()` (gold/cyan border + `"YOU"` badge) or where `entry.uid` matches a local linked friend profile (`"FRIEND"` badge).
4. **Bottom "Your Personal Best" Strip:**
   - Shows the local Primary Player's current stat in the selected category alongside their cloud sync status (`"Synced to Leaderboard"` vs `"Sign in on the Players page to post your stats to global leaderboards"`).
5. **Offline / Empty State & Budget-Paused Banner:**
   - Include `BudgetPausedBanner` (Package 02) below the header bar so if `system/status.paused == true`, the user sees the friendly monthly-budget-paused message while still being able to browse existing leaderboard rankings.
   - If offline and cached data exists in `user://leaderboard_cache.json`, display the cached board with an `"Offline — showing cached rankings"` banner.
6. **Mandatory Controller / Gamepad Support (`00_OVERVIEW.md` §6):**
   - Implement `_update_controller_focus_navigation()` linking the top bar (`← Back`, `↻ Refresh`, `☁ Account`), the 7 category tab buttons (Left/Right cycles tabs; Down enters the first leaderboard row; Up goes to the header bar), and each focusable leaderboard row inside the `ScrollContainer` (`follow_focus = true`, `TouchScrollHelper` attached).
   - Pressing `ui_cancel` (B button / Escape) returns to `res://UI/MainMenu/main_menu.tscn`.
   - Apply `ScreenOffsetManager` and test across desktop (`1728×972`) and mobile aspect ratios.

---

## 5. Verification & Unit Tests

Create `tests/test_leaderboards_menu.gd`:
1. **Formatting & Tie-Breaking:** Test `format_metric_value` across `longest_drive`, `longest_putt`, `lowest_score_18` (`-2 (70)`, `E (72)`, `+5 (77)`), and `most_achievements`.
2. **Cache TTL Behavior:** Verify that calling `fetch_category("longest_drive")` twice within 10 minutes makes only **1** query to `FirestoreClient`, and `force_refresh = true` bypasses the cache.
3. **Main Menu & Leaderboards Controller Navigation:** Instantiate `main_menu.tscn` and `leaderboards_menu.tscn`, verify all 8 main menu buttons exist and have valid controller focus neighbors (`focus_neighbor_left/right/top/bottom`), verify category tab switching and D-pad row focus traversal in `leaderboards_menu`, and verify `ui_cancel` handling.
