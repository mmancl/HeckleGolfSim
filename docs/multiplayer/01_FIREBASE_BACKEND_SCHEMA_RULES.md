# Work Package 01 — Firebase Backend: Schemas, Rules, $10 Budget Circuit Breaker & CI/CD

> **Prerequisite:** Read [`00_OVERVIEW.md`](00_OVERVIEW.md) first.
> **Can start:** Immediately (Phase 0).
> **Owns:** `firestore.rules`, `database.rules.json`, `firestore.indexes.json`, `firebase.json`, `functions/package.json`, `functions/index.js`, `.github/workflows/deploy_firebase.yml`, `scripts/deploy/deploy_firebase.ps1`, `.gitignore` (secret hygiene rules), `Resources/firebase_config.json`, `firebase/tests/*`.

---

## 1. Scope & Goals

1. Replace the insecure placeholder `firestore.rules` (Hole H25) with production security rules that enforce ownership, delegate access for linked accounts, verified-email approval for link requests, range checks on public leaderboards, and the **$10/month budget circuit-breaker lock**.
2. Define and protect the **Realtime Database (RTDB)** schema (`database.rules.json`) for system status, join codes, public lobbies, and turn-based online matches.
3. Implement the **$10/month Cloud Budget Alert & Automatic Circuit-Breaker Function** (`functions/index.js` + automated setup in CI/CD) so that if monthly usage ever reaches your $10 Google AI Pro credit limit, cloud writes and online matches automatically pause for the remainder of the month and display the friendly pause message in-game and on the website.
4. Update `firebase.json`, `.github/workflows/deploy_firebase.yml`, and `scripts/deploy/deploy_firebase.ps1` so **all** Firebase & Google Cloud components (`hosting`, `firestore`, `database`, `functions`, and the Pub/Sub budget topic) are deployed automatically through the CI/CD pipeline with zero secrets committed to this public repo.
5. Add automated rules unit tests in `firebase/tests/` using `@firebase/rules-unit-testing` against the Firebase Emulator Suite.

---

## 2. Cloud Firestore Schema

All documents carry `"schema_version": 1`. Timestamps are integer Unix seconds (`int`).

### 2.0 `system/status` (Global Cloud Service Status & Budget Kill-Switch — world-readable, Admin SDK write-only)
Read by the game client and website to check whether multiplayer/cloud sync is active or paused for the month:
```json
{
  "schema_version": 1,
  "paused": false,
  "reason": "",
  "paused_month": "",
  "updated_at": 1730000000,
  "message": "Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."
}
```
- Client write permission: **`allow write: if false;`** (only writable by the `enforceBudgetCap` Cloud Function via Firebase Admin SDK).
- When `paused == true`, `firestore.rules` rejects all client `create`, `update`, and `delete` operations across the entire database.

### 2.1 `users/{uid}` (Private account document — owner only)
Created on first sign-in. Never readable by other users (protects email PII). Default `leaderboard_opt_in` is `true` (Owner Decision D6).
```json
{
  "schema_version": 1,
  "email_lower": "user1@gmail.com",
  "display_name": "Mike",
  "created_at": 1730000000,
  "last_login_at": 1730003600,
  "leaderboard_opt_in": true,
  "linked_cloud_uids": ["uid_of_user2"]
}
```

### 2.2 `profiles/{uid}` (Profile metadata & lifetime aggregates — owner + approved delegates)
One cloud profile per Firebase account (`docId == uid`).
- Readable and writable by `request.auth.uid == uid` **OR** if `exists(/databases/$(database)/documents/profiles/$(uid)/delegates/$(request.auth.uid))` is true.
```json
{
  "schema_version": 1,
  "owner_uid": "uid_of_user1",
  "display_name": "Mike",
  "avatar": "res://assets/images/avatars/golfer_1.png",
  "preferred_tee": "Blue",
  "skill_level": "mid_handicap",
  "handedness": 0,
  "ball_graphic": "single_line",
  "bag": ["Dr", "3W", "5i", "6i", "7i", "8i", "9i", "PW", "SW", "Pt"],
  "updated_at": 1730003600,
  "updated_by_uid": "uid_of_user1",
  "rev": 14,
  "lifetime": {
    "matches_played": 42,
    "single_player_completed": 18,
    "multiplayer_played": 24,
    "wins": 11,
    "losses": 10,
    "ties": 3,
    "holes_played": 612,
    "total_strokes": 2610,
    "total_par": 2448,
    "par_diff_sum": 162,
    "par_diff_matches": 40,
    "best_to_par_18": -2,
    "best_gross_18": 70,
    "best_to_par_9": -1,
    "best_gross_9": 35,
    "longest_drive_yds": 312.4,
    "longest_putt_ft": 44.2,
    "hole_in_ones": 1,
    "achievements_count": 17,
    "best_courses": {
      "Augusta National Golf Club": {
        "diff": -2,
        "strokes": 70,
        "holes": 18,
        "str": "-2 (18 holes)",
        "updated_at": 1730000000
      }
    }
  },
  "club_summary": {
    "Dr": { "carry_yds": 265.0, "total_yds": 284.5, "ball_speed_mph": 158.2, "club_speed_mph": 107.1, "smash": 1.48, "spin_rpm": 2450, "count": 94 },
    "7i": { "carry_yds": 165.0, "total_yds": 172.0, "ball_speed_mph": 118.0, "club_speed_mph": 87.0, "smash": 1.36, "spin_rpm": 6200, "count": 120 }
  }
}
```

### 2.3 `profiles/{uid}/sync/stats` (Bundled raw sync payload — owner + approved delegates)
Single document holding raw club shots (**capped at 200 per club** per Owner Decision D5), personal records, unlocked achievements, swing issues, and clear-history tombstones.
```json
{
  "schema_version": 1,
  "rev": 14,
  "updated_at": 1730003600,
  "tombstones": {
    "cleared_all_at": 0,
    "cleared_clubs": { "Dr": 1729000000 },
    "cleared_swing_issues_at": 0
  },
  "records": {
    "longest_drive_yds": 312.4,
    "longest_putt_ft": 44.2
  },
  "clubs": {
    "Dr": [
      {
        "id": "a1b2c3d4e5f6",
        "t": 1730001200,
        "c": 242.3,
        "tot": 260.1,
        "bs": 69.2,
        "cs": 47.1,
        "sf": 1.47,
        "sp": 2510,
        "sd": -4.2,
        "tg": 250.0,
        "red": 0.0,
        "fa": 1.2,
        "cp": -0.8,
        "hi": 2.1,
        "vi": -1.0
      }
    ]
  },
  "achievements": {
    "unlocked": {
      "first_par": 1728000000,
      "long_drive": 1729500000
    },
    "heard_heckles": ["res://assets/audio/heckler/bad_shot_1.wav"]
  },
  "swing_issues": {
    "2026-10": {
      "Over the Top": 4,
      "Early Extension": 2
    }
  }
}
```
Short keys in `clubs.<club>[]` keep 200 shots × 14 clubs well under 450 KB.

### 2.4 `profiles/{uid}/matches/{matchId}` (Immutable match summary — owner + delegates create-only)
Written once when a non-practice match finishes (`exists == false` precondition prevents double-counting in `lifetime`).

### 2.5 `profiles/{uid}/delegates/{delegateUid}` (Access grant — owner write/delete, delegate read)
Created when `uid` (e.g. user2) approves a link request from `delegateUid` (user1). Deleting this doc revokes access immediately.

### 2.6 `link_requests/{requestId}` (Delegation handshake)
Deterministic ID: `requester_uid + "__" + sha256_hex(target_email_lower).substr(0, 20)`.

### 2.7 `public_profiles/{uid}` (World-readable leaderboard entry — no email/PII)
Written whenever `profiles/{uid}` is pushed and a leaderboard field changed (if `leaderboard_opt_in == true`, which is the default). If the user opts out, the client deletes `public_profiles/{uid}`.

---

## 3. Realtime Database (RTDB) Schema

### 3.0 `/system/status` (Global Budget Kill-Switch Mirror in RTDB)
```json
{
  "paused": false,
  "reason": "",
  "paused_month": "",
  "message": "Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."
}
```

### 3.1 `/codes/{CODE}`
Maps 6-char uppercase code to `matchId` while the match is in `"lobby"` status. Deleted immediately when the host starts or leaves/closes the lobby.

### 3.2 `/lobbies/{matchId}` (Public lobby browser index)
Present **only** while `status == "lobby"` AND `visibility == "public"`. Deleted immediately when the match starts, when the host leaves/logs off, or when any client detects `now - last_seen > 45s` (`45000 ms`).

### 3.3 `/matches/{matchId}`
Holds `meta`, `devices/{uid}`, `golfers/{slotId}`, and `events/{seqKey}` (see `00_OVERVIEW.md` and `07`/`09`).

---

## 4. Complete `firestore.rules`

Write this exact ruleset to `firestore.rules`:

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    function isSignedIn() {
      return request.auth != null;
    }

    function isOwner(uid) {
      return isSignedIn() && request.auth.uid == uid;
    }

    function isDelegate(ownerUid) {
      return isSignedIn() &&
        exists(/databases/$(database)/documents/profiles/$(ownerUid)/delegates/$(request.auth.uid));
    }

    function isOwnerOrDelegate(ownerUid) {
      return isOwner(ownerUid) || isDelegate(ownerUid);
    }

    function hasVerifiedEmail() {
      return isSignedIn() &&
        request.auth.token.email != null &&
        request.auth.token.email_verified == true;
    }

    // Budget circuit-breaker check: returns false if system/status has paused == true
    function isCloudActive() {
      return !exists(/databases/$(database)/documents/system/status) ||
        get(/databases/$(database)/documents/system/status).data.paused != true;
    }

    function validRangeOrAbsent(data, field, minVal, maxVal) {
      return !(field in data) || (
        data[field] is number &&
        data[field] >= minVal &&
        data[field] <= maxVal
      );
    }

    // 0. Global system status / budget pause flag (world-readable, Admin SDK write-only)
    match /system/{docId} {
      allow read: if true;
      allow write: if false;
    }

    // 1. Private user account doc (owner only)
    match /users/{uid} {
      allow read: if isOwner(uid);
      allow create, update: if isCloudActive()
        && isOwner(uid)
        && request.resource.data.schema_version == 1
        && (!('display_name' in request.resource.data) || (request.resource.data.display_name is string && request.resource.data.display_name.size() <= 40));
      allow delete: if isOwner(uid);
    }

    // 2. Synced player profiles (owner + approved delegates)
    match /profiles/{uid} {
      allow read: if isOwnerOrDelegate(uid);
      allow create, update: if isCloudActive()
        && isOwnerOrDelegate(uid)
        && request.resource.data.schema_version == 1
        && request.resource.data.owner_uid == uid
        && request.resource.data.display_name is string
        && request.resource.data.display_name.size() >= 1
        && request.resource.data.display_name.size() <= 40;
      allow delete: if isOwner(uid);

      // Bundled stats doc (clubs, records, achievements, swing_issues, tombstones)
      match /sync/{docId} {
        allow read: if isOwnerOrDelegate(uid);
        allow create, update: if isCloudActive()
          && isOwnerOrDelegate(uid)
          && docId == "stats"
          && request.resource.data.schema_version == 1;
        allow delete: if isOwner(uid);
      }

      // Append-only match summaries
      match /matches/{matchId} {
        allow read: if isOwnerOrDelegate(uid);
        allow create: if isCloudActive()
          && isOwnerOrDelegate(uid)
          && request.resource.data.schema_version == 1
          && request.resource.data.match_id == matchId
          && request.resource.data.strokes is int
          && request.resource.data.strokes >= 1
          && request.resource.data.holes_count is int
          && request.resource.data.holes_count >= 1
          && request.resource.data.holes_count <= 36;
        allow update: if false;
        allow delete: if isOwner(uid);
      }

      // Access grants for linked accounts
      match /delegates/{delegateUid} {
        allow read: if isOwner(uid) || (isSignedIn() && request.auth.uid == delegateUid);
        allow create, update: if isCloudActive()
          && isOwner(uid)
          && request.resource.data.delegate_uid == delegateUid;
        allow delete: if isOwner(uid) || (isSignedIn() && request.auth.uid == delegateUid);
      }
    }

    // 3. Account link requests (handshake between user1 and user2)
    match /link_requests/{requestId} {
      allow read: if isSignedIn() && (
        resource == null ||
        resource.data.requester_uid == request.auth.uid ||
        resource.data.target_uid == request.auth.uid ||
        (hasVerifiedEmail() && request.auth.token.email.lower() == resource.data.target_email_lower)
      );

      allow create: if isCloudActive()
        && isSignedIn()
        && request.resource.data.requester_uid == request.auth.uid
        && request.resource.data.status == "pending"
        && request.resource.data.target_email_lower is string
        && request.resource.data.target_email_lower.size() >= 3
        && request.resource.data.target_email_lower.size() <= 120;

      allow update: if isCloudActive() && isSignedIn() && (
        (
          hasVerifiedEmail()
          && request.auth.token.email.lower() == resource.data.target_email_lower
          && request.resource.data.requester_uid == resource.data.requester_uid
          && request.resource.data.target_email_lower == resource.data.target_email_lower
          && request.resource.data.target_uid == request.auth.uid
          && request.resource.data.status in ["approved", "denied", "revoked"]
        )
        ||
        (
          resource.data.requester_uid == request.auth.uid
          && request.resource.data.requester_uid == request.auth.uid
          && request.resource.data.target_email_lower == resource.data.target_email_lower
          && request.resource.data.status in ["pending", "revoked"]
        )
      );

      allow delete: if isSignedIn() && (
        resource.data.requester_uid == request.auth.uid ||
        resource.data.target_uid == request.auth.uid
      );
    }

    // 4. Public leaderboards projection (world-readable even when paused, sanity-checked writes)
    match /public_profiles/{uid} {
      allow read: if true;
      allow create, update: if isCloudActive()
        && isOwnerOrDelegate(uid)
        && request.resource.data.schema_version == 1
        && request.resource.data.uid == uid
        && request.resource.data.display_name is string
        && request.resource.data.display_name.size() >= 1
        && request.resource.data.display_name.size() <= 40
        && !('email' in request.resource.data)
        && validRangeOrAbsent(request.resource.data, 'longest_drive_yds', 0.0, 450.0)
        && validRangeOrAbsent(request.resource.data, 'longest_putt_ft', 0.0, 180.0)
        && validRangeOrAbsent(request.resource.data, 'best_gross_18', 18, 250)
        && validRangeOrAbsent(request.resource.data, 'best_to_par_18', -36, 180)
        && validRangeOrAbsent(request.resource.data, 'best_gross_9', 9, 130)
        && validRangeOrAbsent(request.resource.data, 'best_to_par_9', -18, 90)
        && validRangeOrAbsent(request.resource.data, 'achievements_count', 0, 100)
        && validRangeOrAbsent(request.resource.data, 'matches_played', 0, 100000)
        && validRangeOrAbsent(request.resource.data, 'wins', 0, 100000)
        && validRangeOrAbsent(request.resource.data, 'hole_in_ones', 0, 1000);
      allow delete: if isOwner(uid);
    }
  }
}
```

---

## 5. Complete `database.rules.json` (Realtime Database)

Create `database.rules.json` in the repository root. Note how:
- `/system/status` is world-readable so both the website and game can check budget pause state with zero auth.
- All writes and match/lobby reads check `root.child('system/status/paused').val() != true`.
- Abandoned public lobbies (`last_seen < (now - 45000)`, i.e. 45 seconds without a host heartbeat) can be deleted by any authenticated client so dead lobbies are purged immediately (Hole H14).

```json
{
  "rules": {
    "system": {
      "status": {
        ".read": true,
        ".write": false
      }
    },
    "codes": {
      "$code": {
        ".read": "auth != null && root.child('system/status/paused').val() != true",
        ".write": "auth != null && root.child('system/status/paused').val() != true && (
          (!data.exists() && newData.child('host_uid').val() == auth.uid) ||
          (data.exists() && data.child('host_uid').val() == auth.uid) ||
          (!newData.exists() && data.child('created_at').val() < ((now / 1000) - 3600))
        )"
      }
    },
    "lobbies": {
      ".read": "auth != null && root.child('system/status/paused').val() != true",
      ".indexOn": ["last_seen", "created_at"],
      "$matchId": {
        ".write": "auth != null && root.child('system/status/paused').val() != true && (
          (!data.exists() && newData.child('host_uid').val() == auth.uid) ||
          (data.exists() && data.child('host_uid').val() == auth.uid) ||
          (!newData.exists() && data.child('last_seen').val() < ((now / 1000) - 45))
        )"
      }
    },
    "matches": {
      "$matchId": {
        ".read": "auth != null && root.child('system/status/paused').val() != true",
        "meta": {
          ".write": "auth != null && root.child('system/status/paused').val() != true && (
            (!data.exists() && newData.child('host_uid').val() == auth.uid) ||
            (data.exists() && data.child('host_uid').val() == auth.uid) ||
            (data.exists() && root.child('matches/' + $matchId + '/devices/' + auth.uid).exists() && newData.child('host_uid').val() == data.child('host_uid').val())
          )"
        },
        "devices": {
          "$deviceUid": {
            ".write": "auth != null && root.child('system/status/paused').val() != true && (
              (auth.uid == $deviceUid && (
                data.exists() ||
                root.child('matches/' + $matchId + '/meta/status').val() == 'lobby'
              )) ||
              (root.child('matches/' + $matchId + '/meta/host_uid').val() == auth.uid)
            )"
          }
        },
        "golfers": {
          "$slotId": {
            ".write": "auth != null && root.child('system/status/paused').val() != true && (
              (!data.exists() && root.child('matches/' + $matchId + '/meta/status').val() == 'lobby' && newData.child('owner_uid').val() == auth.uid) ||
              (data.exists() && data.child('owner_uid').val() == auth.uid) ||
              (root.child('matches/' + $matchId + '/meta/host_uid').val() == auth.uid)
            )"
          }
        },
        "events": {
          "$seqKey": {
            ".write": "auth != null && root.child('system/status/paused').val() != true && !data.exists() && root.child('matches/' + $matchId + '/devices/' + auth.uid).exists() && newData.child('by_uid').val() == auth.uid"
          }
        }
      }
    }
  }
}
```

---

## 6. $10/Month Cloud Budget Alert & Automatic Circuit-Breaker Function

### 6.1 `functions/package.json` & `functions/index.js`
Create `functions/package.json` (Node 20, `firebase-admin`, `firebase-functions`) and `functions/index.js`:

```javascript
const { onMessagePublished } = require("firebase-functions/v2/pubsub");
const admin = require("firebase-admin");

admin.initializeApp();

const PAUSE_MESSAGE =
  "Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience.";

// Triggered by Google Cloud Billing Budget notifications on Pub/Sub topic "budget-alerts"
// Default hard cutoff is $9.50 (50c buffer below the $10.00 monthly credit so in-flight requests never exceed $10.00)
const HARD_CAP_USD = parseFloat(process.env.MONTHLY_BUDGET_CAP_USD || "9.50");

exports.enforceBudgetCap = onMessagePublished("budget-alerts", async (event) => {
  const data = event.data.message.json || {};
  const costAmount = parseFloat(data.costAmount || 0);
  const budgetAmount = parseFloat(data.budgetAmount || 10.0);
  const periodStart = data.costIntervalStart || new Date().toISOString().slice(0, 7);

  const db = admin.firestore();
  const rtdb = admin.database();
  const statusRef = db.doc("system/status");
  const currentSnap = await statusRef.get();
  const current = currentSnap.exists ? currentSnap.data() : { paused: false };

  if (costAmount >= HARD_CAP_USD || costAmount >= budgetAmount) {
    if (!current.paused) {
      const payload = {
        schema_version: 1,
        paused: true,
        reason: "monthly_budget_reached",
        paused_month: String(periodStart).slice(0, 7),
        cost_usd: costAmount,
        budget_usd: budgetAmount,
        updated_at: Math.floor(Date.now() / 1000),
        message: PAUSE_MESSAGE,
      };
      await Promise.all([
        statusRef.set(payload, { merge: true }),
        rtdb.ref("system/status").set(payload),
      ]);
      console.warn(`[BudgetGuard] Monthly spend ($${costAmount}) reached cap ($${HARD_CAP_USD}). Multiplayer PAUSED.`);
    }
  } else if (costAmount < 1.0 && current.paused && current.reason === "monthly_budget_reached") {
    // New billing month started (cost reset near $0) -> automatically unpause!
    const payload = {
      schema_version: 1,
      paused: false,
      reason: "",
      paused_month: "",
      cost_usd: costAmount,
      budget_usd: budgetAmount,
      updated_at: Math.floor(Date.now() / 1000),
      message: PAUSE_MESSAGE,
    };
    await Promise.all([
      statusRef.set(payload, { merge: true }),
      rtdb.ref("system/status").set(payload),
    ]);
    console.info(`[BudgetGuard] New billing cycle detected ($${costAmount}). Multiplayer RESUMED.`);
  }
});
```

---

## 7. Full CI/CD Pipeline Automation (`.github/workflows/deploy_firebase.yml`)

Update `firebase.json`, `.github/workflows/deploy_firebase.yml`, and `scripts/deploy/deploy_firebase.ps1` so **every** cloud requirement is deployed automatically via GitHub Actions:

### 7.1 `firebase.json`
```json
{
  "hosting": {
    "public": "web",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  },
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "database": {
    "rules": "database.rules.json"
  },
  "functions": [
    {
      "source": "functions",
      "codebase": "default",
      "runtime": "nodejs20",
      "ignore": [
        "node_modules",
        ".git",
        "*.log"
      ]
    }
  ],
  "emulators": {
    "auth": { "port": 9099 },
    "firestore": { "port": 8080 },
    "database": { "port": 9000 },
    "functions": { "port": 5001 },
    "hosting": { "port": 5000 },
    "pubsub": { "port": 8085 },
    "ui": { "enabled": true }
  }
}
```

### 7.2 `.github/workflows/deploy_firebase.yml` Upgrades
1. Add triggers:
   - Keep `workflow_dispatch` (with `targets`: `all`, `hosting`, `firestore:rules`, `firestore`, `database`, `functions`).
   - Add automatic `push` trigger on `main` when `web/**`, `firestore.rules`, `firestore.indexes.json`, `database.rules.json`, `functions/**`, or `firebase.json` change so you never have to remember to manually deploy rules or website changes!
2. Add steps before `firebase deploy`:
   - **Run Firebase Rules & Budget Function Unit Tests** (`npm --prefix firebase/tests ci && npm --prefix firebase/tests test`).
   - **Install Functions Dependencies** (`npm --prefix functions ci`).
   - **Ensure GCP APIs & Pub/Sub Topic + $10 Budget Exist (when authenticated via Service Account):**
     - Uses `gcloud` (pre-installed on `ubuntu-latest`) to idempotently ensure the `budget-alerts` Pub/Sub topic exists (`gcloud pubsub topics create budget-alerts || true`) and, if `GCP_BILLING_ACCOUNT_ID` is set in GitHub Secrets, ensures a `$10.00/month` budget (`HeckleGolf-10USD-Monthly-Cap`) with `50%`, `80%`, `95%`, `100%` alerts is wired to `projects/heckle-golf-sim/topics/budget-alerts`.
   - **Seed Initial `system/status` Doc (if not present):** Initializes `system/status` with `paused: false` if missing.

### 7.3 `.gitignore` Hardening (Public Repo Secret Audit)
Append to `.gitignore`:
```gitignore
# Cloud & Firebase secrets (never commit to public repo)
*service_account*.json
*firebase_sa*.json
*credentials*.json
.env
.env.*
functions/.runtimeconfig.json
functions/node_modules/
firebase/tests/node_modules/
```

---

## 8. Verification & Tests

Create `firebase/tests/package.json` and `firebase/tests/rules.test.mjs` using `@firebase/rules-unit-testing`:
1. **Owner & Delegate Access:** Verify `uid_1` and approved delegate `uid_2` permissions on `users`, `profiles`, `sync/stats`, `matches`, and `link_requests`.
2. **Verified Email Requirement:** Verify unverified email token cannot approve a `link_request`.
3. **Leaderboard Range Validation:** Verify out-of-range values (`longest_drive_yds: 999`) or `email` fields in `public_profiles` are rejected.
4. **Abandoned Lobby Cleanup Rule:** Verify any authenticated user can delete `/lobbies/{id}` when `last_seen` is older than 45 seconds, and cannot delete an active lobby (`last_seen` within 45s) owned by another host.
5. **$10 Budget Circuit-Breaker Lock Test:** Set `system/status` (`paused: true`) in both Firestore and RTDB emulators, and verify that:
   - Reading `system/status` and `public_profiles` still succeeds (so the game/website can display the friendly pause message and view existing leaderboards).
   - Every client write to `users`, `profiles`, `sync/stats`, `matches`, `link_requests`, `public_profiles`, `/codes`, `/lobbies`, and `/matches` is immediately rejected by security rules.
