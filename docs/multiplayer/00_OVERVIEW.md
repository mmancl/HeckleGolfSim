# Online Accounts, Cloud Sync, Leaderboards & Online Multiplayer — Master Design

> **Audience:** the human owner + every implementation agent. Each agent gets its own work-package doc
> (`01`–`09`) but **must read this overview first**. This file holds the shared architecture, the decisions
> that every package depends on, the dependency graph, cross-platform/controller/security/budget mandates,
> and the list of design holes (with the fix for each).

---

## 1. Goals (from the request)

| # | Requirement | Covered by |
|---|---|---|
| G1 | Optional login: Google account **or** email/password (enabled on **all** platforms including sideloaded macOS/iOS) | [02](02_GODOT_FIREBASE_CLIENT_AND_AUTH.md) |
| G2 | Players-page data (club stats, shot recommendations, best courses, achievements, swing issues…) stored in Firebase for the **primary** profile | [03](03_PROFILE_IDENTITY_AND_CLOUD_SYNC.md) |
| G3 | User picks the primary profile on the Players page; only primary (+ approved linked profiles) go to the cloud | [03](03_PROFILE_IDENTITY_AND_CLOUD_SYNC.md) |
| G4 | Pull on app startup; push after every match **and** every 30 minutes of active use (low cost) | [03](03_PROFILE_IDENTITY_AND_CLOUD_SYNC.md) |
| G5 | Website: personal stats for signed-in user; leaderboards for everyone (no login) | [06](06_WEBSITE_STATS_LEADERBOARDS_APPROVALS.md) |
| G6 | Linked accounts: user2 approves user1 once; user1 can pull/push user2's data forever until revoked | [04](04_LINKED_ACCOUNTS_DELEGATION.md) (+ [06](06_WEBSITE_STATS_LEADERBOARDS_APPROVALS.md) for web approval) |
| G7 | Main menu **Leaderboards** section (longest drive, longest putt, lowest score, most achievements, most games…) | [05](05_IN_GAME_LEADERBOARDS.md) |
| G8 | Main menu **Multiplayer** section: host (choose course/settings → share code), join by code, start locks the code, auto-install missing course | [07](07_ONLINE_LOBBY_HOST_JOIN.md) |
| G9 | Public match browser (un-started hosted matches, showing course, # holes, etc.); automatically removed if the host logs off/disconnects without starting | [07](07_ONLINE_LOBBY_HOST_JOIN.md) |
| G10 | Turn-based online play; remote shots replayed directly from Point A → Point B with no collisions and no rollout (putts roll straight A → B ignoring slope) | [08](08_REMOTE_SHOT_REPLAY.md) + [09](09_ONLINE_MATCH_RUNTIME.md) |
| G11 | Low cost, full featured; **hard $10/month budget circuit breaker** with friendly pause message in-game and on the website if monthly budget is reached | [01](01_FIREBASE_BACKEND_SCHEMA_RULES.md), [02](02_GODOT_FIREBASE_CLIENT_AND_AUTH.md), [06](06_WEBSITE_STATS_LEADERBOARDS_APPROVALS.md) |

---

## 2. Work packages

| Doc | Package | Primary area | Can start |
|---|---|---|---|
| [01](01_FIREBASE_BACKEND_SCHEMA_RULES.md) | Firebase backend: Firestore schema, RTDB schema, security rules, indexes, **$10/mo budget circuit-breaker Cloud Function**, CI/CD deploy pipeline, rules tests | `firestore.rules`, `database.rules.json`, `firebase.json`, `firestore.indexes.json`, `functions/`, `.github/workflows/deploy_firebase.yml`, `firebase/tests/` | **Immediately** |
| [02](02_GODOT_FIREBASE_CLIENT_AND_AUTH.md) | Godot Firebase client layer (Auth REST, Firestore REST, RTDB REST + SSE), budget-pause detector/banner, and Account/Login UI | new `Utils/Cloud/*`, new `UI/Account/*` | **Immediately** |
| [03](03_PROFILE_IDENTITY_AND_CLOUD_SYNC.md) | Stable profile IDs, primary profile, sync engine (pull/merge/push, **200 shots/club cap**), match summaries, leaderboard stat derivation | `MultiplayerManager.gd`, `AchievementManager.gd`, `players_menu.gd`, new `Utils/Cloud/cloud_sync.gd` | After 02's public API is stubbed (day 1 with stubs) |
| [04](04_LINKED_ACCOUNTS_DELEGATION.md) | Linked/secondary accounts: request → approve → sync forever → revoke | `players_menu.gd`, `Utils/Cloud/link_service.gd` | After 03 |
| [05](05_IN_GAME_LEADERBOARDS.md) | Main-menu tiles (Leaderboards **and** Multiplayer) + Leaderboards scene | `main_menu.tscn/.gd`, new `UI/Leaderboards/*` | After 02 API stub (can use mock data immediately) |
| [06](06_WEBSITE_STATS_LEADERBOARDS_APPROVALS.md) | Website: sign-up/sign-in, stats dashboard, public leaderboards, link-request approvals, budget-paused banner | `web/*` | **Immediately** (only needs schema in 01) |
| [07](07_ONLINE_LOBBY_HOST_JOIN.md) | Online lobby: host/join/public list, host-disconnect lobby removal, course install & fingerprint check, start match | new `UI/OnlineMultiplayer/*`, new `Utils/Cloud/online_session.gd` | After 02 RTDB client stub |
| [08](08_REMOTE_SHOT_REPLAY.md) | Remote shot replay animation (direct A→B carry with no rollout for air shots; straight A→B roll for putts; zero collisions) | `Player/ball.gd` (minimal), new `Player/remote_shot_replayer.gd` | **Immediately** (pure local feature) |
| [09](09_ONLINE_MATCH_RUNTIME.md) | Online match runtime: turn sync, event log, remote shot application (local-only stat recording), presence/AFK, rejoin, match end | `range.gd`, `course_play.gd`, `MultiplayerManager.gd`, new `Utils/Cloud/online_match_controller.gd` | After 07 + 08 |

---

## 3. Dependency graph & phases

```mermaid
flowchart LR
    P01["01 Backend schema + rules + budget guard + CI/CD"]
    P02["02 Godot Firebase client + Auth UI"]
    P06["06 Website"]
    P08["08 Remote shot replay"]
    P03["03 Profile identity + Cloud sync"]
    P05["05 Main menu tiles + Leaderboards"]
    P07["07 Online lobby"]
    P04["04 Linked accounts"]
    P09["09 Online match runtime"]
    INT["Integration + E2E test pass"]

    P01 --> P03
    P02 --> P03
    P02 --> P05
    P02 --> P07
    P01 --> P06
    P03 --> P04
    P06 -. "web approval page" .-> P04
    P07 --> P09
    P08 --> P09
    P03 -. "match-end sync hook" .-> P09
    P05 -. "Multiplayer tile routes to 07 scene" .-> P07
    P04 --> INT
    P09 --> INT
    P05 --> INT
    P06 --> INT
```

| Phase | Packages (parallel inside a phase) | Notes |
|---|---|---|
| **Phase 0** | 01, 02, 06, 08 | Fully parallel. 02 must publish its public API (method signatures, signals) in the first commit so phase-1 agents can code against stubs. |
| **Phase 1** | 03, 05, 07 | Parallel. 03 and 07 both need a working 02. 05 can run on mock data until 02 lands. |
| **Phase 2** | 04, 09 | 04 needs 03's multi-profile sync engine. 09 needs 07 (lobby → match handoff) and 08 (replayer). |
| **Phase 3** | Integration | Two-device E2E tests, cost verification in Firebase usage dashboard, rules deploy. |

### Hard sequencing constraints (cannot run in parallel)
1. **03 → 04**: linked-account sync reuses 03's per-profile pull/merge/push.
2. **07 → 09**: the runtime starts from the `match_meta` produced by the lobby's Start.
3. **08 → 09**: runtime calls the replayer API.
4. **02 → (03, 05-live, 07)**: everything talks to Firebase through 02.
5. **01 rules must be deployed before any live testing** of 03/04/06/07/09 (agents can use the Firebase Emulator Suite in the meantime).

### File-conflict hot spots (coordinate, keep edits minimal and additive)
| File | Touched by | Rule |
|---|---|---|
| `Utils/MultiplayerManager.gd` | 03, 09 | 03 owns profile/stat/match-summary changes. 09 adds **only** an `is_remote` guard + a new `record_remote_shot()` function. Put new logic in new files. |
| `UI/MainMenu/main_menu.tscn/.gd` | 05 only | 05 adds **both** new tiles (Leaderboards + Multiplayer). The Multiplayer tile routes to `res://UI/OnlineMultiplayer/multiplayer_menu.tscn` (created by 07); if missing, show a "Coming soon" toast. |
| `UI/PlayersMenu/players_menu.gd` | 03, 04 | 03 adds the Account/Primary section; 04 adds the "Link cloud account" controls into the section 03 creates (03 must leave a clearly named container, `CloudLinkSection`). |
| `project.godot` (autoloads + version) | 02, 03, 07, 09 | Autoload names are reserved in §5.4. Version bumps will conflict — see §12. |
| `firebase.json`, rules files, `.github/workflows/deploy_firebase.yml` | 01 only | Others request changes via 01's doc. |
| `Courses/Range/range.gd` | 09 (and 08 read-only) | 08 must not edit `range.gd`. |

---

## 4. Architecture & Resolved Owner Decisions

```mermaid
flowchart TB
    subgraph Game["Godot app (Windows, macOS, Linux, Android, iOS)"]
        AUTH["CloudAuth autoload (02)"]
        FS["FirestoreClient (02)"]
        RT["RtdbClient + SSE (02)"]
        SYNC["CloudSync autoload (03)"]
        LINK["LinkService (04)"]
        LB["Leaderboards scene (05)"]
        LOBBY["OnlineSession Lobby (07)"]
        OMC["OnlineMatchController (09)"]
        REPLAY["RemoteShotReplayer (08)"]
        MM["MultiplayerManager (existing)"]
        LOCAL[("user:// JSON files (existing)")]
    end
    subgraph Firebase["Firebase + Google Cloud"]
        FAUTH["Firebase Auth: Google, Email/Password, Anonymous"]
        FSTORE[("Cloud Firestore: system/status, users, profiles, stats, matches, public_profiles, link_requests")]
        RTDB[("Realtime Database: system/status, codes, lobbies, live matches + event log")]
        HOST["Hosting: website"]
        BUDGET["Cloud Billing Budget ($10/mo) -> Pub/Sub -> Budget Guard Function"]
    end
    AUTH --> FAUTH
    FS --> FSTORE
    RT --> RTDB
    SYNC --> FS
    SYNC <--> LOCAL
    MM <--> LOCAL
    LINK --> FS
    LB --> FS
    LOBBY --> RT
    OMC --> RT
    OMC --> MM
    OMC --> REPLAY
    HOST --> FSTORE
    HOST --> RTDB
    BUDGET --> FSTORE
    BUDGET --> RTDB
```

### 4.1 Finalized Design Decisions

| # | Decision | Status / Notes |
|---|---|---|
| D1 | **Firestore** for durable data (accounts, profiles, stats, match summaries, leaderboards, link requests). | Confirmed. |
| D2 | **Realtime Database (RTDB)** enabled for live online matches (join codes, lobbies, turn events). | **Confirmed by owner.** Uses SSE streaming + conditional ETag writes; stays inside the 10 GB/mo free tier. |
| D3 | **Anonymous Auth enabled** so signed-out users can host/join online matches without creating an account. | **Confirmed by owner.** Anonymous users' stats stay local-only. |
| D4 | **Google Sign-In enabled on ALL platforms** (Windows, macOS, Linux, Android, iOS). | **Confirmed by owner.** macOS/iOS builds are sideloaded; do **not** hide Google Sign-In on iOS/macOS and do **not** add App Store compliance blockers. |
| D5 | **Cloud shot cap per club = 200** (`CLOUD_MAX_SHOTS_PER_CLUB = 200`). | **Confirmed by owner.** (200 shots × 14 clubs × ~150 B ≈ 420 KB, safely under Firestore's 1 MiB document limit.) |
| D6 | **Leaderboards opt-in by default (`leaderboard_opt_in = true`)**, with an opt-out toggle in-game and on the website. | **Confirmed by owner.** |
| D7 | **Remote shot replay has NO rollout on air shots, and putts roll straight A → B ignoring slope.** | **Confirmed by owner.** Non-putter shots fly in a clean arc directly from `start_pos` (A) to `end_pos` (B) and stop immediately at B. Putts roll along the ground directly from A to B and stop at B. |
| D8 | **Abandoned public lobbies are removed immediately on host exit/logoff, and hidden within 45 seconds if the host crashes/loses power.** | **Confirmed by owner.** See §9 and Package 07. |
| D9 | **Hard $10/month budget circuit breaker** via Google Cloud Billing Budget + Pub/Sub Cloud Function that trips a kill-switch (`system/status.paused = true`) in Firestore & RTDB, locking database writes/matches and displaying a friendly monthly-budget-reached message in-game and on the website. | **Confirmed by owner.** Deployed automatically via CI/CD. See §10 and Package 01. |

---

## 5. Shared Conventions

### 5.1 Units & IDs
- Store **meters** and **unix seconds** in cloud data unless a field name says otherwise (`_yds`, `_ft`). Leaderboard display fields use yards/feet with explicit suffixes.
- IDs: `profile_id` = UUIDv4; shot `id` = 12 hex chars; online `matchId` = RTDB push ID; join code = 6 chars from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`.
- Server time: Firestore `REQUEST_TIME` transform; RTDB `{".sv":"timestamp"}`. Never trust device clocks for ordering.

### 5.2 Versioning of protocols
- `CLOUD_SCHEMA_VERSION = 1` (Firestore docs). `ONLINE_PROTOCOL_VERSION = 1` (RTDB match docs). Joining a match with a different protocol version is refused with a "please update" message.

### 5.3 Course identity (used by 03, 07, 09)
- `course_key = slug(Title) + "@" + round(Latitude,4) + "," + round(Longitude,4)` using the top-level `Title`/`Latitude`/`Longitude` written into `course.json` by `OsmMapLoader.cs` (`Courses/OsmMapLoader.cs` ~L815–845). Folder names are **not** stable — never use them as identity.
- `course_fingerprint = sha1(sorted hole IDs + par + tee box positions rounded to 0.5 m + green centers rounded to 0.5 m)` computed from `Hole Info`.

### 5.4 Reserved autoload names
`CloudAuth` (02), `CloudSync` (03), `OnlineSession` (07/09 share; 07 creates it, 09 extends it). Non-autoload classes use `class_name` under `Utils/Cloud/`.

---

## 6. Mandatory Controller / Gamepad Support Standard (All UI Packages: 02, 03, 04, 05, 07, 09)

Controller navigation is a first-class requirement across the entire simulator (D-pad, left stick, `ui_accept` / Joypad A, `ui_cancel` / Joypad B). **Every agent touching or creating UI must implement and test these 7 rules:**

1. **Focus Mode & Explicit Neighbor Graph:**
   - Every interactive control (`Button`, `OptionButton`, `CheckButton`, `LineEdit`, `HSlider`, tab pills, list rows) must have `focus_mode = Control.FOCUS_ALL`.
   - Whenever a view, tab, list, or modal populates or refreshes dynamically, call a dedicated `_update_controller_focus_navigation()` method that explicitly sets `focus_neighbor_top`, `focus_neighbor_bottom`, `focus_neighbor_left`, and `focus_neighbor_right` (`get_path_to(...)`) so D-pad/stick navigation never gets trapped or jumps to hidden controls.
2. **High-Visibility Focus Outlines:**
   - Every focusable button/card must have a high-visibility focus stylebox (using `ThemeManager` helpers or a `3px` gold/cyan `StyleBoxFlat` border override on `"focus"`, matching `main_menu.gd` L69–80 and `players_menu.gd`).
3. **Initial Focus & Modal Isolation (`UIFocusGuard`):**
   - When opening any modal or switching tabs/screens, register the modal with `/root/UIFocusGuard` (`push_modal_lock` / `pop_modal_lock` if used) and call `grab_focus()` (`call_deferred`) on the primary default control. When closing a modal, restore focus to the button that opened it.
4. **`ui_cancel` (B Button / Escape) Handling:**
   - Every new scene and modal must implement `_unhandled_input(event)`: pressing `ui_cancel` closes the active modal (or navigates back to the Main Menu from top-level menus), except when typing in a `LineEdit` where `KEY_BACKSPACE` must not trigger `ui_cancel` (match the guard in `osm_download_dialog.gd` L1254).
5. **Virtual Keyboard Integration (`VirtualKeyboardManager`):**
   - Every `LineEdit` (Email, Password, Display Name, 6-char Join Code) must work with `/root/VirtualKeyboardManager` so controller and touchscreen users on projector PCs, Android, and iOS can type without a physical keyboard.
6. **ScrollContainer Auto-Scroll on Focus:**
   - Lists inside a `ScrollContainer` (Leaderboards rows, Public Lobby rows, Approvals list) must set `follow_focus = true` on the `ScrollContainer` and attach `TouchScrollHelper` (`Utils/touch_scroll_helper.gd`) so both gamepad D-pad scrolling and mobile touch dragging work out of the box.
7. **Unit Test Enforcement:**
   - Every UI package's GUT test file (`test_cloud_auth_and_clients.gd`, `test_leaderboards_menu.gd`, `test_online_lobby_and_course_check.gd`, etc.) **must include a controller focus test** that instantiates the UI, simulates D-pad focus traversal, and asserts `get_viewport().gui_get_focus_owner() != null`.

---

## 7. Cross-Platform Compatibility & Zero-Regression Guarantee (Windows, macOS, Linux, Android, iOS)

All 5 platforms built by `.github/workflows/multiplatform_release.yml` (Windows Desktop, macOS Universal, Linux, Android AAB, and sideloaded iOS IPA) must work identically with zero regressions:

1. **100% Pure GDScript + Built-In Godot Networking (`HTTPRequest` / `HTTPClient`):**
   - Do **not** add native C++/C#/Android AAR/iOS Framework plugins for Firebase. Built-in `HTTPRequest` and `HTTPClient` with TLS (`TLSOptions.client()`) work out of the box on Windows, macOS, Linux, Android, and iOS.
2. **File Paths & Case Sensitivity:**
   - Always use `res://` and `user://` paths with exact casing (macOS, Linux, Android, and iOS filesystems can be case-sensitive; Windows is not).
   - Ensure `export_presets.cfg` includes `*.json, *.json.gz, *.gz` (already configured on all 5 presets: Linux, Windows Desktop, Android, macOS, iOS) so `res://Resources/firebase_config.json` is packaged in every export.
3. **Google Sign-In Across Desktop & Mobile (Including Sideloaded macOS & iOS):**
   - Enable Google Sign-In on **all** platforms (no iOS block).
   - Make the **Google OAuth 2.0 Device Authorization Flow** (shows 8-char code + QR/link + `"Open Google Verification Page"` button via `OS.shell_open("https://www.google.com/device")` + clipboard copy of the code) the universal primary method on all platforms. Why? Because on sideloaded iOS/Android and fullscreen simulator PCs, custom URL schemes require App Store/Play Store intent verification, whereas opening `google.com/device` in the system browser (or scanning on a phone) works 100% reliably on Windows, macOS, Linux, Android, and sideloaded iOS!
   - On Windows/macOS/Linux desktop, also offer the 1-click Loopback (`127.0.0.1`) browser redirect option.
4. **Mobile Lifecycle & Backgrounding (Android & iOS):**
   - Handle `NOTIFICATION_APPLICATION_PAUSED`, `NOTIFICATION_APPLICATION_RESUMED`, `NOTIFICATION_WM_CLOSE_REQUEST`, and `NOTIFICATION_APPLICATION_FOCUS_OUT`:
     - When paused/backgrounded on Android/iOS, pause the 30-minute active-usage sync timer, flush dirty sync state metadata to `user://cloud_sync_state.json`, and on resume, reconnect any open `RtdbStream` SSE listener and catch up missed match events via sequence number `seq`.
5. **Responsive UI & Safe Areas:**
   - All new screens and modals must respect `ScreenOffsetManager` (`Utils/screen_offset_manager.gd`) and fit cleanly on 16:9 desktop (`1728×972`), ultrawide, and mobile/iPad aspect ratios using `ScrollContainer` and `TouchScrollHelper`.
6. **Offline-First & Zero-Regression Guarantee for Existing Modes:**
   - Every cloud/online feature is strictly additive. If the user is offline, not signed in, or if the monthly cloud budget pause is active, **Courses (local single-player & local pass-and-play multiplayer), Driving Range, Practice Mode, Mini-Games, History, Players Menu, and Launch Monitors (Garmin, R10, Square BLE, Putting Camera, Golfer Camera)** must continue to work with zero errors, zero startup delays, and zero blocking popups.

---

## 8. Public Repository Security Audit & Secret Hygiene

I audited the entire repository (`git ls-files`, `.gitignore`, `.github/workflows/*.yml`, `scripts/`, `Resources/firebase_config.json`, `web/index.html`, `Courses/OsmMapLoader.cs`).

### 8.1 Current Audit Findings (Clean)
1. **No private keys or credentials are tracked in Git:**
   - Android signing keystores (`*.keystore`, `*.jks`) are properly ignored in `.gitignore` and decoded at CI runtime from GitHub Secrets (`ANDROID_KEYSTORE_BASE64`).
   - Firebase deployment credentials in `.github/workflows/deploy_firebase.yml` read strictly from GitHub Actions Secrets (`FIREBASE_SERVICE_ACCOUNT_HECKLE_GOLF_SIM` / `FIREBASE_TOKEN`) into `$RUNNER_TEMP/firebase_sa.json` (outside the workspace).
   - Google Places API key in `Courses/OsmMapLoader.cs` (`L7130`) reads from environment variable `GOOGLE_PLACES_API_KEY` and is not hardcoded.
2. **What IS in `Resources/firebase_config.json` and `web/index.html` — and why it is safe ONLY with strict rules:**
   - `firebase_config.json` and `web/index.html` contain the Firebase Web `apiKey` (`AIzaSy...`), `projectId`, and `appId`. In Firebase's architecture, the Web API key is **public by design** (it is shipped in every website and client app just to identify your Firebase project to Google's servers).
   - **HOWEVER**, because that `apiKey` is public, **anyone can call the Firestore/RTDB REST APIs against your project ID!** Right now, your existing `firestore.rules` has `allow read, write: if request.auth != null;` on `/matches` and `allow write: if request.auth != null;` on `/leaderboards` and `allow read: if true;` on `/users`. That means anyone who signs up could overwrite your entire leaderboard or dump every user's document.
   - Deploying Package 01's `firestore.rules` and `database.rules.json` closes that hole completely.

### 8.2 Security Rules & Secret Hygiene Mandates for All Agents
1. **Never commit service account keys, `.env` files, or CI tokens:**
   - Add `*service_account*.json`, `*firebase_sa*.json`, `.env`, `.env.*`, `functions/.runtimeconfig.json` to `.gitignore` in Package 01.
2. **Restrict the Firebase API Key in Google Cloud Console (Owner 2-Minute Action):**
   - In [Google Cloud Console → APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials), click the Browser/Firebase API key (`AIzaSyDEdlLgd1OspjvXW5fY90ICVCpkZJM8Vbs`) and under **API restrictions**, select **"Restrict key"** so it can **only** call:
     - *Identity Toolkit API* (Firebase Auth)
     - *Token Service API* (Firebase Auth token refresh)
     - *Cloud Firestore API*
     - *Firebase Realtime Database API*
     - *Firebase Installations / Analytics API*
   - This prevents anyone from using your public Firebase `apiKey` against expensive Google Cloud APIs (like Google Maps/Places, Vertex AI, Cloud Storage, etc.).
3. **Enable Firebase Auth Abuse Limits:**
   - Keep standard Identity Toolkit per-IP signup/signin quota defaults enabled in Firebase Auth (default 100 account creations/IP/hour) so bots cannot spam anonymous or email accounts.
4. **Google OAuth Client IDs:**
   - For Installed/Device OAuth clients (`TVs and Limited Input devices` / `Desktop`), Google's documentation explicitly notes that the client ID/secret shipped in installed apps is treated as public/non-confidential and only identifies the client app for user-consent screens — it grants **zero** access to your project or any user account without the user actively approving on `google.com/device`. Never use a Web Server / Service Account secret in client code.
5. **Payload Size & Schema Enforcement in Rules:**
   - Both `firestore.rules` and `database.rules.json` enforce field types, string lengths, value bounds, and owner/delegate UID checks so a modified client cannot upload megabyte blobs or corrupt another user's profile.

---

## 9. Immediate Cleanup of Abandoned Public Lobbies (Hole H14)

To ensure users never see or try to join a public lobby whose host logged off, closed the app, or crashed without starting:
1. **Graceful Exit / Logoff / Scene Leave (Immediate Deletion):**
   - When the host clicks **Back / Cancel Lobby**, signs out in `CloudAuth`, quits the app (`NOTIFICATION_WM_CLOSE_REQUEST` on Windows/macOS/Linux), or backgrounds the app (`NOTIFICATION_APPLICATION_PAUSED` on Android/iOS while in lobby), `OnlineSession` immediately deletes `/lobbies/{matchId}`, `/codes/{CODE}`, and `/matches/{matchId}`.
2. **Tight Heartbeat + Client-Side Liveness Filter (20s Heartbeat / 45s Expiry):**
   - While a lobby is open and un-started, the host sends a lightweight heartbeat (`PATCH /lobbies/{matchId} {"last_seen": now}`) every **20 seconds**.
   - The Public Matches Browser (`fetch_public_lobbies()`) filters out **and immediately deletes** any lobby where `now - last_seen > 45` seconds.
3. **Pre-Join Host Liveness Verification:**
   - When a user clicks **Join** on a public lobby (or enters a join code), `OnlineSession` checks `now - match_devices[host_uid].last_seen <= 45` and `meta.status == "lobby"`. If the host's heartbeat is older than 45 seconds, `OnlineSession` deletes the dead `/lobbies/{matchId}` entry and shows `"That lobby was closed by the host"` instead of letting the player load into an abandoned room.

---

## 10. Hard $10/Month Cloud Budget Alerts & Automatic Kill-Switch Circuit Breaker (Requirement G11)

To guarantee your cloud spend cannot run away past the **$10/month** credit included with your Google subscription, Package 01 sets up a two-layer defense (Alerts + Automatic Hard Shutdown) deployed via CI/CD:

### 10.1 How It Works
```mermaid
flowchart LR
    B["Google Cloud Billing Budget ($10.00/mo)"] -->|"50% ($5), 80% ($8), 100% ($10)"| E["Email Alerts to Owner"]
    B -->|"Pub/Sub topic: budget-alerts"| CF["Cloud Function: enforceBudgetCap (functions/index.js)"]
    CF -->|"If costAmount >= $9.50"| FS["Set Firestore system/status {paused: true} + RTDB /system/status {paused: true}"]
    FS -->|"Security Rules check"| LOCK["All Firestore writes & RTDB lobbies/matches rejected at server"]
    FS -->|"Game & Website read system/status"| UI["Friendly Banner: 'Multiplayer is temporarily paused for the remainder of the month...'"]
```

1. **Google Cloud Billing Budget (`$10.00 / calendar month`):**
   - Configured at thresholds `50% ($5.00)`, `80% ($8.00)`, `95% ($9.50)`, and `100% ($10.00)` publishing to Pub/Sub topic `budget-alerts`.
2. **Automated Circuit-Breaker Cloud Function (`functions/index.js`):**
   - Triggered by the `budget-alerts` Pub/Sub topic.
   - When `costAmount >= 9.50` (triggers at $9.50 so in-flight requests never push you past $10.00), the function uses the Firebase Admin SDK to write:
     - Firestore document `system/status`:
       ```json
       {
         "paused": true,
         "reason": "monthly_budget_reached",
         "paused_month": "2026-11",
         "message": "Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."
       }
       ```
     - RTDB path `/system/status`: same JSON object.
   - On the 1st of the new month (`costAmount < 1.00`), the function automatically resets `paused: false` so multiplayer and cloud sync resume automatically on the 1st of the next month!
3. **Server-Side Security Rule Enforcement (Cannot Be Bypassed):**
   - `firestore.rules` includes a global helper `isCloudActive()`:
     `!exists(/databases/$(database)/documents/system/status) || get(/databases/$(database)/documents/system/status).data.paused != true`
     Every client `create`/`update`/`delete` rule requires `isCloudActive()`.
   - `database.rules.json` requires `root.child('system/status/paused').val() != true` on all `.write` rules and on `/lobbies` and `/matches` reads.
4. **Friendly User-Facing Message In-Game (02, 05, 07) & On Website (06):**
   - On startup (and if any request fails with `403` when `system/status.paused == true`), the game and website display a clean, friendly notice banner:
     > **"Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."**
   - All local single-player, local multiplayer, range, practice, and local stats continue working 100% normally.

---

## 11. Summary of All Design Holes & Fixes

| ID | Hole / risk | Fix | Owner |
|---|---|---|---|
| **H1** | Local data is keyed by display name (`players_registry.json`, `player_club_stats.json`, `player_achievements.json`, `player_swing_issues.json`). | Add `profile_id` (UUID), `cloud_uid`, `link_role` to registry. Enforce unique local names; support safe rename across all local JSON files. | 03, 04 |
| **H2** | Match history is capped at 10 files (`_enforce_history_limit`, `MultiplayerManager.gd` L2380) and `calculate_player_stats()` derives lifetime stats from those 10 files. | Maintain lifetime aggregates in `profiles/{uid}.lifetime` using idempotent Firestore transforms (`exists=false` precondition on `profiles/{uid}/matches/{id}`). | 03 |
| **H3** | Overwrite sync would destroy shots recorded at another location. | Merge-based sync: 12-hex shot IDs + set union + tombstones for clear-history actions. | 03 |
| **H4** | Unbounded club shot arrays would exceed Firestore's 1 MiB document limit. | Cap cloud shot array to the **most recent 200 shots per club** (`CLOUD_MAX_SHOTS_PER_CLUB = 200`) using compact keys. | 03 |
| **H5** | Firestore has no realtime listener over REST in GDScript; polling Firestore costs reads. | Use **Realtime Database (RTDB)** with Server-Sent Events (SSE) for lobbies and turn events (always-free 10 GB/mo bandwidth). | 02, 07, 09 |
| **H6** | Google Sign-In across desktop + sideloaded iOS/macOS + Android without native SDKs. | Use Google OAuth 2.0 Device Authorization Flow on all platforms + optional Desktop Loopback PKCE flow; exchange `id_token` via `accounts:signInWithIdp`. Enabled on all platforms including iOS/macOS. | 02 |
| **H7** | Approving a link by email could be spoofed by an unverified email/password account. | Rules require `request.auth.token.email_verified == true` to read/approve link requests; send verification email on sign-up. | 01, 02, 04 |
| **H8** | `user2` may not have an account yet when `user1` links them at `user1`'s house. | `user2` can play immediately while `pending_link`; `user2` can create an account on the website on their phone and approve in 30 seconds, merging all shots recorded so far. | 04, 06 |
| **H9** | Remote players' shots in online multiplayer would pollute local player stats, achievements, and match history. | Flag remote golfers `is_remote = true`; never register them locally, never write their shots to `player_club_stats.json`, `player_achievements.json`, or `shot_stats` in `user://match_history/`. | 09 |
| **H10** | Turn order and scoring logic run independently per device and could diverge near gimme/cup boundaries. | Active shooter's device is authoritative: shot event carries `end`, `holed_out`, `penalty`, `gimme_strokes`, `next_slot`, and `scores` snapshot. | 09 |
| **H11** | Random pin placement (`range.gd` L4156) and round wind (`GlobalSettings.start_round_wind`) roll independently per device. | Host sets wind and `pin_seed` in `meta.settings`; first shot on each hole also carries authoritative `pin` coordinates. | 07, 09 |
| **H12** | Course folder names differ across devices; joiners may lack the course or have outdated geometry. | Identify courses by `course_key = slug(Title)@lat,lon` and verify SHA-1 `course_fingerprint`; auto-install via `OsmMapLoader` in lobby before match starts. | 07 |
| **H13** | Disconnects or AFK players mid-match would freeze the turn forever. | 60s match heartbeat; after 3 min inactive, show Concede Hole / Remove Player options; support crash rejoin via event log fast-forward. | 09 |
| **H14** | Public lobbies left behind when host logs off or closes the game without cancelling. | Immediate deletion of `/lobbies/{id}` and `/codes/{CODE}` on host exit/logoff/pause + 20s lobby heartbeat with 45s auto-expiry and pre-join liveness check. | 07 |
| **H15** | Join code collisions or joining after match starts. | Conditional PUT (`null_etag`) for codes; Start Match atomically deletes `/codes/{CODE}` and `/lobbies/{id}` and sets `status = "active"`. | 01, 07 |
| **H16** | Mulligans, mid-match add/pause player, catch-up mode, and practice mode would desync online matches. | Disabled/hidden during online matches; Forfeit becomes "Leave Online Match". | 09 |
| **H17** | Scramble / 2v2 Scramble require cross-device best-ball selection. | v1 online supports Standard, Skins, and Closest to Pin. | 07, 09 |
| **H18** | Local launch monitor shots firing during a remote player's turn. | Disarm launch monitor and ignore hit signals whenever `active_player.is_remote == true` or replay is active. | 09 |
| **H19** | Replayed remote shot emitting `ball.rest` or rolling out into different local terrain/trees. | Replayer sets `ball.is_replaying_remote_shot = true`, flies directly from A to B with **no rollout** (putts roll straight A → B ignoring slope), and emits `replay_finished` (never `ball.rest`). | 08 |
| **H20** | Leaderboard spoofing or manual/debug shots topping leaderboards. | Server rules validate realistic bounds; only launch-monitor shots (`src == "lm"`) and 0-mulligan Standard rounds qualify for leaderboards. | 01, 03 |
| **H21** | Anonymous web/in-game leaderboard refreshes burning Firestore reads. | `limit(25)` queries + 10-min client cache in-game and `sessionStorage` cache on web; only write `public_profiles/{uid}` when a leaderboard metric actually changes. | 03, 05, 06 |
| **H23** | 30-minute timer counting backgrounded time or losing dirty state on quit. | Count only foreground active seconds; persist dirty queue in `user://cloud_sync_state.json`; flush on next startup. | 03 |
| **H24** | Switching Primary Profile while signed in. | Explicit confirmation dialog explaining that cloud stats will merge into the newly selected primary profile. | 03 |
| **H25** | Existing `firestore.rules` exposes `/users` (emails) and allows arbitrary writes to `/leaderboards` and `/matches`. | Replaced completely in Package 01 + audited for public-repo safety (§8). | 01 |
| **H26** | Different app versions joining the same online match. | `ONLINE_PROTOCOL_VERSION` check on join. | 07 |
| **H27** | Local gimme/green-speed/rollout settings differing across devices in an online match. | Host's gameplay settings are snapshotted into `meta.settings`, applied for the match, and restored on exit. | 07, 09 |
| **H28** | Couch + online play (multiple local golfers on one device playing against remote golfers). | Each golfer slot has `owner_uid`; a device controls the turn whenever `golfers[active_slot].owner_uid == CloudAuth.get_uid()`. | 07, 09 |
| **H30** | Cloud spend exceeding the $10/month Google AI Pro credit. | Google Cloud Billing Budget ($10/mo) + Pub/Sub Cloud Function flips `system/status.paused = true` at $9.50, locking rules and showing the friendly pause banner in-game and on the website (§10). | 01, 02, 06 |

---

## 12. Coordination Rules for Implementation Agents

1. Read this overview + your package doc + `AGENTS.md`. Follow `AGENTS.md` token-efficiency rules (sliced reads, targeted tests only, don't launch the game unless asked).
2. **Controller & Cross-Platform Mandates:** Every UI change must follow §6 (controller focus graph, `UIFocusGuard`, `VirtualKeyboardManager`, `ui_cancel`, controller unit test) and §7 (pure GDScript, Windows/macOS/Linux/Android/iOS compatibility, zero regressions to offline play).
3. **CI/CD Automation:** All Google Cloud / Firebase resources (Hosting, Firestore rules & indexes, RTDB rules, and the budget circuit-breaker Cloud Function) must be deployed automatically through `.github/workflows/deploy_firebase.yml` and `scripts/deploy/deploy_firebase.ps1` (Package 01).
4. **Release notes:** Append player-friendly bullets to `CHANGES_SINCE_LAST_RELEASE.md` under the existing headings; never delete others' entries.
5. **Versioning:** Run `powershell -ExecutionPolicy Bypass -File .\scripts\tools\bump_version.ps1 -Minor` per `AGENTS.md` when implementing your package and report both `config/version` and Android `version/code`.
