# Work Package 02 — Godot Firebase Client Layer, Budget Guard & Authentication UI

> **Prerequisite:** Read [`00_OVERVIEW.md`](00_OVERVIEW.md) and [`01_FIREBASE_BACKEND_SCHEMA_RULES.md`](01_FIREBASE_BACKEND_SCHEMA_RULES.md).
> **Can start:** Immediately (Phase 0). **Publish the public API stub (`CloudAuth`, `FirestoreClient`, `RtdbClient`) in your first commit** so Packages 03, 05, and 07 can code against it in parallel.
> **Owns:** `Utils/Cloud/cloud_auth.gd` (Autoload `CloudAuth`), `Utils/Cloud/firestore_client.gd`, `Utils/Cloud/rtdb_client.gd`, `Utils/Cloud/rtdb_stream.gd`, `UI/Account/account_modal.gd`, `UI/Account/account_modal.tscn`, `UI/Account/budget_paused_banner.gd`, `tests/test_cloud_auth_and_clients.gd`.

---

## 1. Scope & Goals

1. Provide a pure-GDScript, zero-native-plugin Firebase client layer (`CloudAuth`, `FirestoreClient`, `RtdbClient`, `RtdbStream`) that works identically across **Windows, macOS, Linux, Android, and iOS** (including sideloaded iOS/macOS builds) with zero regressions to offline play.
2. Support optional **Email/Password** (sign-up, sign-in, password reset, email verification) and **Google Sign-In** (enabled on **all** platforms including iOS/macOS via OAuth 2.0 Device Authorization Flow + Desktop Loopback PKCE) plus automatic **Anonymous Auth** for signed-out online multiplayer.
3. Detect when the **$10/month cloud budget pause (`system/status.paused == true`)** is active and display a friendly, reusable banner/dialog across cloud UI screens:
   > **"Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."**
4. Persist refresh tokens securely on disk (`user://cloud_auth.dat`), auto-refresh ID tokens before expiry, and recover cleanly when offline or resuming from mobile backgrounding.
5. Build the in-game **Account Modal** (`UI/Account/account_modal.tscn/.gd`) with **100% controller/gamepad navigation**, `VirtualKeyboardManager`, `UIFocusGuard`, and `ScreenOffsetManager` support.

---

## 2. Public API Contract (Freeze on Day 1)

### 2.1 Autoload `CloudAuth` (`res://Utils/Cloud/cloud_auth.gd`)
Register in `project.godot` under `[autoload]`:
`CloudAuth="*res://Utils/Cloud/cloud_auth.gd"`

```gdscript
extends Node

signal auth_state_changed(is_signed_in: bool, user: Dictionary)
signal google_device_code_received(user_code: String, verification_url: String, expires_in: int)
signal auth_error(code: String, message: String)
signal account_deleted()
signal cloud_service_paused_changed(is_paused: bool, message: String)

const DEFAULT_BUDGET_PAUSE_MESSAGE := "Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."

# User dictionary keys:
# {
#   "uid": String,
#   "email": String,
#   "display_name": String,
#   "email_verified": bool,
#   "is_anonymous": bool,
#   "provider_id": String # "password", "google.com", "anonymous"
# }

func is_signed_in() -> bool # true only for non-anonymous accounts
func is_authenticated_any() -> bool # true for signed-in OR anonymous session
func get_uid() -> String
func get_email() -> String
func get_display_name() -> String
func is_email_verified() -> bool
func is_anonymous() -> bool
func get_valid_id_token() -> String # awaits refresh if < 5 min remaining

# Cloud budget circuit-breaker status
func is_cloud_service_paused() -> bool
func get_cloud_pause_message() -> String
func check_cloud_service_status() -> Dictionary # Reads system/status on startup or when a 403 occurs

# Auth actions (all async, return Dictionary {"ok": bool, "user": Dictionary, "error": String})
func sign_up_email(email: String, password: String, display_name: String) -> Dictionary
func sign_in_email(email: String, password: String) -> Dictionary
func send_password_reset(email: String) -> Dictionary
func send_email_verification() -> Dictionary
func reload_user_profile() -> Dictionary

func start_google_sign_in() -> Dictionary # Enabled on ALL platforms (Windows, macOS, Linux, Android, iOS)
func cancel_google_sign_in() -> void

func ensure_anonymous_session() -> Dictionary # Used by OnlineSession if not signed in
func sign_out() -> void
func delete_account_and_cloud_data(reauth_password: String = "") -> Dictionary

# Shared clients instantiated and owned by CloudAuth:
var firestore: FirestoreClient
var rtdb: RtdbClient
```

### 2.2 `FirestoreClient` (`class_name FirestoreClient`)
Wraps `https://firestore.googleapis.com/v1/projects/{projectId}/databases/(default)/documents`.

```gdscript
class_name FirestoreClient
extends RefCounted

# Automatic conversion between GDScript Dictionary/Array/int/float/bool/String/null
# and Firestore Value format (mapValue, arrayValue, integerValue, doubleValue, booleanValue, stringValue, nullValue).

# Returns {"ok": bool, "status": int, "data": Dictionary, "update_time": String, "error": String, "budget_paused": bool}
func get_doc(doc_path: String, require_auth: bool = true) -> Dictionary
func set_doc(doc_path: String, fields: Dictionary, update_mask: PackedStringArray = [], update_time: String = "", current_document_exists: Variant = null) -> Dictionary
func delete_doc(doc_path: String) -> Dictionary
func run_query(collection_id: String, where_filters: Array = [], order_by: Array = [], limit: int = 25, require_auth: bool = false) -> Dictionary
func commit_writes(writes: Array) -> Dictionary
```
- **Automatic Budget-Pause Detection:** Whenever a Firestore write or RTDB request returns HTTP `403 PERMISSION_DENIED`, `FirestoreClient` / `RtdbClient` checks `CloudAuth.check_cloud_service_status()`. If `system/status.paused == true`, it sets `"budget_paused": true`, `"error": CloudAuth.get_cloud_pause_message()`, and emits `CloudAuth.cloud_service_paused_changed(true, message)`.

### 2.3 `RtdbClient` & `RtdbStream` (`class_name RtdbClient`, `class_name RtdbStream`)
Wraps `{databaseURL}/{path}.json?auth={idToken}`.

```gdscript
class_name RtdbClient
extends RefCounted

# Returns {"ok": bool, "status": int, "data": Variant, "etag": String, "error": String, "budget_paused": bool}
func get_path(path: String, query_params: Dictionary = {}, with_etag: bool = false) -> Dictionary
func put_path(path: String, data: Variant, if_match_etag: String = "") -> Dictionary # Pass "null_etag" to require non-existent
func patch_path(path: String, data: Dictionary) -> Dictionary
func post_path(path: String, data: Variant) -> Dictionary # Push ID generation
func delete_path(path: String) -> Dictionary
func open_stream(path: String) -> RtdbStream
```

---

## 3. Google Sign-In on All Platforms (Windows, macOS, Linux, Android, Sideloaded iOS)

Per Owner Decision D4, macOS and iOS are sideloaded builds, so **Google Sign-In must be visible and enabled on all 5 platforms (`Windows`, `macOS`, `Linux`, `Android`, `iOS`)** — do not hide it on iOS/macOS.

### 3.1 Primary Universal Flow: Google OAuth 2.0 Device Authorization Grant
1. Works identically on Windows, macOS, Linux, Android, and sideloaded iOS without needing platform-specific native plugins or App Store URL-scheme entitlements.
2. Request device code:
   ```
   POST https://oauth2.googleapis.com/device/code
   Content-Type: application/x-www-form-urlencoded
   client_id={googleDeviceClientId}&scope=openid%20email%20profile
   ```
3. Display the 8-character `user_code` in large bold text alongside:
   - **`Copy Code & Open Google Sign-In`** button (copies `user_code` via `DisplayServer.clipboard_set(user_code)` and opens `https://www.google.com/device` via `OS.shell_open()`).
   - Instructions so simulator PC/projector users can also just open `google.com/device` on their phone.
4. Poll `https://oauth2.googleapis.com/token` every `interval` seconds until approved, then exchange `id_token` with Firebase via `POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key={apiKey}`.

### 3.2 Desktop Convenience Option: Loopback Redirect + PKCE
On desktop (`OS.get_name() in ["Windows", "macOS", "Linux"]`), if `googleDesktopClientId` is configured in `firebase_config.json`, also support 1-click browser sign-in via a temporary `TCPServer` bound to `127.0.0.1:0`.

---

## 4. Reusable Budget-Paused Banner (`UI/Account/budget_paused_banner.gd`)

Create a small, reusable `PanelContainer` component (`class_name BudgetPausedBanner`) that connects to `CloudAuth.cloud_service_paused_changed` and automatically shows/hides itself at the top of:
- `account_modal.gd` (Package 02)
- `players_menu.gd` cloud bar (Package 03)
- `leaderboards_menu.gd` (Package 05)
- `multiplayer_menu.gd` (Package 07)

When `CloudAuth.is_cloud_service_paused()` is `true`, it displays a friendly amber/gold card:
> **"Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."**
*(Subtitle: "Local single-player, local pass-and-play multiplayer, driving range, and local stats continue to work normally.")*

---

## 5. Account Modal UI & Full Controller Support (`UI/Account/account_modal.gd`)

Must strictly follow [`00_OVERVIEW.md` §6 (Controller Support)](00_OVERVIEW.md#6-mandatory-controller--gamepad-support-standard-all-ui-packages-02-03-04-05-07-09) and [`§7 (Cross-Platform Compatibility)`](00_OVERVIEW.md#7-cross-platform-compatibility--zero-regression-guarantee-windows-macos-linux-android-ios):
1. **Controller Navigation & Focus Management:**
   - Register modal lock with `/root/UIFocusGuard` on open and pop on close.
   - Implement `_update_controller_focus_navigation()` setting explicit `focus_neighbor_top/bottom/left/right` on all tabs, `LineEdit` inputs, `Sign In` / `Continue with Google` / `Close` buttons.
   - Wire all `LineEdit` controls (`email_input`, `password_input`, `display_name_input`) to `/root/VirtualKeyboardManager`.
   - Handle `ui_cancel` (B button / Escape) to close the modal cleanly (ignoring `KEY_BACKSPACE` while a `LineEdit` has focus).
2. **Leaderboard Opt-In Default (Owner Decision D6):**
   - When creating a new `users/{uid}` document on first sign-in, set `"leaderboard_opt_in": true` by default.
   - Provide a `CheckButton` in the signed-in view: **"Show my stats on public leaderboards"** (default checked; unchecking sets `leaderboard_opt_in = false` and deletes `public_profiles/{uid}`).

---

## 6. Verification & Unit Tests

Create `tests/test_cloud_auth_and_clients.gd`:
1. **Firestore Value Serializer/Deserializer:** Round-trip test converting nested GDScript Dictionaries, Arrays, ints, floats, bools, nulls, and strings to Firestore REST JSON format and back.
2. **Token Expiry & Refresh Deduplication:** Verify concurrent requests awaiting `get_valid_id_token()` trigger only 1 HTTP refresh call.
3. **Budget Pause Detection:** Simulate `system/status` returning `{"paused": true, "message": "..."}` and verify `CloudAuth.is_cloud_service_paused()` becomes `true`, `cloud_service_paused_changed` emits, and `BudgetPausedBanner` becomes visible with the exact friendly message.
4. **SSE Parser (`RtdbStream`):** Verify chunked `event: put` and `event: patch` frames parse accurately.
5. **Controller Focus Traversal Test:** Instantiate `account_modal.tscn`, verify Google Sign-In button is visible on all platforms (including when simulating iOS/macOS), verify `_update_controller_focus_navigation()` wires valid neighbor paths, and assert focus transitions cleanly across all controls.
