# Work Package 06 — Website: Player Stats Portal, Public Leaderboards & Link Approvals

> **Prerequisite:** Read [`00_OVERVIEW.md`](00_OVERVIEW.md) and [`01_FIREBASE_BACKEND_SCHEMA_RULES.md`](01_FIREBASE_BACKEND_SCHEMA_RULES.md).
> **Can start:** Immediately (Phase 0). Has zero GDScript dependencies — only depends on the Firestore schema in Package 01.
> **Owns:** `web/index.html` (and any modular JS/CSS files added under `web/`).

---

## 1. Scope & Goals

Upgrade `web/index.html` (currently has placeholder `"Your stats will appear here once web tracking launches"` at `web/index.html` L645–652 and L1000–1060) to deliver:
1. **Public Global Leaderboards section (`#leaderboards`)** visible to **all visitors without signing in** (Requirement G5), matching the 7 categories in Package 05.
2. **Full Player Portal (`#stats-signin`)** for any signed-in user:
   - Sign-In **and Sign-Up** (Create Account + Password Reset + Email Verification prompt) so a friend (`user2`) visiting `user1`'s house can create an account on their phone in 30 seconds and approve linking on the spot (Hole H8).
   - **Overview Cards:** Matches Played, Wins / W-L-T, Avg Score to Par, Best 18-Hole Score, Longest Drive, Longest Putt, Achievements Unlocked.
   - **Club Distances & Averages Table:** Carry, Total, Ball Speed, Club Speed, Smash Factor, Spin, and Shot Count per club (read from `profiles/{uid}.club_summary` in **1 document read**).
   - **Best Courses & Recent Matches List:** Course records (`lifetime.best_courses`) + recent match scorecards (`profiles/{uid}/matches` ordered by `played_at desc`, `limit(10)`).
   - **Swing Analysis & Achievements Tab:** Monthly swing issue counts and unlocked achievements (lazy-loaded from `profiles/{uid}/sync/stats` only when the user clicks that tab).
3. **Account Link Approvals & Shared Access Panel:**
   - Displays incoming pending `link_requests` where `target_email_lower == user.email.toLowerCase()` with one-tap **`Approve`** and **`Deny`** buttons.
   - Displays currently approved delegates (`profiles/{uid}/delegates`) with a **`Revoke`** button.
4. **Monthly Budget-Paused Banner & Leaderboard Opt-Out Controls:**
   - Reads `system/status` on page load (cached in `sessionStorage` for 5 minutes) and whenever a write fails with `permission-denied`. If `paused === true`, displays a prominent, friendly banner in the Player Portal and Leaderboards sections:
     > **"Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."**
   - Default `leaderboard_opt_in` to `true` on new accounts (Owner Decision D6), with a toggle to opt out or delete cloud account data.

---

## 2. Firebase Web SDK Imports (`web/index.html`)

Extend the existing Firebase `10.12.0` module script in `web/index.html` (`L979–999`) to import Firestore and additional Auth methods:

```javascript
import {
  getAuth, onAuthStateChanged,
  signInWithEmailAndPassword, createUserWithEmailAndPassword,
  sendPasswordResetEmail, sendEmailVerification, updateProfile,
  signInWithPopup, GoogleAuthProvider, signOut, deleteUser
} from "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js";

import {
  getFirestore, doc, getDoc, setDoc, updateDoc, deleteDoc,
  collection, query, where, orderBy, limit, getDocs, writeBatch
} from "https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore.js";
```

---

## 3. Public Leaderboards Section (`#leaderboards`)

### 3.1 Placement & Navigation
- Add a `"Leaderboards"` link in the top navbar (`web/index.html`) scrolling smoothly to `<section id="leaderboards">` placed right above `<section id="stats-signin">`.
- Works for anonymous visitors with **zero authentication required** (`public_profiles` has `allow read: if true;`).

### 3.2 Categories & Client-Side Caching (Hole H21)
Support the same 7 tabs as Package 05:
1. **Longest Drive** (`orderBy("longest_drive_yds", "desc")`, `limit(25)`)
2. **Longest Putt** (`orderBy("longest_putt_ft", "desc")`, `limit(25)`)
3. **Lowest Score (18H)** (`orderBy("best_to_par_18", "asc")`, `limit(25)`)
4. **Lowest Score (9H)** (`orderBy("best_to_par_9", "asc")`, `limit(25)`)
5. **Most Achievements** (`orderBy("achievements_count", "desc")`, `limit(25)`)
6. **Most Games Played** (`orderBy("matches_played", "desc")`, `limit(25)`)
7. **Most Wins** (`orderBy("wins", "desc")`, `limit(25)`)

**Cost control:** Cache each category's query result in `sessionStorage` under key `hgs_lb_{categoryId}` with a 10-minute timestamp TTL so switching tabs or refreshing the page does not re-read 25 Firestore docs each time.

---

## 4. Signed-In Player Portal (`#stats-signin`)

### 4.1 Sign-In / Sign-Up / Password Reset Toggle
Update `#signin-form` (`web/index.html` L631–643):
- Add a mode toggle: **Sign In** ↔ **Create Account** (adds Display Name input and calls `createUserWithEmailAndPassword` + `updateProfile` + `sendEmailVerification` + initializes `users/{uid}` and `profiles/{uid}`).
- Add a **"Forgot password?"** link that calls `sendPasswordResetEmail(auth, email)`.

### 4.2 Dashboard Data Loading (Minimal Reads)
When `onAuthStateChanged` fires with a signed-in `user`:
1. **Read 1:** `getDoc(doc(db, "profiles", user.uid))`
   - Renders the 6 top summary stat boxes (`lifetime.matches_played`, `lifetime.wins`, `avg_to_par`, `lifetime.best_to_par_18` / `best_gross_18`, `lifetime.longest_drive_yds`, `lifetime.longest_putt_ft`, `lifetime.achievements_count`).
   - Renders the **Club Distances & Averages** table from `profile.club_summary` (ordered by standard bag order: `Dr`, `3W`, `5W`, `7W`, `2H`–`5H`, `3i`–`9i`, `PW`, `GW`, `SW`, `LW`, `Pt`).
   - Renders **Best Courses** from `profile.lifetime.best_courses`.
2. **Read 2:** Check pending link requests addressed to `user.email.toLowerCase()`:
   - `getDocs(query(collection(db, "link_requests"), where("target_email_lower", "==", user.email.toLowerCase())))`
   - If any request has `status === "pending"`, show a prominent banner at the top of the portal:
     > 🔔 **`{requester_name}` (`{requester_email}`) wants to sync your player stats on their simulator.**
     > `[Approve Access]` `[Deny]`
3. **Lazy-Loaded Tabs (only fetched when clicked):**
   - **Recent Matches Tab:** `getDocs(query(collection(db, "profiles", user.uid, "matches"), orderBy("played_at", "desc"), limit(10)))` — expandable hole-by-hole scorecard rows.
   - **Achievements & Swing Analysis Tab:** `getDoc(doc(db, "profiles", user.uid, "sync", "stats"))` — shows unlocked achievements and monthly swing recommendations (`swing_issues`).
   - **Shared Access & Privacy Tab:**
     - Lists active delegates (`getDocs(collection(db, "profiles", user.uid, "delegates"))`) with a **`Revoke`** button.
     - Toggle: **"Show my profile on public leaderboards"** (updates `users/{uid}.leaderboard_opt_in` and creates/deletes `public_profiles/{uid}`).
     - **"Delete Account & Cloud Data"** button (deletes `public_profiles/{uid}`, `profiles/{uid}/sync/stats`, `profiles/{uid}`, `users/{uid}`, and calls `deleteUser(user)`).

---

## 5. Approving or Revoking a Link Request on the Web

### 5.1 Approve Action
1. Check `user.emailVerified`. If `false`, show a button to call `sendEmailVerification(user)` and `await user.reload(); await user.getIdToken(true);` (Hole H7).
2. Execute a Firestore `writeBatch(db)`:
   ```javascript
   const batch = writeBatch(db);
   // Ensure profiles/{uid} exists even if user2 just created their account on the web
   batch.set(doc(db, "profiles", user.uid), {
     schema_version: 1,
     owner_uid: user.uid,
     display_name: user.displayName || user.email.split("@")[0],
     updated_at: Math.floor(Date.now() / 1000)
   }, { merge: true });
   batch.set(doc(db, "profiles", user.uid, "delegates", req.requester_uid), {
     delegate_uid: req.requester_uid,
     delegate_name: req.requester_name || "",
     delegate_email: req.requester_email || "",
     approved_at: Math.floor(Date.now() / 1000),
     request_id: req.id
   });
   batch.update(doc(db, "link_requests", req.id), {
     status: "approved",
     target_uid: user.uid,
     target_display_name: user.displayName || user.email.split("@")[0],
     updated_at: Math.floor(Date.now() / 1000)
   });
   await batch.commit();
   ```

### 5.2 Revoke Action
```javascript
const batch = writeBatch(db);
batch.delete(doc(db, "profiles", user.uid, "delegates", delegate.delegate_uid));
if (delegate.request_id) {
  batch.update(doc(db, "link_requests", delegate.request_id), {
    status: "revoked",
    updated_at: Math.floor(Date.now() / 1000)
  });
}
await batch.commit();
```

---

## 6. Verification Checklist

1. Serve `web/` locally (`npx firebase-tools serve --only hosting` or any static server) and verify:
   - Signed-out visitor sees the **Global Leaderboards** section and can switch between all 7 leaderboard tabs.
   - New user can **Create Account**, verify email, and immediately see pending link requests sent to their email.
   - Signed-in user with synced data sees their overview cards, club distances table, best courses, recent matches, and can toggle leaderboard visibility or delete their cloud account.
   - Mobile viewport (`375px` width) renders the Sign-In card, Approval banner, and Leaderboards table cleanly without horizontal overflow.
