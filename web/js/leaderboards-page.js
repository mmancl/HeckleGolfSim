import { initLeaderboards } from "./leaderboards.js";
import { checkBudgetStatus } from "./budget.js";
import { db, doc, getDoc, auth, onAuthStateChanged } from "./firebase-init.js";
import { ensurePublicProfileSynced } from "./portal.js";

function setupLeaderboardsPage() {
  initLeaderboards();
  checkBudgetStatus();

  const btnSignin = document.getElementById("nav-signin-btn");
  const greeting = document.getElementById("user-greeting");
  const avatarEl = document.getElementById("user-avatar");
  const nameEl = document.getElementById("user-name");

  onAuthStateChanged(auth, async (user) => {
    if (user) {
      if (btnSignin) btnSignin.style.display = "none";
      if (greeting) greeting.style.display = "flex";
      const initial = (user.displayName || user.email || "?").charAt(0).toUpperCase();
      if (avatarEl) avatarEl.textContent = initial;
      if (nameEl) nameEl.textContent = user.displayName ? user.displayName.split(" ")[0] : user.email.split("@")[0];

      // Auto-sync public leaderboard profile to ensure records appear live
      try {
        const profSnap = await getDoc(doc(db, "profiles", user.uid));
        if (profSnap.exists()) {
          await ensurePublicProfileSynced(user, profSnap.data());
          if (typeof window.hgsRefreshLeaderboard === "function") {
            window.hgsRefreshLeaderboard();
          }
        }
      } catch (err) {
        console.warn("[Leaderboards] Auto-sync public profile notice:", err);
      }
    } else {
      if (btnSignin) btnSignin.style.display = "";
      if (greeting) greeting.style.display = "none";
    }
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setupLeaderboardsPage);
} else {
  setupLeaderboardsPage();
}
