# Work Package 07 — Online Multiplayer Lobby: Host, Join by Code, Public Browser & Course Sync

> **Prerequisite:** Read [`00_OVERVIEW.md`](00_OVERVIEW.md), [`01_FIREBASE_BACKEND_SCHEMA_RULES.md`](01_FIREBASE_BACKEND_SCHEMA_RULES.md), and [`02_GODOT_FIREBASE_CLIENT_AND_AUTH.md`](02_GODOT_FIREBASE_CLIENT_AND_AUTH.md).
> **Depends on:** Package 02 (`RtdbClient` + `RtdbStream` + `CloudAuth.ensure_anonymous_session()`). Package 05 already creates the Main Menu `Multiplayer` button routing to `res://UI/OnlineMultiplayer/multiplayer_menu.tscn`.
> **Owns:** `Utils/Cloud/online_session.gd` (Autoload `OnlineSession` — lobby phase), `Utils/Cloud/course_fingerprint.gd`, `UI/OnlineMultiplayer/multiplayer_menu.tscn`, `UI/OnlineMultiplayer/multiplayer_menu.gd`, `tests/test_online_lobby_and_course_check.gd`.

---

## 1. Scope & Goals

1. Build the **Online Multiplayer Menu** (`res://UI/OnlineMultiplayer/multiplayer_menu.tscn/.gd`) with three tabs/flows:
   - **Host Match:** Select a downloaded catalog/OSM course, match settings (course length, game mode, turn order, wind, green speed, Private vs Public visibility), add 1 or more local golfers from this device, and generate a **6-character Join Code** (`ABCDEFGHJKMNPQRSTUVWXYZ23456789`).
   - **Join by Code:** Paste or type a 6-character code (`VirtualKeyboardManager` + clipboard paste button) to join a private or public match in `"lobby"` status.
   - **Public Matches Browser:** Browse all un-started public lobbies (`status == "lobby"`) showing Course Title, # of Holes (`course_length`), Game Mode, Host Name, and Player Count (`2/4`), and join with one click.
2. **Course Installation & Fingerprint Verification (Hole H12):**
   - If a joining player does not have the match's course installed locally (matched by `course_key = slug(title) + "@" + round(lat,4) + "," + round(lon,4)`), or if their local `course_fingerprint` does not match the host's `course_fingerprint`, prompt them right inside the lobby to **Download & Generate Course** using `OsmMapLoader.DownloadAndGenerateCourse(lat, lon, title, is_cached, location)`.
   - Track each device's `course_ready` and `ready` state in RTDB (`/matches/{matchId}/devices/{uid}`).
3. **Start Match & Code Locking (Requirement G8 + Hole H15):**
   - Once all connected devices have `course_ready == true`, the Host clicks **Start Match**.
   - Starting the match atomically deletes `/codes/{CODE}` and `/lobbies/{matchId}` and sets `/matches/{matchId}/meta/status = "active"`, so the join code no longer works and the match disappears from the public browser.

---

## 2. Course Identity & Fingerprint (`Utils/Cloud/course_fingerprint.gd`)

### 2.1 Why Folder Names Cannot Be Used (Hole H12)
In `Courses/OsmMapLoader.cs` (`L815–845`), course folder names under `user://courses/` are dynamically disambiguated if another course shares a similar name. Therefore, two players might have the same course in different directory names, or different courses with similar names.

### 2.2 Canonical `course_key` and `course_fingerprint`
```gdscript
class_name CourseFingerprint
extends RefCounted

# Reads course.json and returns:
# {
#   "ok": bool,
#   "title": String,
#   "key": String,            # e.g. "augusta_national_golf_club@33.5022,-82.0225"
#   "lat": float,
#   "lon": float,
#   "location": String,
#   "is_custom": bool,
#   "is_cached": bool,
#   "fingerprint": String,    # 40-char sha1 hex of sorted Hole Info (par + rounded tee/green coords)
#   "hole_ids": Array[String],
#   "scene_path": String,
#   "config_path": String
# }
static func inspect_course_config(config_path: String) -> Dictionary

# Scans user://courses for a course matching course_key (or lat/lon within 200m + same normalized title)
static func find_installed_course(course_key: String, lat: float, lon: float, title: String) -> Dictionary
```
- **Fingerprint algorithm:**
  1. Sort `Hole Info` keys using `MultiplayerManager.get_hole_number_from_id(str(k))`.
  2. For each hole, append `"%s:P%d:G%.1f,%.1f,%.1f" % [hole_id, par, green_x, green_y, green_z]` plus sorted tee box keys `"%s:%.1f,%.1f,%.1f"` (coordinates rounded to `0.5m` to avoid floating-point text-formatting noise across platforms).
  3. Return `.sha1_text()`.
- **Custom Course Restriction in v1:**
  - If `course.get("is_custom", false)` is true or `lat == 0.0 and lon == 0.0`, disable hosting that course online with tooltip: *"Custom local courses cannot be hosted online yet because remote players cannot download them from the course catalog."*

---

## 3. `OnlineSession` Autoload — Lobby API (`Utils/Cloud/online_session.gd`)

Register in `project.godot`:
`OnlineSession="*res://Utils/Cloud/online_session.gd"`

```gdscript
extends Node

signal lobby_updated(meta: Dictionary, devices: Dictionary, golfers: Dictionary)
signal public_lobbies_loaded(lobbies: Array[Dictionary])
signal lobby_error(code: String, message: String)
signal course_install_required(course_info: Dictionary, reason: String) # "missing" | "fingerprint_mismatch"
signal match_started(match_id: String, meta: Dictionary, golfers: Array[Dictionary])
signal lobby_closed(reason: String)

const ONLINE_PROTOCOL_VERSION := 1
const MAX_GOLFERS := 4
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789" # No 0/O/1/I/L

var is_online_match: bool = false
var current_match_id: String = ""
var is_host: bool = false
var current_join_code: String = ""
var match_meta: Dictionary = {}
var match_devices: Dictionary = {}
var match_golfers: Dictionary = {}

# Host actions
func create_lobby(course_config_path: String, settings: Dictionary, visibility: String, local_golfers: Array[Dictionary]) -> Dictionary
func update_lobby_settings(settings: Dictionary) -> Dictionary
func kick_device(target_uid: String) -> Dictionary
func start_online_match() -> Dictionary

# Joiner / Browser actions
func fetch_public_lobbies() -> Array[Dictionary]
func join_by_code(code: String, local_golfers: Array[Dictionary]) -> Dictionary
func join_by_match_id(match_id: String, local_golfers: Array[Dictionary]) -> Dictionary
func set_local_course_ready(ready: bool, local_scene_path: String, local_config_path: String) -> void
func set_local_device_ready(ready: bool) -> void
func add_local_golfer_to_lobby(golfer_config: Dictionary) -> Dictionary
func remove_local_golfer_from_lobby(slot_id: String) -> Dictionary
func leave_lobby() -> void
```

---

## 4. Lobby Lifecycle & Edge Cases

### 4.1 Anonymous Auth Fallback (Decision D10)
Before any lobby call (`create_lobby`, `join_by_code`, `fetch_public_lobbies`), call:
```gdscript
if not CloudAuth.is_authenticated_any():
    var auth_res = await CloudAuth.ensure_anonymous_session()
```
So players who choose not to create a cloud account can still host and join online matches seamlessly.

### 4.2 Collision-Safe Join Code Reservation (Hole H15)
When `create_lobby()` generates a 6-character code `CODE`:
1. Create `/matches/{matchId}` first via `RtdbClient.post_path("matches", initial_match_payload)`.
2. Claim `/codes/{CODE}` using `RtdbClient.put_path("codes/" + CODE, {"match_id": match_id, "host_uid": my_uid, "created_at": now}, "null_etag")`.
3. If `put_path` returns HTTP `412 Precondition Failed` (code collision), generate a new 6-char code and retry (up to 5 attempts).
4. If `visibility == "public"`, write `/lobbies/{matchId}`.

### 4.3 Supported Online Game Modes & Determinism Seeds (Holes H11, H17, H27)
- **Allowed `game_mode` options in Online Host setup:** `"Standard"`, `"Skins"`, `"Closest to Pin"`. (Hide `"Scramble"` and `"2v2 Scramble"` in online mode per Hole H17.)
- **Allowed `turn_order_mode` options:** `"Stay Up"`, `"Classic"`, `"Full Hole"`.
- **Shared Wind & Pin Seed (Hole H11):**
  - When creating the lobby (or toggling Wind in lobby settings), the Host generates:
    - `wind_speed_mph` and `wind_dir_rad` (using `GlobalSettings` wind picker)
    - `pin_seed = randi()`
    - Host's current gimme settings (`gimme_1_enabled`, `gimme_1_dist_ft`, etc.), `green_speed`, `random_pin_enabled`, `ball_rollout_enabled`.
  - All of these are stored in `/matches/{matchId}/meta/settings` so every client uses identical round conditions.

### 4.4 Immediate Removal of Un-Started Public Lobbies When Host Leaves or Logs Off (Hole H14)
To guarantee users never see or try to join a public lobby that will never start because the host logged off, closed the app, or walked away without cancelling:
1. **Immediate Cleanup on Host Leave / Logoff / App Close / Mobile Backgrounding:**
   - When `is_host == true` and `meta.status == "lobby"`:
     - Clicking **`← Back / Cancel Lobby`** in `multiplayer_menu.gd`
     - Signing out (`CloudAuth.auth_state_changed` with `is_signed_in == false`)
     - Closing the window (`NOTIFICATION_WM_CLOSE_REQUEST` on Windows/macOS/Linux)
     - Backgrounding the app (`NOTIFICATION_APPLICATION_PAUSED` on Android/iOS while still in an un-started lobby)
     immediately calls `leave_lobby()`, which deletes `/lobbies/{current_match_id}`, `/codes/{current_join_code}`, and `/matches/{current_match_id}`.
2. **Tight 20-Second Heartbeat & 45-Second Auto-Purge:**
   - While in a lobby, every connected device updates `/matches/{matchId}/devices/{my_uid}/last_seen` every **20 seconds**.
   - If `is_host` and `visibility == "public"`, the host also updates `/lobbies/{matchId}/last_seen` every **20 seconds**.
   - When `fetch_public_lobbies()` runs:
     - Any lobby with `now - lobby.last_seen > 45` (45 seconds without a host heartbeat) is **excluded from the list AND immediately deleted** via a fire-and-forget `RtdbClient.delete_path("lobbies/" + stale_id)` (explicitly permitted by `database.rules.json` whenever `last_seen < (now/1000) - 45`).
3. **Pre-Join Host Liveness Check:**
   - When a joiner clicks **Join** on a public lobby or submits a 6-character code, `OnlineSession` fetches `/matches/{matchId}` and checks `meta.status == "lobby"` and `now - devices[meta.host_uid].last_seen <= 45`.
   - If the host's heartbeat is older than 45 seconds, `OnlineSession` deletes `/lobbies/{matchId}` and returns `"That lobby is no longer active (the host disconnected)."` instead of placing the player into a dead lobby.

### 4.5 Course Installation Inside the Lobby (Requirement G8 + Hole H12)
When a joiner enters a lobby (`join_by_code` or `join_by_match_id`):
1. Run `CourseFingerprint.find_installed_course(meta.course.key, meta.course.lat, meta.course.lon, meta.course.title)`.
2. **Case A — Installed & `fingerprint == meta.course.fingerprint`:**
   - Immediately call `set_local_course_ready(true, found.scene_path, found.config_path)`.
3. **Case B — Not installed OR `fingerprint != meta.course.fingerprint`:**
   - Set `course_ready = false` on `/matches/{matchId}/devices/{my_uid}`.
   - Display an inline **"Course Required"** banner in the lobby room with a **`Download & Install "{course.title}"`** button.
   - Clicking it instantiates `OsmMapLoader` (or opens `osm_download_dialog.tscn` pre-targeted to `meta.course.lat, meta.course.lon, meta.course.title, meta.course.is_cached, meta.course.location`), awaits `CourseGenerated`, re-verifies the course, and sets `course_ready = true`.
4. The Host's **Start Match** button is enabled only when:
   - `match_golfers.size() >= 2` (and `<= MAX_GOLFERS`), AND
   - Every active device in `match_devices` (with `now - last_seen < 120`) has `course_ready == true` and `ready == true`.

### 4.6 Starting the Match & Locking the Code
When the Host clicks **Start Match**:
1. Sort `match_golfers.values()` by `order` (`slot_0`, `slot_1`, …).
2. Set `meta.status = "active"`, `meta.started_at = now`, `meta.turn = {"hole_index": 0, "active_slot": first_slot.slot_id, "active_owner_uid": first_slot.owner_uid, "next_seq": 1, "updated_at": now}`.
3. Delete `/codes/{current_join_code}` and (if public) `/lobbies/{current_match_id}`.
4. All clients watching the lobby via `RtdbStream` see `meta.status == "active"` and emit `match_started`, which hands off to Package 09 (`OnlineMatchController`) to configure `MultiplayerManager.setup_game(...)` and call `SceneManager.load_course(local_scene_path, local_config_path)`.

### 4.7 Mandatory Controller Support, Cross-Platform Layout & Budget Banner (`00_OVERVIEW.md` §§6, 7, 10)
1. **Budget-Paused Banner:** Place `BudgetPausedBanner` (Package 02) at the top of `multiplayer_menu.gd`. If `CloudAuth.is_cloud_service_paused()` is `true`, disable the `Host Match` and `Join` buttons and show the friendly monthly-budget-reached message.
2. **Full Controller / Gamepad Navigation:**
   - Implement `_update_controller_focus_navigation()` across all 3 lobby views (`Host Setup`, `Join by Code` with `VirtualKeyboardManager`, `Public Matches Browser` with `follow_focus = true` and `TouchScrollHelper`, and the `Waiting Room Lobby` view including the `Download & Install Course` button, `Copy Code` button, and `Start Match` button).
   - Handle `ui_cancel` (B button / Escape) to leave the lobby (prompting confirmation if hosting an active lobby) or return to the Main Menu.

---

## 5. Verification & Unit Tests

Create `tests/test_online_lobby_and_course_check.gd`:
1. **Course Fingerprint Determinism:** Load `Courses/UserCourses/Airways/course.json`, compute `inspect_course_config`, and verify that key and SHA-1 fingerprint are deterministic and sensitive to par/tee changes.
2. **Join Code Generation & Collision Retry:** Mock `RtdbClient.put_path` returning `412` on the first code and `200` on the second, verifying `create_lobby` retries and succeeds.
3. **Abandoned Public Lobby Cleanup (Hole H14):**
   - Verify that calling `leave_lobby()` or simulating host sign-out/exit immediately deletes `/lobbies/{matchId}` and `/codes/{CODE}`.
   - Feed `fetch_public_lobbies()` one active lobby (`last_seen = now - 10`) and one stale lobby (`last_seen = now - 50`), and assert that the stale lobby is filtered out of the returned list and `delete_path("lobbies/" + stale_id)` is called.
4. **Start Match Preconditions:** Verify `start_online_match()` refuses to start if any device has `course_ready == false`, and when all devices are ready, deletes `/codes/{CODE}` and `/lobbies/{matchId}` and transitions `meta.status` to `"active"`.
5. **Controller Focus Navigation Test:** Instantiate `multiplayer_menu.tscn` and verify D-pad focus neighbors across tabs, code entry, public lobby rows, and lobby room controls.
