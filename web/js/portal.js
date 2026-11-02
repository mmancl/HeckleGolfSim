import {
  auth,
  db,
  provider,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  sendPasswordResetEmail,
  sendEmailVerification,
  updateProfile,
  signInWithPopup,
  GoogleAuthProvider,
  signOut,
  deleteUser,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  query,
  where,
  orderBy,
  limit,
  getDocs,
  writeBatch
} from "./firebase-init.js";
import { checkBudgetStatus, handleWriteError } from "./budget.js";

const STANDARD_CLUBS = [
  "Dr", "3w", "5w", "2H", "3H", "4H", "1i", "2i", "3i", "4i",
  "5i", "6i", "7i", "8i", "9i", "Pw", "Gw", "Sw", "Lw", "Pt"
];

const STANDARD_14_BAG = [
  "Dr", "3w", "5w", "4H", "5i", "6i", "7i", "8i", "9i", "Pw", "Gw", "Sw", "Lw", "Pt"
];

const STANDARD_BAG_ORDER = [
  "Dr", "3w", "3W", "5w", "5W", "7w", "7W", "2H", "3H", "4H", "5H",
  "1i", "2i", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "Pw", "PW", "Gw", "GW", "Sw", "SW", "Lw", "LW", "Pt"
];

const CLUB_LABELS = {
  Dr: "Driver",
  "3w": "3 Wood", "3W": "3 Wood",
  "5w": "5 Wood", "5W": "5 Wood",
  "7w": "7 Wood", "7W": "7 Wood",
  "2H": "2 Hybrid",
  "3H": "3 Hybrid",
  "4H": "4 Hybrid",
  "5H": "5 Hybrid",
  "1i": "1 Iron",
  "2i": "2 Iron",
  "3i": "3 Iron",
  "4i": "4 Iron",
  "5i": "5 Iron",
  "6i": "6 Iron",
  "7i": "7 Iron",
  "8i": "8 Iron",
  "9i": "9 Iron",
  Pw: "Pitching Wedge", PW: "Pitching Wedge",
  Gw: "Gap Wedge", GW: "Gap Wedge",
  Sw: "Sand Wedge", SW: "Sand Wedge",
  Lw: "Lob Wedge", LW: "Lob Wedge",
  Pt: "Putter"
};

const ACHIEVEMENT_LABELS = {
  first_par: { title: "First Par", desc: "Scored your first par on any hole" },
  first_birdie: { title: "First Birdie", desc: "Scored 1 under par on a hole" },
  first_eagle: { title: "First Eagle", desc: "Scored 2 under par on a hole" },
  hole_in_one: { title: "Ace / Hole in One", desc: "Holed out in a single shot" },
  long_drive: { title: "Long Drive", desc: "Crushed a drive over 300 yards" },
  long_putt: { title: "Monster Putt", desc: "Drained a putt longer than 30 feet" },
  round_under_par: { title: "Red Numbers", desc: "Finished an 18-hole round under par" },
  sand_save: { title: "Sand Save", desc: "Made par or better from a bunker" },
  green_in_regulation: { title: "Pure Striking", desc: "Hit 10+ greens in regulation" },
  range_grinder: { title: "Range Grinder", desc: "Hit 100+ balls on the driving range" },
  putting_master: { title: "Putting Master", desc: "Mastered the putting practice minigame" },
  chipping_master: { title: "Chipping Master", desc: "Mastered the chipping practice minigame" },
  heckle_veteran: { title: "Thick Skinned", desc: "Heard 50+ unique heckles" },
  multiplayer_winner: { title: "Match Winner", desc: "Won your first online multiplayer match" }
};

let currentUser = null;
let currentProfile = null;
let currentTab = "overview";
let loadedTabs = { overview: false, matches: false, achievements: false, settings: false };
let pendingDeviceCode = "";
let pendingLoopbackPort = "";
let deviceHandoffCompleted = false;
let activeConfirmCallback = null;
let toastTimeout = null;

export function initPortal() {
  const urlParams = new URLSearchParams(window.location.search);
  pendingDeviceCode = (urlParams.get("device_code") || "").trim().toUpperCase();
  pendingLoopbackPort = (urlParams.get("port") || "").trim();

  bindAuthModeToggles();
  bindAuthForms();
  bindPortalTabs();
  bindPlayerManagement();

  // Listen to Auth state
  onAuthStateChanged(auth, async (user) => {
    currentUser = user;
    updateNavAuth(user);

    if (pendingDeviceCode && !deviceHandoffCompleted) {
      showAuthView();
      setTimeout(() => {
        document.getElementById("stats-signin")?.scrollIntoView({ behavior: "smooth" });
      }, 150);
      showFeedback(
        `Connecting to Heckle Golf Simulator (Code: ${pendingDeviceCode}). Click "Continue with Google" below to sign in to the game.`,
        false
      );
      return;
    }

    if (user) {
      showPortalView();
      await loadUserData(user);
    } else {
      showAuthView();
    }
  });

  // Check budget status on load
  checkBudgetStatus(false);
}

// ─── NAV AUTH UI ───
function updateNavAuth(user) {
  const btnSignin = document.getElementById("nav-signin-btn");
  const greeting = document.getElementById("user-greeting");
  const avatarEl = document.getElementById("user-avatar");
  const nameEl = document.getElementById("user-name");

  if (user) {
    if (btnSignin) btnSignin.style.display = "none";
    if (greeting) greeting.style.display = "flex";
    const initial = (user.displayName || user.email || "?").charAt(0).toUpperCase();
    if (avatarEl) avatarEl.textContent = initial;
    if (nameEl) nameEl.textContent = user.displayName ? user.displayName.split(" ")[0] : user.email.split("@")[0];
  } else {
    if (btnSignin) btnSignin.style.display = "";
    if (greeting) greeting.style.display = "none";
  }
}

// ─── AUTH MODE SWITCHING ───
function bindAuthModeToggles() {
  const btnSigninMode = document.getElementById("mode-btn-signin");
  const btnSignupMode = document.getElementById("mode-btn-signup");
  const linkForgot = document.getElementById("link-forgot-pw");
  const linkBackToSignin = document.getElementById("link-back-to-signin");
  const linkToSignup = document.getElementById("link-to-signup");

  if (btnSigninMode) btnSigninMode.addEventListener("click", () => setAuthMode("signin"));
  if (btnSignupMode) btnSignupMode.addEventListener("click", () => setAuthMode("signup"));
  if (linkForgot) linkForgot.addEventListener("click", () => setAuthMode("forgot"));
  if (linkBackToSignin) linkBackToSignin.addEventListener("click", () => setAuthMode("signin"));
  if (linkToSignup) linkToSignup.addEventListener("click", () => setAuthMode("signup"));
}

function setAuthMode(mode) {
  const signinForm = document.getElementById("signin-form");
  const signupForm = document.getElementById("signup-form");
  const forgotForm = document.getElementById("forgot-form");
  const btnSigninMode = document.getElementById("mode-btn-signin");
  const btnSignupMode = document.getElementById("mode-btn-signup");
  const googleBtn = document.getElementById("google-signin-btn");
  const divider = document.querySelector(".divider");
  const authModesContainer = document.querySelector(".auth-modes");

  clearFeedback();

  if (mode === "signin") {
    if (signinForm) signinForm.style.display = "";
    if (signupForm) signupForm.style.display = "none";
    if (forgotForm) forgotForm.style.display = "none";
    if (btnSigninMode) btnSigninMode.classList.add("active");
    if (btnSignupMode) btnSignupMode.classList.remove("active");
    if (googleBtn) googleBtn.style.display = "";
    if (divider) divider.style.display = "";
    if (authModesContainer) authModesContainer.style.display = "flex";
  } else if (mode === "signup") {
    if (signinForm) signinForm.style.display = "none";
    if (signupForm) signupForm.style.display = "";
    if (forgotForm) forgotForm.style.display = "none";
    if (btnSigninMode) btnSigninMode.classList.remove("active");
    if (btnSignupMode) btnSignupMode.classList.add("active");
    if (googleBtn) googleBtn.style.display = "";
    if (divider) divider.style.display = "";
    if (authModesContainer) authModesContainer.style.display = "flex";
  } else if (mode === "forgot") {
    if (signinForm) signinForm.style.display = "none";
    if (signupForm) signupForm.style.display = "none";
    if (forgotForm) forgotForm.style.display = "";
    if (googleBtn) googleBtn.style.display = "none";
    if (divider) divider.style.display = "none";
    if (authModesContainer) authModesContainer.style.display = "none";
  }
}

function showFeedback(message, isError = true) {
  const el = document.getElementById("auth-feedback");
  if (!el) return;
  el.className = `auth-feedback ${isError ? "error" : "success"}`;
  el.textContent = message;
}

function clearFeedback() {
  const el = document.getElementById("auth-feedback");
  if (!el) return;
  el.className = "auth-feedback";
  el.textContent = "";
}

// ─── BIND AUTH FORMS ───
function bindAuthForms() {
  // Sign In
  const signinForm = document.getElementById("signin-form");
  if (signinForm) {
    signinForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      clearFeedback();
      const email = document.getElementById("email").value.trim();
      const password = document.getElementById("password").value;
      const btn = signinForm.querySelector("button[type='submit']");

      btn.textContent = "Signing In…";
      btn.disabled = true;

      try {
        await signInWithEmailAndPassword(auth, email, password);
      } catch (err) {
        showFeedback(formatAuthError(err.code || err.message), true);
        btn.textContent = "Sign In";
        btn.disabled = false;
      }
    });
  }

  // Create Account (Sign Up)
  const signupForm = document.getElementById("signup-form");
  if (signupForm) {
    signupForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      clearFeedback();
      const name = document.getElementById("signup-name").value.trim();
      const email = document.getElementById("signup-email").value.trim();
      const password = document.getElementById("signup-password").value;
      const btn = signupForm.querySelector("button[type='submit']");

      if (name.length < 1 || name.length > 40) {
        showFeedback("Display Name must be between 1 and 40 characters.", true);
        return;
      }
      if (password.length < 6) {
        showFeedback("Password must be at least 6 characters.", true);
        return;
      }

      btn.textContent = "Creating Account…";
      btn.disabled = true;

      try {
        const cred = await createUserWithEmailAndPassword(auth, email, password);
        const newUser = cred.user;

        // 1. Update displayName
        await updateProfile(newUser, { displayName: name });

        // 2. Send email verification
        await sendEmailVerification(newUser);

        // 3. Initialize users/{uid} and profiles/{uid}
        const now = Math.floor(Date.now() / 1000);
        await setDoc(doc(db, "users", newUser.uid), {
          schema_version: 1,
          email_lower: newUser.email.toLowerCase(),
          display_name: name,
          created_at: now,
          last_login_at: now,
          leaderboard_opt_in: true,
          linked_cloud_uids: []
        }, { merge: true });

        await setDoc(doc(db, "profiles", newUser.uid), {
          schema_version: 1,
          owner_uid: newUser.uid,
          display_name: name,
          updated_at: now,
          rev: 1
        }, { merge: true });

        showFeedback("Account created! A verification email has been sent to " + email + ".", false);
      } catch (err) {
        const pauseMsg = await handleWriteError(err);
        if (pauseMsg) {
          showFeedback(pauseMsg, true);
        } else {
          showFeedback(formatAuthError(err.code || err.message), true);
        }
        btn.textContent = "Create Account";
        btn.disabled = false;
      }
    });
  }

  // Forgot Password
  const forgotForm = document.getElementById("forgot-form");
  if (forgotForm) {
    forgotForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      clearFeedback();
      const email = document.getElementById("forgot-email").value.trim();
      const btn = forgotForm.querySelector("button[type='submit']");

      btn.textContent = "Sending Link…";
      btn.disabled = true;

      try {
        await sendPasswordResetEmail(auth, email);
        showFeedback("Password reset link sent! Check your inbox.", false);
        btn.textContent = "Send Reset Link";
        btn.disabled = false;
      } catch (err) {
        showFeedback(formatAuthError(err.code || err.message), true);
        btn.textContent = "Send Reset Link";
        btn.disabled = false;
      }
    });
  }

  // Google Sign-In
  const googleBtn = document.getElementById("google-signin-btn");
  if (googleBtn) {
    googleBtn.addEventListener("click", async () => {
      clearFeedback();
      try {
        const result = await signInWithPopup(auth, provider);
        const user = result.user;
        const credential = GoogleAuthProvider.credentialFromResult(result);
        const googleIdToken = credential ? credential.idToken : "";
        const now = Math.floor(Date.now() / 1000);

        if (pendingDeviceCode && googleIdToken) {
          try {
            const fbToken = await user.getIdToken();
            await fetch(
              `https://heckle-golf-sim-default-rtdb.firebaseio.com/auth_handoff/${encodeURIComponent(pendingDeviceCode)}.json?auth=${encodeURIComponent(fbToken)}`,
              {
                method: "PUT",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                  google_id_token: googleIdToken,
                  uid: user.uid,
                  created_at: now
                })
              }
            );
          } catch (_) {}

          if (pendingLoopbackPort) {
            try {
              await fetch(
                `http://127.0.0.1:${encodeURIComponent(pendingLoopbackPort)}/callback?code=${encodeURIComponent(pendingDeviceCode)}&id_token=${encodeURIComponent(googleIdToken)}`,
                { method: "GET", mode: "cors" }
              );
            } catch (_) {}
          }

          deviceHandoffCompleted = true;
          showFeedback(
            "✅ Signed in to Heckle Golf Simulator! You can now switch back to the game window.",
            false
          );
        }

        // Ensure users/{uid} and profiles/{uid} exist
        await setDoc(doc(db, "users", user.uid), {
          schema_version: 1,
          email_lower: user.email.toLowerCase(),
          display_name: user.displayName || user.email.split("@")[0],
          last_login_at: now,
          leaderboard_opt_in: true
        }, { merge: true });

        await setDoc(doc(db, "profiles", user.uid), {
          schema_version: 1,
          owner_uid: user.uid,
          display_name: user.displayName || user.email.split("@")[0],
          updated_at: now
        }, { merge: true });

        if (pendingDeviceCode && deviceHandoffCompleted) {
          setTimeout(async () => {
            showPortalView();
            await loadUserData(user);
          }, 2500);
        }
      } catch (err) {
        if (err.code !== "auth/popup-closed-by-user") {
          showFeedback(formatAuthError(err.code || err.message), true);
        }
      }
    });
  }

  // Nav scroll triggers or redirects
  const btnNavSignin = document.getElementById("nav-signin-btn");
  if (btnNavSignin) {
    btnNavSignin.addEventListener("click", () => {
      const statsElem = document.getElementById("stats-signin");
      if (statsElem) {
        statsElem.scrollIntoView({ behavior: "smooth" });
      } else {
        window.location.href = "portal.html";
      }
    });
  }
  const greetingEl = document.getElementById("user-greeting");
  if (greetingEl) {
    greetingEl.addEventListener("click", (e) => {
      if (e.target.id !== "signout-btn") {
        const statsElem = document.getElementById("stats-signin");
        if (statsElem) {
          statsElem.scrollIntoView({ behavior: "smooth" });
        } else {
          window.location.href = "portal.html";
        }
      }
    });
  }

  // Sign out buttons
  const signoutBtn = document.getElementById("signout-btn");
  if (signoutBtn) {
    signoutBtn.addEventListener("click", () => signOut(auth));
  }
  const portalSignoutBtn = document.getElementById("portal-signout-btn");
  if (portalSignoutBtn) {
    portalSignoutBtn.addEventListener("click", () => signOut(auth));
  }

  // Resend verification email
  const btnResendVerify = document.getElementById("btn-resend-verify");
  if (btnResendVerify) {
    btnResendVerify.addEventListener("click", async () => {
      if (!currentUser) return;
      btnResendVerify.textContent = "Sending…";
      btnResendVerify.disabled = true;
      try {
        await sendEmailVerification(currentUser);
        alert("Verification email sent to " + currentUser.email + ". Please check your inbox or spam folder.");
      } catch (err) {
        alert("Could not send verification email: " + err.message);
      } finally {
        btnResendVerify.textContent = "Resend Verification Email";
        btnResendVerify.disabled = false;
      }
    });
  }

  // Refresh verification status
  const btnCheckVerify = document.getElementById("btn-check-verify");
  if (btnCheckVerify) {
    btnCheckVerify.addEventListener("click", async () => {
      if (!currentUser) return;
      btnCheckVerify.textContent = "Checking…";
      btnCheckVerify.disabled = true;
      try {
        await currentUser.reload();
        await currentUser.getIdToken(true);
        updateVerificationBanner(currentUser);
        if (currentUser.emailVerified) {
          await checkIncomingLinkRequests(currentUser);
        }
      } catch (err) {
        alert("Could not refresh status: " + err.message);
      } finally {
        btnCheckVerify.textContent = "I've Verified (Refresh)";
        btnCheckVerify.disabled = false;
      }
    });
  }
}

function formatAuthError(codeOrMsg) {
  if (codeOrMsg.includes("user-not-found") || codeOrMsg.includes("wrong-password") || codeOrMsg.includes("invalid-credential")) {
    return "Invalid email or password.";
  }
  if (codeOrMsg.includes("email-already-in-use")) {
    return "An account with this email already exists.";
  }
  if (codeOrMsg.includes("weak-password")) {
    return "Password is too weak. Please use at least 6 characters.";
  }
  if (codeOrMsg.includes("invalid-email")) {
    return "Please enter a valid email address.";
  }
  return codeOrMsg;
}

// ─── PORTAL VIEW TOGGLING ───
function showAuthView() {
  const signinCard = document.querySelector(".signin-card");
  const playerPortal = document.getElementById("player-portal");
  const signinInfo = document.querySelector(".signin-info");

  if (signinCard) signinCard.style.display = "";
  if (playerPortal) playerPortal.style.display = "none";
  if (signinInfo) signinInfo.style.display = "";

  setAuthMode("signin");
  loadedTabs = { overview: false, matches: false, achievements: false, settings: false };
}

function showPortalView() {
  const signinCard = document.querySelector(".signin-card");
  const playerPortal = document.getElementById("player-portal");
  const signinInfo = document.querySelector(".signin-info");

  if (signinCard) signinCard.style.display = "none";
  if (playerPortal) playerPortal.style.display = "block";
  if (signinInfo) signinInfo.style.display = "none";
}

// ─── TAB NAVIGATION ───
function bindPortalTabs() {
  const tabBtns = document.querySelectorAll(".portal-tab-btn");
  tabBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      const tabName = btn.dataset.tab;
      switchPortalTab(tabName);
    });
  });
}

function switchPortalTab(tabName) {
  currentTab = tabName;
  document.querySelectorAll(".portal-tab-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.tab === tabName);
  });
  document.querySelectorAll(".portal-tab-pane").forEach((pane) => {
    pane.classList.toggle("active", pane.id === `portal-tab-${tabName}`);
  });

  // Lazy load tab data
  if (!loadedTabs[tabName] && currentUser) {
    if (tabName === "matches") loadRecentMatches(currentUser);
    else if (tabName === "achievements") loadAchievementsAndSwing(currentUser);
    else if (tabName === "settings") loadSharedAccessAndSettings(currentUser);
  }
}

// ─── LOAD USER DATA (READ 1 & READ 2) ───
export async function ensurePublicProfileSynced(user, profile) {
  if (!user || !profile) return;
  try {
    const optIn = profile?.privacy?.leaderboard_opt_in !== false;
    if (!optIn) {
      try {
        await deleteDoc(doc(db, "public_profiles", user.uid));
      } catch {}
      return;
    }

    const lt = profile.lifetime || {};
    const rec = profile.records || {};
    const ach = profile.achievements || {};
    let achCount = 0;
    if (ach.unlocked && typeof ach.unlocked === "object") {
      achCount = Object.keys(ach.unlocked).length;
    } else if (typeof lt.achievements_count === "number") {
      achCount = lt.achievements_count;
    }

    const longestDr = Number(lt.longest_drive_yds ?? rec.longest_drive ?? rec.longest_drive_yds ?? profile.longest_drive_yds ?? 0);
    const longestPt = Number(lt.longest_putt_ft ?? rec.longest_putt ?? rec.longest_putt_ft ?? profile.longest_putt_ft ?? 0);
    const matchesPl = Number(lt.matches_played ?? 0);
    const wins = Number(lt.wins ?? 0);

    const rawName = profile.display_name || user.displayName || user.email?.split("@")[0] || "Golfer";
    const displayName = String(rawName).trim().slice(0, 40) || "Golfer";

    const pubData = {
      schema_version: 1,
      uid: user.uid,
      display_name: displayName,
      avatar: String(profile.avatar || ""),
      longest_drive_yds: Math.min(Math.max(0, isNaN(longestDr) ? 0 : longestDr), 450.0),
      longest_putt_ft: Math.min(Math.max(0, isNaN(longestPt) ? 0 : longestPt), 180.0),
      achievements_count: Math.min(Math.max(0, isNaN(achCount) ? 0 : achCount), 100),
      matches_played: Math.min(Math.max(0, isNaN(matchesPl) ? 0 : matchesPl), 100000),
      wins: Math.min(Math.max(0, isNaN(wins) ? 0 : wins), 100000),
      updated_at: Math.floor(Date.now() / 1000)
    };

    const bg18 = Number(lt.best_gross_18 ?? rec.best_gross_18);
    if (!isNaN(bg18) && bg18 >= 18 && bg18 <= 250) {
      pubData.best_gross_18 = bg18;
      const btp18 = Number(lt.best_to_par_18 ?? rec.best_to_par_18);
      if (!isNaN(btp18) && btp18 >= -36 && btp18 <= 180) pubData.best_to_par_18 = btp18;
    }

    const bg9 = Number(lt.best_gross_9 ?? rec.best_gross_9);
    if (!isNaN(bg9) && bg9 >= 9 && bg9 <= 130) {
      pubData.best_gross_9 = bg9;
      const btp9 = Number(lt.best_to_par_9 ?? rec.best_to_par_9);
      if (!isNaN(btp9) && btp9 >= -18 && btp9 <= 90) pubData.best_to_par_9 = btp9;
    }

    // Write directly without merge: true to purge any legacy invalid fields
    await setDoc(doc(db, "public_profiles", user.uid), pubData);

    // Clear stale cached leaderboard entries
    sessionStorage.removeItem("hgs_lb_longest_drive");
    sessionStorage.removeItem("hgs_lb_longest_putt");
    sessionStorage.removeItem("hgs_lb_lowest_score_18");
    sessionStorage.removeItem("hgs_lb_lowest_score_9");
    sessionStorage.removeItem("hgs_lb_most_wins");
    sessionStorage.removeItem("hgs_lb_most_matches");
    sessionStorage.removeItem("hgs_lb_achievements");
  } catch (err) {
    console.warn("[Portal] Public leaderboard projection sync warning:", err);
  }
}

async function loadUserData(user) {
  updateUserHeader(user);
  updateVerificationBanner(user);

  try {
    // 1. Read 1: profiles/{uid}
    const profileSnap = await getDoc(doc(db, "profiles", user.uid));
    if (profileSnap.exists()) {
      currentProfile = profileSnap.data();
    } else {
      currentProfile = {
        schema_version: 1,
        owner_uid: user.uid,
        display_name: user.displayName || user.email.split("@")[0],
        updated_at: Math.floor(Date.now() / 1000)
      };
    }

    // Also fetch sync/stats if available to ensure full telemetry & records
    try {
      const statsSnap = await getDoc(doc(db, "profiles", user.uid, "sync", "stats"));
      if (statsSnap.exists()) {
        const syncStats = statsSnap.data();
        if (!currentProfile.lifetime) currentProfile.lifetime = {};
        const lt = currentProfile.lifetime;
        const rec = syncStats.records || {};
        const recDr = Number(rec.longest_drive_yds ?? rec.longest_drive ?? 0);
        if (recDr > Number(lt.longest_drive_yds ?? 0)) {
          lt.longest_drive_yds = recDr;
        }
        const recPt = Number(rec.longest_putt_ft ?? rec.longest_putt ?? 0);
        if (recPt > Number(lt.longest_putt_ft ?? 0)) {
          lt.longest_putt_ft = recPt;
        }

        if (syncStats.clubs && typeof syncStats.clubs === "object") {
          if (!currentProfile.club_summary) currentProfile.club_summary = {};
          for (const [clb, rawShots] of Object.entries(syncStats.clubs)) {
            if (!Array.isArray(rawShots) || rawShots.length === 0) continue;
            const existing = currentProfile.club_summary[clb] || {};
            let carrySum = 0, totalSum = 0, speedSum = 0, clubSpeedSum = 0, spinSum = 0, offlineSum = 0;
            let faceSum = 0, faceCount = 0, pathSum = 0, pathCount = 0;
            const impactPts = [];

            rawShots.forEach((s) => {
              const cm = Number(s.CarryDistance ?? s.c ?? 0);
              const tm = Number(s.TotalDistance ?? s.tot ?? 0);
              carrySum += cm * 1.09361;
              totalSum += tm * 1.09361;
              speedSum += Number(s.BallSpeed ?? s.Speed ?? s.bs ?? 0);
              clubSpeedSum += Number(s.ClubSpeed ?? s.cs ?? 0);
              spinSum += Number(s.TotalSpin ?? s.sp ?? 0);
              const sideM = Math.abs(Number(s.SideDistance ?? s.sd ?? 0));
              offlineSum += sideM * 1.09361;

              if (s.FaceAngle != null || s.ClubFaceAngle != null || s.fa != null) {
                faceSum += Number(s.FaceAngle ?? s.ClubFaceAngle ?? s.fa);
                faceCount++;
              }
              if (s.ClubPath != null || s.Path != null || s.cp != null) {
                pathSum += Number(s.ClubPath ?? s.Path ?? s.cp);
                pathCount++;
              }
              if (s.HorizontalFaceImpact != null || s.VerticalFaceImpact != null || s.hi != null || s.vi != null) {
                impactPts.push({
                  h: Math.round(Number(s.HorizontalFaceImpact ?? s.hi ?? 0) * 10) / 10,
                  v: Math.round(Number(s.VerticalFaceImpact ?? s.vi ?? 0) * 10) / 10
                });
              }
            });

            const n = rawShots.length;
            const avgCs = clubSpeedSum / n;
            const avgBs = speedSum / n;
            const recImpact = impactPts.slice(-50);

            currentProfile.club_summary[clb] = {
              count: existing.count ?? n,
              carry_yds: existing.carry_yds ?? (carrySum / n),
              total_yds: existing.total_yds ?? (totalSum / n),
              ball_speed_mph: existing.ball_speed_mph ?? avgBs,
              club_speed_mph: existing.club_speed_mph ?? avgCs,
              smash: existing.smash ?? (avgCs > 0 ? avgBs / avgCs : 0),
              spin_rpm: existing.spin_rpm ?? Math.round(spinSum / n),
              avg_offline_yds: existing.avg_offline_yds ?? existing.offline_yds ?? (offlineSum / n),
              avg_face_angle: existing.avg_face_angle ?? (faceCount > 0 ? faceSum / faceCount : 0),
              has_face_angle: existing.has_face_angle ?? (faceCount > 0),
              face_angle_count: existing.face_angle_count ?? faceCount,
              avg_club_path: existing.avg_club_path ?? (pathCount > 0 ? pathSum / pathCount : 0),
              has_club_path: existing.has_club_path ?? (pathCount > 0),
              club_path_count: existing.club_path_count ?? pathCount,
              impact_points: existing.impact_points ?? recImpact,
              has_impact_data: existing.has_impact_data ?? (recImpact.length > 0)
            };
          }
        }
      }
    } catch (e) {
      console.warn("[Portal] Could not load sync/stats:", e);
    }

    updateUserHeader(user, currentProfile);
    renderOverviewCards(currentProfile);
    renderProfilePreferencesSummary(currentProfile);
    renderClubSummary(currentProfile);
    renderBestCourses(currentProfile);
    loadedTabs.overview = true;

    // Ensure public leaderboard projection has latest lifetime records
    await ensurePublicProfileSynced(user, currentProfile);

    // 2. Read 2: Check incoming link requests (if email is verified)
    if (user.emailVerified) {
      await checkIncomingLinkRequests(user);
    }
  } catch (err) {
    console.error("Error loading user profile:", err);
  }
}

function updateUserHeader(user, profile) {
  const avatarEl = document.getElementById("portal-avatar-initial");
  const nameEl = document.getElementById("portal-user-display-name");
  const emailEl = document.getElementById("portal-user-email");

  const displayName = profile?.display_name || user.displayName || user.email.split("@")[0];
  const initial = (displayName || "?").charAt(0).toUpperCase();
  if (avatarEl) avatarEl.textContent = initial;
  if (nameEl) nameEl.textContent = displayName;
  if (emailEl) emailEl.textContent = user.email;
}

function updateVerificationBanner(user) {
  const banner = document.getElementById("verification-banner");
  if (!banner) return;
  if (!user.emailVerified) {
    banner.classList.add("active");
  } else {
    banner.classList.remove("active");
  }
}

// ─── LINK REQUESTS & APPROVALS (REQUIREMENT 3) ───
async function checkIncomingLinkRequests(user) {
  const banner = document.getElementById("approvals-banner");
  const container = document.getElementById("approvals-list");
  if (!banner || !container) return;

  try {
    const emailLower = user.email.toLowerCase();
    const q = query(
      collection(db, "link_requests"),
      where("target_email_lower", "==", emailLower)
    );
    const snap = await getDocs(q);
    const pendingRequests = [];

    snap.forEach((d) => {
      const data = d.data();
      if (data.status === "pending") {
        pendingRequests.push({ id: d.id, ...data });
      }
    });

    if (pendingRequests.length === 0) {
      banner.classList.remove("active");
      container.innerHTML = "";
      return;
    }

    banner.classList.add("active");
    container.innerHTML = "";

    pendingRequests.forEach((req) => {
      const card = document.createElement("div");
      card.className = "approval-card";
      const requesterName = escapeHtml(req.requester_name || "A Golfer");
      const requesterEmail = escapeHtml(req.requester_email || "");

      card.innerHTML = `
        <div class="approval-meta">
          <strong>${requesterName}</strong> (${requesterEmail}) wants to sync your player stats on their simulator.
        </div>
        <div class="approval-btns">
          <button class="btn-approve" data-id="${req.id}">Approve Access</button>
          <button class="btn-deny" data-id="${req.id}">Deny</button>
        </div>
      `;

      card.querySelector(".btn-approve").addEventListener("click", () => approveLinkRequest(user, req));
      card.querySelector(".btn-deny").addEventListener("click", () => denyLinkRequest(user, req));
      container.appendChild(card);
    });
  } catch (err) {
    console.warn("Could not check incoming link requests:", err);
  }
}

async function approveLinkRequest(user, req) {
  if (!user.emailVerified) {
    alert("Please verify your email address before approving account link requests.");
    return;
  }

  try {
    const batch = writeBatch(db);
    const now = Math.floor(Date.now() / 1000);
    const displayName = user.displayName || user.email.split("@")[0];

    // Ensure profiles/{uid} exists
    batch.set(doc(db, "profiles", user.uid), {
      schema_version: 1,
      owner_uid: user.uid,
      display_name: displayName,
      updated_at: now
    }, { merge: true });

    // Add delegate
    batch.set(doc(db, "profiles", user.uid, "delegates", req.requester_uid), {
      delegate_uid: req.requester_uid,
      delegate_name: req.requester_name || "",
      delegate_email: req.requester_email || "",
      approved_at: now,
      request_id: req.id
    });

    // Update link request status
    batch.update(doc(db, "link_requests", req.id), {
      status: "approved",
      target_uid: user.uid,
      target_display_name: displayName,
      updated_at: now
    });

    await batch.commit();
    alert(`Access approved for ${req.requester_name || req.requester_email}! They can now select your profile on their simulator.`);
    await checkIncomingLinkRequests(user);
    if (loadedTabs.settings) {
      loadSharedAccessAndSettings(user);
    }
  } catch (err) {
    console.error("Approve link request failed:", err);
    const pauseMsg = await handleWriteError(err);
    alert(pauseMsg || ("Could not approve link request: " + err.message));
  }
}

async function denyLinkRequest(user, req) {
  if (!confirm(`Deny access request from ${req.requester_name || req.requester_email}?`)) {
    return;
  }

  try {
    const now = Math.floor(Date.now() / 1000);
    await updateDoc(doc(db, "link_requests", req.id), {
      status: "denied",
      target_uid: user.uid,
      updated_at: now
    });
    alert("Access request denied.");
    await checkIncomingLinkRequests(user);
  } catch (err) {
    console.error("Deny link request failed:", err);
    const pauseMsg = await handleWriteError(err);
    alert(pauseMsg || ("Could not deny link request: " + err.message));
  }
}

// ─── TAB 1: OVERVIEW & CLUBS ───
function renderOverviewCards(profile) {
  const lt = profile?.lifetime || {};

  // Matches
  const matchesEl = document.getElementById("stat-matches-played") || document.getElementById("stat-matches");
  if (matchesEl) matchesEl.textContent = lt.matches_played ?? 0;

  // Record W-L-T
  const recordEl = document.getElementById("stat-record");
  if (recordEl) {
    const wins = lt.wins ?? 0;
    const losses = lt.losses ?? 0;
    const ties = lt.ties ?? 0;
    recordEl.textContent = `${wins}W - ${losses}L - ${ties}T`;
  }

  // Scoring Avg to Par
  const avgParEl = document.getElementById("stat-avg-to-par") || document.getElementById("stat-avg-score");
  if (avgParEl) {
    if (lt.par_diff_matches && lt.par_diff_matches > 0) {
      const avg = lt.par_diff_sum / lt.par_diff_matches;
      avgParEl.textContent = `${avg > 0 ? "+" : ""}${avg.toFixed(1)}`;
    } else {
      avgParEl.textContent = "–";
    }
  }

  // Best 18H Score
  const best18El = document.getElementById("stat-best-18");
  if (best18El) {
    if (lt.best_to_par_18 != null) {
      const parVal = lt.best_to_par_18;
      const parStr = parVal === 0 ? "E" : parVal > 0 ? `+${parVal}` : `${parVal}`;
      best18El.textContent = lt.best_gross_18 != null ? `${parStr} (${lt.best_gross_18})` : parStr;
    } else {
      best18El.textContent = "–";
    }
  }

  // Longest Drive
  const driveEl = document.getElementById("stat-longest-drive");
  if (driveEl) {
    const dr = lt.longest_drive_yds ?? profile?.records?.longest_drive ?? profile?.records?.longest_drive_yds;
    driveEl.textContent = (dr && Number(dr) > 0) ? `${Number(dr).toFixed(1)} yds` : "–";
  }

  // Longest Putt
  const puttEl = document.getElementById("stat-longest-putt");
  if (puttEl) {
    const pt = lt.longest_putt_ft ?? profile?.records?.longest_putt ?? profile?.records?.longest_putt_ft;
    puttEl.textContent = (pt && Number(pt) > 0) ? `${Number(pt).toFixed(1)} ft` : "–";
  }

  // Achievements
  const achEl = document.getElementById("stat-achievements-count");
  if (achEl) {
    achEl.textContent = lt.achievements_count ?? 0;
  }
}

function formatSkillLevel(lvl) {
  switch (lvl) {
    case "beginner": return "Beginner (20+ Hcp)";
    case "mid_handicap": return "Mid Handicap (10-19)";
    case "low_handicap": return "Low Handicap (1-9)";
    case "scratch": return "Scratch / Pro (0 or Better)";
    default: return "Mid Handicap (10-19)";
  }
}

function formatBallGraphic(bg) {
  switch (bg) {
    case "single_line": return "Single Line";
    case "triple_track": return "Triple Track";
    case "visor": return "Visor Stripe";
    case "soccer_ball": return "Hex Soccer";
    case "truvis": return "Truvis High Contrast";
    default: return "Single Line";
  }
}

function renderProfilePreferencesSummary(profile) {
  const container = document.getElementById("profile-preferences-summary");
  if (!container) return;

  const tee = profile?.preferred_tee || "Blue";
  const skill = formatSkillLevel(profile?.skill_level);
  const dexterity = (profile?.handedness === 1) ? "Left-Handed" : "Right-Handed";
  const ball = formatBallGraphic(profile?.ball_graphic);

  container.innerHTML = `
    <div class="pref-badge">
      <span class="pref-icon">⛳</span>
      <div>
        <div class="pref-label">Preferred Tee</div>
        <div class="pref-val">${escapeHtml(tee)}</div>
      </div>
    </div>
    <div class="pref-badge">
      <span class="pref-icon">🎯</span>
      <div>
        <div class="pref-label">Skill Level</div>
        <div class="pref-val">${escapeHtml(skill)}</div>
      </div>
    </div>
    <div class="pref-badge">
      <span class="pref-icon">🏌️</span>
      <div>
        <div class="pref-label">Dexterity</div>
        <div class="pref-val">${escapeHtml(dexterity)}</div>
      </div>
    </div>
    <div class="pref-badge">
      <span class="pref-icon">⚪</span>
      <div>
        <div class="pref-label">Ball Graphic</div>
        <div class="pref-val">${escapeHtml(ball)}</div>
      </div>
    </div>
  `;
}

// ─── CLUB DELIVERY VISUALS & IMAGES ───
const CLUB_IMAGES = {
  driver_top: null,
  iron_top: null,
  driver_face: null,
  iron_face: null
};

function preloadClubImages() {
  const sources = {
    driver_top: "images/clubs/driver_top.png",
    iron_top: "images/clubs/iron_top.png",
    driver_face: "images/clubs/driver_face.png",
    iron_face: "images/clubs/iron_face.png"
  };
  for (const [k, src] of Object.entries(sources)) {
    const img = new Image();
    img.src = src;
    img.onload = () => {
      CLUB_IMAGES[k] = img;
    };
  }
}
preloadClubImages();

function classifyClubCategory(clubName) {
  const lower = String(clubName || "").toLowerCase();
  if (lower.startsWith("dr") || lower.includes("driver")) return "driver";
  if (lower.includes("wood") || lower.endsWith("w") || lower.includes("hybrid") || lower.endsWith("h")) return "wood";
  return "iron";
}

function drawPlaceholder(ctx, w, h) {
  ctx.fillStyle = "rgba(255, 255, 255, 0.35)";
  ctx.font = "28px sans-serif";
  ctx.textAlign = "center";
  ctx.fillText("ℹ️", w * 0.5, h * 0.45);

  ctx.fillStyle = "rgba(140, 175, 205, 0.75)";
  ctx.font = "11px sans-serif";
  ctx.fillText("Data not available for this launch monitor", w * 0.5, h * 0.62);
}

function drawBadge(ctx, w, h, text, strokeColor) {
  const badgeW = Math.min(w - 20, 130);
  const badgeH = 22;
  const badgeX = (w - badgeW) * 0.5;
  const badgeY = h - 26;

  ctx.fillStyle = "rgba(10, 18, 30, 0.9)";
  ctx.strokeStyle = strokeColor;
  ctx.lineWidth = 1;

  ctx.beginPath();
  ctx.roundRect(badgeX, badgeY, badgeW, badgeH, 4);
  ctx.fill();
  ctx.stroke();

  ctx.fillStyle = strokeColor;
  ctx.font = "bold 10px sans-serif";
  ctx.textAlign = "center";
  ctx.fillText(text, w * 0.5, badgeY + 15);
}

function drawHeatBloom(ctx, x, y, radius, color) {
  ctx.beginPath();
  ctx.arc(x, y, radius, 0, Math.PI * 2);
  ctx.fillStyle = color;
  ctx.fill();
}

function drawFaceAngleCanvas(canvas, faceAngle, hasData, clubCategory, isLefty, isAverage) {
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  if (!hasData) {
    drawPlaceholder(ctx, w, h);
    return;
  }

  const center = { x: w * 0.5, y: h * 0.43 };

  // 1. Concentric radar circles
  ctx.strokeStyle = "rgba(46, 72, 97, 0.35)";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.arc(center.x, center.y, 44, 0, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(center.x, center.y, 25, 0, Math.PI * 2);
  ctx.stroke();

  // 2. Target line
  ctx.save();
  ctx.setLineDash([4, 3]);
  ctx.strokeStyle = "rgba(128, 179, 230, 0.45)";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(center.x, h - 28);
  ctx.lineTo(center.x, 18);
  ctx.stroke();
  ctx.restore();

  // Target arrowhead
  ctx.strokeStyle = "rgba(153, 217, 255, 0.85)";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(center.x - 5, 22);
  ctx.lineTo(center.x, 14);
  ctx.lineTo(center.x + 5, 22);
  ctx.stroke();

  ctx.fillStyle = "rgba(153, 204, 242, 0.75)";
  ctx.font = "bold 9px sans-serif";
  ctx.textAlign = "center";
  ctx.fillText("TARGET", center.x, 11);

  // 3. Square reference line
  const refExtent = Math.min(w * 0.46, 80);
  ctx.strokeStyle = "rgba(255, 153, 38, 0.95)";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(center.x - refExtent, center.y);
  ctx.lineTo(center.x + refExtent, center.y);
  ctx.stroke();

  ctx.fillStyle = "rgba(255, 179, 64, 0.9)";
  ctx.font = "bold 8px sans-serif";
  if (!isLefty) {
    ctx.textAlign = "right";
    ctx.fillText("0° SQ", center.x + refExtent - 4, center.y - 4);
  } else {
    ctx.textAlign = "left";
    ctx.fillText("0° SQ", center.x - refExtent + 4, center.y - 4);
  }

  // 4. Rotating Clubhead
  const isWood = (clubCategory === "driver" || clubCategory === "wood");
  const img = isWood ? CLUB_IMAGES.driver_top : CLUB_IMAGES.iron_top;
  const rotDeg = Math.min(Math.max(faceAngle, -25), 25);
  const effRotDeg = isLefty ? -rotDeg : rotDeg;
  const rotRad = (effRotDeg * Math.PI) / 180;

  if (img && img.complete && img.naturalWidth > 0) {
    ctx.save();
    ctx.translate(center.x, center.y);
    ctx.rotate(rotRad);
    const sc = Math.min(Math.max(w / 1100, 0.08), 0.13) * 1.45;
    ctx.scale(isLefty ? -sc : sc, sc);
    ctx.drawImage(img, -512, -512);
    ctx.restore();
  }

  // 5. Face line & angle arc
  const absAng = Math.abs(faceAngle);
  if (absAng >= 0.2) {
    const dirX = Math.cos(rotRad);
    const dirY = Math.sin(rotRad);
    ctx.strokeStyle = "rgba(217, 115, 250, 0.95)";
    ctx.lineWidth = 2.2;
    ctx.beginPath();
    ctx.moveTo(center.x - dirX * refExtent, center.y - dirY * refExtent);
    ctx.lineTo(center.x + dirX * refExtent, center.y + dirY * refExtent);
    ctx.stroke();

    const arcR = Math.min(refExtent * 0.65, 44);
    ctx.beginPath();
    if (!isLefty) {
      const startAng = rotRad >= 0 ? 0 : rotRad;
      const endAng = rotRad >= 0 ? rotRad : 0;
      ctx.arc(center.x, center.y, arcR, startAng, endAng);
    } else {
      const startAng = rotRad <= 0 ? Math.PI : (Math.PI + rotRad);
      const endAng = rotRad <= 0 ? (Math.PI + rotRad) : Math.PI;
      ctx.arc(center.x, center.y, arcR, startAng, endAng);
    }
    ctx.stroke();
  }

  // 6. Golf Ball
  const ballPos = { x: center.x, y: center.y - 12 };
  const ballR = 7;
  ctx.beginPath();
  ctx.arc(ballPos.x, ballPos.y, ballR, 0, Math.PI * 2);
  ctx.fillStyle = "#edf2f7";
  ctx.fill();
  ctx.strokeStyle = "rgba(150, 165, 180, 0.8)";
  ctx.lineWidth = 1.2;
  ctx.stroke();

  // Highlight
  ctx.beginPath();
  ctx.arc(ballPos.x - 2, ballPos.y - 2, 1.8, 0, Math.PI * 2);
  ctx.fillStyle = "rgba(255, 255, 255, 0.9)";
  ctx.fill();

  // 7. Badge
  const col = absAng <= 1.2 ? "#59f299" : (absAng <= 3.5 ? "#ffbf4d" : "#ff6161");
  let statusStr = absAng < 0.2 ? "SQUARE (0.0°)" : (faceAngle > 0 ? `${faceAngle.toFixed(1)}° OPEN` : `${absAng.toFixed(1)}° CLOSED`);
  if (isAverage) statusStr = "Avg " + statusStr;
  drawBadge(ctx, w, h, statusStr, col);
}

function drawImpactLocationCanvas(canvas, clubName, hMm, vMm, impactPoints, hasData, clubCategory) {
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  if (!hasData) {
    drawPlaceholder(ctx, w, h);
    return;
  }

  const isWood = (clubCategory === "driver" || clubCategory === "wood");
  const img = isWood ? CLUB_IMAGES.driver_face : CLUB_IMAGES.iron_face;

  const texW = Math.min(w * 0.96, (h - 26) * (1200 / 896));
  const texH = texW * (896 / 1200);
  const texPos = { x: (w - texW) * 0.5, y: (h - 20 - texH) * 0.5 + 8 };

  if (img && img.complete && img.naturalWidth > 0) {
    ctx.drawImage(img, texPos.x, texPos.y, texW, texH);
  }

  let sweetSpot, mmScale;
  if (isWood) {
    sweetSpot = { x: texPos.x + texW * 0.492, y: texPos.y + texH * 0.478 };
    mmScale = (texW * 0.38) / 54;
  } else {
    sweetSpot = { x: texPos.x + texW * 0.400, y: texPos.y + texH * 0.670 };
    mmScale = (texW * 0.36) / 48;
  }

  // Crosshairs
  ctx.save();
  ctx.setLineDash([3, 2]);
  ctx.strokeStyle = "rgba(89, 191, 255, 0.45)";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(sweetSpot.x - 16, sweetSpot.y);
  ctx.lineTo(sweetSpot.x + 16, sweetSpot.y);
  ctx.moveTo(sweetSpot.x, sweetSpot.y - 16);
  ctx.lineTo(sweetSpot.x, sweetSpot.y + 16);
  ctx.stroke();
  ctx.restore();

  ctx.beginPath();
  ctx.arc(sweetSpot.x, sweetSpot.y, 1.8, 0, Math.PI * 2);
  ctx.fillStyle = "rgba(102, 217, 255, 0.85)";
  ctx.fill();

  // Heatmap or single strike
  if (impactPoints && impactPoints.length > 0) {
    impactPoints.forEach((pt) => {
      const ptX = sweetSpot.x - Number(pt.h || 0) * mmScale;
      const ptY = sweetSpot.y - Number(pt.v || 0) * mmScale;

      drawHeatBloom(ctx, ptX, ptY, 14, "rgba(26, 115, 230, 0.14)");
      drawHeatBloom(ctx, ptX, ptY, 8.5, "rgba(77, 217, 77, 0.24)");
      drawHeatBloom(ctx, ptX, ptY, 4.5, "rgba(255, 89, 26, 0.50)");
      drawHeatBloom(ctx, ptX, ptY, 2.2, "rgba(255, 230, 77, 0.80)");
    });

    drawBadge(ctx, w, h, `${impactPoints.length} SHOTS HEATMAP`, "#ffd966");
  } else {
    const ptX = sweetSpot.x - hMm * mmScale;
    const ptY = sweetSpot.y - vMm * mmScale;

    drawHeatBloom(ctx, ptX, ptY, 16, "rgba(26, 140, 255, 0.22)");
    drawHeatBloom(ctx, ptX, ptY, 10.5, "rgba(64, 217, 89, 0.42)");
    drawHeatBloom(ctx, ptX, ptY, 6, "rgba(255, 191, 38, 0.75)");
    drawHeatBloom(ctx, ptX, ptY, 3.2, "rgba(255, 64, 26, 0.95)");
    drawHeatBloom(ctx, ptX, ptY, 1.4, "rgba(255, 255, 255, 0.95)");

    const dist = Math.hypot(ptX - sweetSpot.x, ptY - sweetSpot.y);
    const col = dist < (6 * mmScale) ? "#59f299" : (dist < (14 * mmScale) ? "#ffbf4d" : "#ff6161");
    let desc = "SWEET SPOT (CENTER)";
    if (Math.abs(hMm) >= 3 || Math.abs(vMm) >= 3) {
      const hStr = Math.abs(hMm) >= 3 ? `${Math.abs(hMm).toFixed(0)}mm ${hMm > 0 ? "TOE" : "HEEL"}` : "";
      const vStr = Math.abs(vMm) >= 3 ? `${Math.abs(vMm).toFixed(0)}mm ${vMm > 0 ? "HIGH" : "LOW"}` : "";
      desc = [hStr, vStr].filter(Boolean).join(" • ");
    }
    drawBadge(ctx, w, h, desc, col);
  }
}

function drawClubPathCanvas(canvas, clubPath, hasData, clubCategory, isLefty, isAverage) {
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  if (!hasData) {
    drawPlaceholder(ctx, w, h);
    return;
  }

  const center = { x: w * 0.5, y: h * 0.50 };

  // 1. Radar circles
  ctx.strokeStyle = "rgba(46, 72, 97, 0.35)";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.arc(center.x, center.y, 44, 0, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(center.x, center.y, 25, 0, Math.PI * 2);
  ctx.stroke();

  // 2. Target line
  ctx.save();
  ctx.setLineDash([4, 3]);
  ctx.strokeStyle = "rgba(128, 179, 230, 0.45)";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(center.x, h - 18);
  ctx.lineTo(center.x, 18);
  ctx.stroke();
  ctx.restore();

  // Arrowhead
  ctx.strokeStyle = "rgba(153, 217, 255, 0.85)";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(center.x - 5, 22);
  ctx.lineTo(center.x, 14);
  ctx.lineTo(center.x + 5, 22);
  ctx.stroke();

  ctx.fillStyle = "rgba(153, 204, 242, 0.75)";
  ctx.font = "bold 9px sans-serif";
  ctx.textAlign = "center";
  ctx.fillText("TARGET", center.x, 11);

  // 3. Realistic clubhead at address
  const isWood = (clubCategory === "driver" || clubCategory === "wood");
  const img = isWood ? CLUB_IMAGES.driver_top : CLUB_IMAGES.iron_top;

  if (img && img.complete && img.naturalWidth > 0) {
    ctx.save();
    ctx.translate(center.x, center.y + 10);
    const sc = Math.min(Math.max(w / 1150, 0.07), 0.12) * 1.45;
    ctx.scale(isLefty ? -sc : sc, sc);
    ctx.drawImage(img, -512, -512);
    ctx.restore();
  }

  // 4. Ball at impact
  const ballR = 7;
  ctx.beginPath();
  ctx.arc(center.x, center.y, ballR, 0, Math.PI * 2);
  ctx.fillStyle = "#edf2f7";
  ctx.fill();
  ctx.strokeStyle = "rgba(150, 165, 180, 0.8)";
  ctx.lineWidth = 1.2;
  ctx.stroke();

  // 5. Dynamic Path Vector Arrow
  const effPath = isLefty ? -clubPath : clubPath;
  const pathRad = (Math.min(Math.max(effPath, -25), 25) * Math.PI) / 180;
  const dirForward = { x: Math.sin(pathRad), y: -Math.cos(pathRad) };

  const absPath = Math.abs(clubPath);
  const pathCol = absPath <= 1.5 ? "#59f299" : (absPath <= 4.0 ? "#ffbf4d" : "#ff5959");

  const arrowLen = 50;
  const pStart = { x: center.x - dirForward.x * (arrowLen * 0.8), y: center.y - dirForward.y * (arrowLen * 0.8) };
  const pEnd = { x: center.x + dirForward.x * (arrowLen * 0.88), y: center.y + dirForward.y * (arrowLen * 0.88) };

  ctx.strokeStyle = pathCol;
  ctx.lineWidth = 3.5;
  ctx.beginPath();
  ctx.moveTo(pStart.x, pStart.y);
  ctx.lineTo(pEnd.x, pEnd.y);
  ctx.stroke();

  // Arrowhead polygon
  const normalPath = { x: -dirForward.y, y: dirForward.x };
  const headLen = 12;
  const headW = 7;
  const tip = pEnd;
  const leftWing = { x: tip.x - dirForward.x * headLen + normalPath.x * headW, y: tip.y - dirForward.y * headLen + normalPath.y * headW };
  const rightWing = { x: tip.x - dirForward.x * headLen - normalPath.x * headW, y: tip.y - dirForward.y * headLen - normalPath.y * headW };

  ctx.fillStyle = pathCol;
  ctx.beginPath();
  ctx.moveTo(tip.x, tip.y);
  ctx.lineTo(leftWing.x, leftWing.y);
  ctx.lineTo(rightWing.x, rightWing.y);
  ctx.closePath();
  ctx.fill();

  // Deviation arc
  if (absPath >= 0.4) {
    const arcR = 34;
    const baseAng = -Math.PI * 0.5;
    const targetAng = baseAng + pathRad;
    ctx.strokeStyle = pathCol;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(center.x, center.y, arcR, Math.min(baseAng, targetAng), Math.max(baseAng, targetAng));
    ctx.stroke();
  }

  // Badge
  let statusStr = absPath < 0.2 ? "STRAIGHT (0.0°)" : (clubPath > 0 ? `${clubPath.toFixed(1)}° IN-TO-OUT` : `${absPath.toFixed(1)}° OUT-TO-IN`);
  if (isAverage) statusStr = "Avg " + statusStr;
  drawBadge(ctx, w, h, statusStr, pathCol);
}

function renderClubSummary(profile) {
  const container = document.getElementById("club-summary-container");
  if (!container) return;

  const summary = profile?.club_summary || {};
  const clubKeys = Object.keys(summary);

  if (clubKeys.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <span class="empty-icon">🏌️</span>
        <p>No club shot data recorded yet. Take swings in the simulator to see your club averages and delivery visuals here!</p>
      </div>
    `;
    return;
  }

  const seenClubs = new Set();
  const sortedClubs = [];
  STANDARD_BAG_ORDER.forEach((c) => {
    const matchedKey = clubKeys.find(k => k.toLowerCase() === c.toLowerCase());
    if (matchedKey && !seenClubs.has(matchedKey.toLowerCase())) {
      seenClubs.add(matchedKey.toLowerCase());
      sortedClubs.push(matchedKey);
    }
  });
  clubKeys.forEach((c) => {
    if (!seenClubs.has(c.toLowerCase())) {
      seenClubs.add(c.toLowerCase());
      sortedClubs.push(c);
    }
  });

  const isLefty = profile?.handedness === 1;

  let cardsHtml = "";
  sortedClubs.forEach((clubKey) => {
    const s = summary[clubKey] || {};
    const clubName = CLUB_LABELS[clubKey] || CLUB_LABELS[clubKey.toLowerCase()] || CLUB_LABELS[clubKey.toUpperCase()] || clubKey;
    const carry = s.carry_yds != null ? Number(s.carry_yds).toFixed(1) : "–";
    const total = s.total_yds != null ? Number(s.total_yds).toFixed(1) : "–";
    const bSpeed = s.ball_speed_mph != null ? Number(s.ball_speed_mph).toFixed(1) : "–";
    const spin = s.spin_rpm != null ? Math.round(Number(s.spin_rpm)) : "–";
    const offline = s.avg_offline_yds != null ? Number(s.avg_offline_yds).toFixed(1) : (s.offline_yds != null ? Number(s.offline_yds).toFixed(1) : "–");
    const count = s.count ?? 0;
    const hasShots = count > 0;
    const drawerId = `drawer-${clubKey.toLowerCase().replace(/[^a-z0-9]/g, '_')}`;

    cardsHtml += `
      <div class="portal-club-card ${hasShots ? 'has-shots' : ''}" data-club="${escapeHtml(clubKey)}">
        <div class="portal-club-row">
          <!-- Club code & name -->
          <div class="portal-club-col-name">
            <span class="portal-club-code">${escapeHtml(clubKey)}</span>
            <span class="portal-club-fullname">${escapeHtml(clubName)} (${escapeHtml(clubKey)})</span>
          </div>

          <!-- Shot Count -->
          <div class="portal-club-col-count">
            <span class="portal-count-val">${count} shots</span>
            <span class="portal-count-sub">Recorded</span>
          </div>

          <!-- Metrics -->
          <div class="portal-club-col-stats">
            <div class="portal-metric-item">
              <span class="portal-metric-val val-gold">${total} yds</span>
              <span class="portal-metric-lbl">Avg Total</span>
            </div>
            <div class="portal-metric-item">
              <span class="portal-metric-val">${carry} yds</span>
              <span class="portal-metric-lbl">Avg Carry</span>
            </div>
            <div class="portal-metric-item">
              <span class="portal-metric-val">${bSpeed} mph</span>
              <span class="portal-metric-lbl">Avg Speed</span>
            </div>
            <div class="portal-metric-item">
              <span class="portal-metric-val">${spin} rpm</span>
              <span class="portal-metric-lbl">Avg Spin</span>
            </div>
            <div class="portal-metric-item">
              <span class="portal-metric-val">${offline} yds</span>
              <span class="portal-metric-lbl">Avg Offline</span>
            </div>
          </div>

          <!-- Buttons -->
          <div class="portal-club-col-actions">
            <button class="btn-toggle-visuals" data-drawer="${drawerId}" ${!hasShots ? 'disabled' : ''}>
              ▼ Visuals
            </button>
            <button class="btn-clear-club-row" data-club="${escapeHtml(clubKey)}" data-club-name="${escapeHtml(clubName)}" data-count="${count}" ${!hasShots ? 'disabled' : ''} title="Clear shot data for ${escapeHtml(clubName)}">
              🗑
            </button>
          </div>
        </div>

        <!-- Drawer -->
        <div class="portal-club-drawer" id="${drawerId}" style="display: none;">
          <div class="portal-drawer-inner">
            <div class="portal-drawer-header">
              🏌 CLUB DELIVERY AVERAGES & STRIKE TENDENCIES
            </div>
            <div class="portal-visuals-grid">
              <!-- Visual Card 1: Face Angle -->
              <div class="portal-visual-panel">
                <div class="portal-visual-header">CLUB FACE ANGLE</div>
                <div class="portal-canvas-container">
                  <canvas id="canvas-face-${drawerId}" width="280" height="200"></canvas>
                </div>
              </div>

              <!-- Visual Card 2: Impact Location -->
              <div class="portal-visual-panel">
                <div class="portal-visual-header flex-header">
                  <span class="club-subtag">${escapeHtml(clubName.toUpperCase())}</span>
                  <span class="visual-title">IMPACT: ${escapeHtml(clubName.toUpperCase())}</span>
                </div>
                <div class="portal-canvas-container">
                  <canvas id="canvas-impact-${drawerId}" width="280" height="200"></canvas>
                </div>
              </div>

              <!-- Visual Card 3: Club Path -->
              <div class="portal-visual-panel">
                <div class="portal-visual-header">CLUB PATH</div>
                <div class="portal-canvas-container">
                  <canvas id="canvas-path-${drawerId}" width="280" height="200"></canvas>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
  });

  container.innerHTML = `<div class="portal-clubs-list">${cardsHtml}</div>`;

  // Hook up drawer toggles
  container.querySelectorAll(".btn-toggle-visuals").forEach((btn) => {
    btn.addEventListener("click", () => {
      const drawerId = btn.getAttribute("data-drawer");
      const drawer = document.getElementById(drawerId);
      if (!drawer) return;

      const isOpening = drawer.style.display === "none";
      drawer.style.display = isOpening ? "block" : "none";
      btn.textContent = isOpening ? "▲ Hide" : "▼ Visuals";

      if (isOpening) {
        const card = btn.closest(".portal-club-card");
        const clubKey = card.getAttribute("data-club");
        const s = summary[clubKey] || {};
        const clubCategory = classifyClubCategory(clubKey);
        const clubName = CLUB_LABELS[clubKey] || clubKey;

        const faceCanvas = document.getElementById(`canvas-face-${drawerId}`);
        const impactCanvas = document.getElementById(`canvas-impact-${drawerId}`);
        const pathCanvas = document.getElementById(`canvas-path-${drawerId}`);

        const renderVisuals = () => {
          drawFaceAngleCanvas(
            faceCanvas,
            Number(s.avg_face_angle ?? 0),
            Boolean(s.has_face_angle ?? (s.face_angle_count > 0)),
            clubCategory,
            isLefty,
            true
          );

          drawImpactLocationCanvas(
            impactCanvas,
            clubName,
            0,
            0,
            s.impact_points || [],
            Boolean(s.has_impact_data ?? (s.impact_points && s.impact_points.length > 0)),
            clubCategory
          );

          drawClubPathCanvas(
            pathCanvas,
            Number(s.avg_club_path ?? 0),
            Boolean(s.has_club_path ?? (s.club_path_count > 0)),
            clubCategory,
            isLefty,
            true
          );
        };

        renderVisuals();
        // If images load slightly later, trigger redraw once cached
        setTimeout(renderVisuals, 150);
      }
    });
  });

  // Hook up clear buttons
  container.querySelectorAll(".btn-clear-club-row").forEach((btn) => {
    btn.addEventListener("click", () => {
      const code = btn.getAttribute("data-club");
      const name = btn.getAttribute("data-club-name");
      const cnt = btn.getAttribute("data-count");
      showConfirmModal({
        title: "Clear Club Shot Data",
        message: `Are you sure you want to clear shot data for ${name} (${code})?\n\nThis will reset all ${cnt} recorded shots for this club and cannot be undone.`,
        confirmText: "Clear Club Data",
        onConfirm: () => clearClubShotData(code)
      });
    });
  });
}

// ─── PLAYER PROFILE & STATS MANAGEMENT ───
async function clearClubShotData(clubKey) {
  if (!currentUser) return;
  try {
    const nowSec = Math.floor(Date.now() / 1000);

    // 1. Update sync/stats
    const statsRef = doc(db, "profiles", currentUser.uid, "sync", "stats");
    const statsSnap = await getDoc(statsRef);
    const statsData = statsSnap.exists() ? statsSnap.data() : { schema_version: 1, clubs: {}, tombstones: {}, records: {} };

    const clubs = { ...(statsData.clubs || {}) };
    for (const k of Object.keys(clubs)) {
      if (k.toLowerCase() === clubKey.toLowerCase()) {
        delete clubs[k];
      }
    }

    const tombstones = { ...(statsData.tombstones || {}) };
    const clearedClubs = { ...(tombstones.cleared_clubs || {}) };
    clearedClubs[clubKey] = nowSec;
    const stdKey = STANDARD_BAG_ORDER.find((sc) => sc.toLowerCase() === clubKey.toLowerCase());
    if (stdKey) {
      clearedClubs[stdKey] = nowSec;
    }
    tombstones.cleared_clubs = clearedClubs;

    const records = { ...(statsData.records || {}) };
    if (clubKey.toLowerCase() === "dr" || clubKey.toLowerCase() === "driver") {
      delete records.longest_drive;
      delete records.longest_drive_yds;
    } else if (clubKey.toLowerCase() === "pt" || clubKey.toLowerCase() === "putter") {
      delete records.longest_putt_ft;
    }

    const statsRev = (statsData.rev || 0) + 1;
    await setDoc(statsRef, {
      ...statsData,
      schema_version: 1,
      clubs,
      records,
      tombstones,
      rev: statsRev,
      updated_at: nowSec
    });

    // 2. Update profiles/{uid}
    const profRef = doc(db, "profiles", currentUser.uid);
    const profSnap = await getDoc(profRef);
    if (profSnap.exists()) {
      const profData = profSnap.data();
      const clubSummary = { ...(profData.club_summary || {}) };
      for (const k of Object.keys(clubSummary)) {
        if (k.toLowerCase() === clubKey.toLowerCase()) {
          delete clubSummary[k];
        }
      }
      const profRev = (profData.rev || 0) + 1;
      await updateDoc(profRef, {
        club_summary: clubSummary,
        rev: profRev,
        updated_at: nowSec,
        updated_by_uid: currentUser.uid
      });
      currentProfile = { ...profData, club_summary: clubSummary, rev: profRev };
    }

    renderClubSummary(currentProfile);
    showToast(`✓ Shot data for ${CLUB_LABELS[clubKey] || clubKey} cleared.`);
  } catch (err) {
    console.error("Failed to clear club data:", err);
    const pauseMsg = await handleWriteError(err);
    showToast(pauseMsg || ("Failed to clear club data: " + (err.message || err)));
  }
}

async function clearAllBallHistory() {
  if (!currentUser) return;
  try {
    const nowSec = Math.floor(Date.now() / 1000);

    // 1. Update sync/stats
    const statsRef = doc(db, "profiles", currentUser.uid, "sync", "stats");
    const statsSnap = await getDoc(statsRef);
    const statsData = statsSnap.exists() ? statsSnap.data() : { schema_version: 1 };

    const tombstones = { ...(statsData.tombstones || {}) };
    tombstones.cleared_all_at = nowSec;

    const statsRev = (statsData.rev || 0) + 1;
    await setDoc(statsRef, {
      ...statsData,
      schema_version: 1,
      clubs: {},
      records: {},
      tombstones,
      rev: statsRev,
      updated_at: nowSec
    });

    // 2. Update profiles/{uid}
    const profRef = doc(db, "profiles", currentUser.uid);
    const profSnap = await getDoc(profRef);
    if (profSnap.exists()) {
      const profData = profSnap.data();
      const lifetime = { ...(profData.lifetime || {}) };
      lifetime.longest_drive_yds = 0;
      const profRev = (profData.rev || 0) + 1;
      await updateDoc(profRef, {
        club_summary: {},
        lifetime,
        rev: profRev,
        updated_at: nowSec,
        updated_by_uid: currentUser.uid
      });
      currentProfile = { ...profData, club_summary: {}, lifetime, rev: profRev };
    }

    renderOverviewCards(currentProfile);
    renderClubSummary(currentProfile);
    showToast("✓ All ball history across all clubs has been cleared.");
  } catch (err) {
    console.error("Failed to clear ball history:", err);
    const pauseMsg = await handleWriteError(err);
    showToast(pauseMsg || ("Failed to clear ball history: " + (err.message || err)));
  }
}

async function clearSwingHistory() {
  if (!currentUser) return;
  try {
    const nowSec = Math.floor(Date.now() / 1000);

    const statsRef = doc(db, "profiles", currentUser.uid, "sync", "stats");
    const statsSnap = await getDoc(statsRef);
    const statsData = statsSnap.exists() ? statsSnap.data() : { schema_version: 1 };

    const tombstones = { ...(statsData.tombstones || {}) };
    tombstones.cleared_swing_issues_at = nowSec;

    const statsRev = (statsData.rev || 0) + 1;
    await setDoc(statsRef, {
      ...statsData,
      schema_version: 1,
      swing_issues: {},
      tombstones,
      rev: statsRev,
      updated_at: nowSec
    });

    const swingContainer = document.getElementById("swing-analysis-container");
    if (swingContainer) {
      swingContainer.innerHTML = `
        <div class="empty-state">
          <span class="empty-icon">📊</span>
          <p>No swing issues logged yet. Enable swing analysis on your launch monitor to track swing tendencies over time!</p>
        </div>
      `;
    }
    showToast("✓ Swing flaw and tendency history has been cleared.");
  } catch (err) {
    console.error("Failed to clear swing history:", err);
    const pauseMsg = await handleWriteError(err);
    showToast(pauseMsg || ("Failed to clear swing history: " + (err.message || err)));
  }
}

async function saveProfilePreferences(updates) {
  if (!currentUser) return;
  try {
    const nowSec = Math.floor(Date.now() / 1000);
    const profRef = doc(db, "profiles", currentUser.uid);
    const profSnap = await getDoc(profRef);
    const profData = profSnap.exists() ? profSnap.data() : {};
    const profRev = (profData.rev || 0) + 1;

    const finalName = (updates.displayName || profData.display_name || currentUser.displayName || "Golfer").trim();
    const newProf = {
      ...profData,
      schema_version: 1,
      display_name: finalName,
      preferred_tee: updates.preferredTee || profData.preferred_tee || "Blue",
      skill_level: updates.skillLevel || profData.skill_level || "mid_handicap",
      handedness: updates.handedness != null ? updates.handedness : (profData.handedness ?? 0),
      ball_graphic: updates.ballGraphic || profData.ball_graphic || "single_line",
      rev: profRev,
      updated_at: nowSec,
      updated_by_uid: currentUser.uid
    };

    await setDoc(profRef, newProf, { merge: true });

    // Update Firebase Auth user displayName if changed
    if (finalName && finalName !== currentUser.displayName) {
      try {
        await updateProfile(currentUser, { displayName: finalName });
      } catch (e) {
        console.warn("Could not update auth displayName:", e);
      }
    }

    // Update users/{uid}
    try {
      await updateDoc(doc(db, "users", currentUser.uid), {
        display_name: finalName,
        updated_at: nowSec
      });
    } catch {}

    // Update public_profiles/{uid} if present
    try {
      const pubSnap = await getDoc(doc(db, "public_profiles", currentUser.uid));
      if (pubSnap.exists()) {
        await updateDoc(doc(db, "public_profiles", currentUser.uid), {
          display_name: finalName,
          updated_at: nowSec
        });
      }
    } catch {}

    currentProfile = newProf;

    updateUserHeader(currentUser, currentProfile);
    renderProfilePreferencesSummary(currentProfile);
    await ensurePublicProfileSynced(currentUser, currentProfile);
    closeEditProfileModal();
    showToast("✓ Profile and preferences updated successfully.");
  } catch (err) {
    console.error("Failed to update profile:", err);
    const pauseMsg = await handleWriteError(err);
    showToast(pauseMsg || ("Failed to update profile: " + (err.message || err)));
  }
}

// ─── MODAL CONTROLLERS & TOAST ───
function showConfirmModal({ title, message, confirmText = "Confirm", onConfirm }) {
  const overlay = document.getElementById("confirm-modal-overlay");
  const titleEl = document.getElementById("confirm-modal-title");
  const descEl = document.getElementById("confirm-modal-message");
  const proceedBtn = document.getElementById("btn-confirm-proceed");

  if (!overlay) return;
  if (titleEl) titleEl.textContent = title;
  if (descEl) descEl.textContent = message;
  if (proceedBtn) proceedBtn.textContent = confirmText;
  activeConfirmCallback = onConfirm;

  overlay.classList.add("open");
  document.body.style.overflow = "hidden";
}

function closeConfirmModal() {
  const overlay = document.getElementById("confirm-modal-overlay");
  if (overlay) overlay.classList.remove("open");
  document.body.style.overflow = "";
  activeConfirmCallback = null;
}

function openEditProfileModal() {
  const overlay = document.getElementById("edit-profile-modal-overlay");
  if (!overlay) return;

  const nameInput = document.getElementById("input-edit-display-name");
  const teeSelect = document.getElementById("select-edit-preferred-tee");
  const handSelect = document.getElementById("select-edit-handedness");
  const skillSelect = document.getElementById("select-edit-skill-level");
  const ballSelect = document.getElementById("select-edit-ball-graphic");

  const p = currentProfile || {};
  if (nameInput) nameInput.value = p.display_name || currentUser?.displayName || currentUser?.email?.split("@")[0] || "";
  if (teeSelect) teeSelect.value = p.preferred_tee || "Blue";
  if (handSelect) handSelect.value = String(p.handedness ?? 0);
  if (skillSelect) skillSelect.value = p.skill_level || "mid_handicap";
  if (ballSelect) ballSelect.value = p.ball_graphic || "single_line";

  overlay.classList.add("open");
  document.body.style.overflow = "hidden";
}

function closeEditProfileModal() {
  const overlay = document.getElementById("edit-profile-modal-overlay");
  if (overlay) overlay.classList.remove("open");
  document.body.style.overflow = "";
}

function showToast(message) {
  const toast = document.getElementById("portal-toast");
  if (!toast) return;
  toast.textContent = message;
  toast.classList.add("active");
  if (toastTimeout) clearTimeout(toastTimeout);
  toastTimeout = setTimeout(() => {
    toast.classList.remove("active");
  }, 3500);
}

function bindPlayerManagement() {
  // Confirm modal buttons
  document.getElementById("btn-confirm-close")?.addEventListener("click", closeConfirmModal);
  document.getElementById("btn-confirm-cancel")?.addEventListener("click", closeConfirmModal);
  document.getElementById("btn-confirm-proceed")?.addEventListener("click", async () => {
    const btn = document.getElementById("btn-confirm-proceed");
    if (activeConfirmCallback) {
      if (btn) { btn.disabled = true; btn.textContent = "Processing…"; }
      try {
        await activeConfirmCallback();
      } finally {
        if (btn) { btn.disabled = false; }
        closeConfirmModal();
      }
    }
  });

  // Edit profile triggers
  document.getElementById("btn-edit-profile")?.addEventListener("click", openEditProfileModal);
  document.getElementById("portal-top-edit-profile-btn")?.addEventListener("click", openEditProfileModal);
  document.getElementById("btn-edit-profile-close")?.addEventListener("click", closeEditProfileModal);
  document.getElementById("btn-edit-profile-cancel")?.addEventListener("click", closeEditProfileModal);
  document.getElementById("btn-edit-profile-save")?.addEventListener("click", async () => {
    const nameInput = document.getElementById("input-edit-display-name");
    const teeSelect = document.getElementById("select-edit-preferred-tee");
    const handSelect = document.getElementById("select-edit-handedness");
    const skillSelect = document.getElementById("select-edit-skill-level");
    const ballSelect = document.getElementById("select-edit-ball-graphic");

    const updates = {
      displayName: nameInput?.value?.trim() || "",
      preferredTee: teeSelect?.value || "Blue",
      handedness: handSelect ? parseInt(handSelect.value, 10) : 0,
      skillLevel: skillSelect?.value || "mid_handicap",
      ballGraphic: ballSelect?.value || "single_line"
    };

    const saveBtn = document.getElementById("btn-edit-profile-save");
    if (saveBtn) { saveBtn.disabled = true; saveBtn.textContent = "Saving…"; }
    try {
      await saveProfilePreferences(updates);
    } finally {
      if (saveBtn) { saveBtn.disabled = false; saveBtn.textContent = "Save Profile"; }
    }
  });

  // Clear all ball history
  document.getElementById("btn-clear-all-history")?.addEventListener("click", () => {
    showConfirmModal({
      title: "Clear All Ball History",
      message: "Are you sure you want to clear your entire ball history across all clubs? This resets all your club average carries, speed, spin, and personal best records, and cannot be undone.",
      confirmText: "Clear All History",
      onConfirm: clearAllBallHistory
    });
  });

  // Clear swing flaw history
  document.getElementById("btn-clear-swing-history")?.addEventListener("click", () => {
    showConfirmModal({
      title: "Clear Swing Tendencies",
      message: "Are you sure you want to clear your swing tendency history? This resets all recorded swing flaws and improvement recommendations.",
      confirmText: "Clear Swing History",
      onConfirm: clearSwingHistory
    });
  });

  // Close modals on overlay backdrop click
  ["confirm-modal-overlay", "edit-profile-modal-overlay"].forEach((id) => {
    const el = document.getElementById(id);
    if (el) {
      el.addEventListener("click", (e) => {
        if (e.target === el) {
          el.classList.remove("open");
          document.body.style.overflow = "";
        }
      });
    }
  });

  // Close modals on Escape key
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      closeConfirmModal();
      closeEditProfileModal();
    }
  });
}

function renderBestCourses(profile) {
  const container = document.getElementById("best-courses-container");
  if (!container) return;

  const bestCourses = profile?.lifetime?.best_courses || {};
  const courseNames = Object.keys(bestCourses);

  if (courseNames.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <span class="empty-icon">⛳</span>
        <p>No course rounds recorded yet. Play a round in Heckle Golf to record your best courses!</p>
      </div>
    `;
    return;
  }

  let cardsHtml = "";
  courseNames.forEach((name) => {
    const c = bestCourses[name];
    const diff = c.diff != null ? (c.diff === 0 ? "E" : c.diff > 0 ? `+${c.diff}` : `${c.diff}`) : "";
    const strokes = c.strokes != null ? `(${c.strokes} strokes)` : "";
    const holes = c.holes ? `${c.holes} Holes` : "18 Holes";

    cardsHtml += `
      <div class="best-course-item">
        <div>
          <h4>${escapeHtml(name)}</h4>
          <span class="course-meta">${holes}</span>
        </div>
        <div class="best-course-score">
          ${diff} <span style="font-size: 0.85rem; font-weight: normal; color: var(--muted);">${strokes}</span>
        </div>
      </div>
    `;
  });

  container.innerHTML = `<div class="best-courses-grid">${cardsHtml}</div>`;
}

// ─── TAB 2: RECENT MATCHES (LAZY-LOADED) ───
async function loadRecentMatches(user) {
  const container = document.getElementById("recent-matches-container");
  if (!container) return;

  container.innerHTML = `
    <div class="loading-state">
      <div class="spinner"></div>
      <p>Loading recent matches…</p>
    </div>
  `;

  try {
    let snap;
    try {
      const q = query(
        collection(db, "profiles", user.uid, "matches"),
        orderBy("played_at", "desc"),
        limit(10)
      );
      snap = await getDocs(q);
      if (snap.empty) {
        const qFallback = query(
          collection(db, "profiles", user.uid, "matches"),
          limit(10)
        );
        snap = await getDocs(qFallback);
      }
    } catch {
      const qFallback = query(
        collection(db, "profiles", user.uid, "matches"),
        limit(10)
      );
      snap = await getDocs(qFallback);
    }
    const matches = snap.docs.map((d) => ({ id: d.id, ...d.data() }));

    loadedTabs.matches = true;

    if (matches.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <span class="empty-icon">📋</span>
          <p>No match scorecards found yet. Complete a round in Heckle Golf to view your match history!</p>
        </div>
      `;
      return;
    }

    let listHtml = "";
    matches.forEach((m, idx) => {
      const courseName = escapeHtml(m.course_name || "Unknown Course");
      const playedTimestamp = m.played_at || m.created_at;
      const dateStr = playedTimestamp ? new Date(playedTimestamp * 1000).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" }) : "";
      const holesCount = m.holes_count || 18;
      const strokes = m.strokes || "–";
      const toPar = m.to_par != null ? (m.to_par === 0 ? "E" : m.to_par > 0 ? `+${m.to_par}` : `${m.to_par}`) : "";
      const matchType = m.match_type === "multiplayer" ? "Multiplayer" : "Single Player";
      const isFinished = m.is_finished !== false;
      const statusBadge = isFinished
        ? `<span class="match-score-badge" style="background: rgba(34, 197, 94, 0.15); color: #4ade80; border: 1px solid rgba(34, 197, 94, 0.3);">Completed</span>`
        : `<span class="match-score-badge" style="background: rgba(234, 179, 8, 0.15); color: #facc15; border: 1px solid rgba(234, 179, 8, 0.3);">Partial Round</span>`;

      let holesTableHtml = "";
      if (m.holes && Array.isArray(m.holes) && m.holes.length > 0) {
        let holeHeaders = "";
        let parRow = "";
        let scoreRow = "";

        m.holes.forEach((h, hIdx) => {
          const hNum = h.hole_number || (hIdx + 1);
          holeHeaders += `<th style="padding: 0.4rem; text-align: center;">#${hNum}</th>`;
          parRow += `<td style="padding: 0.4rem; text-align: center; color: var(--muted);">${h.par ?? "–"}</td>`;
          scoreRow += `<td style="padding: 0.4rem; text-align: center; font-weight: 700; color: var(--green);">${h.score ?? "–"}</td>`;
        });

        holesTableHtml = `
          <button class="btn-toggle-scorecard" data-idx="${idx}">View Hole-by-Hole Scores ▼</button>
          <div class="scorecard-holes-table" id="scorecard-holes-${idx}">
            <div class="table-responsive">
              <table class="data-table" style="font-size: 0.8rem;">
                <thead><tr><th style="padding: 0.4rem;">Hole</th>${holeHeaders}</tr></thead>
                <tbody>
                  <tr><td style="padding: 0.4rem; font-weight: 600;">Par</td>${parRow}</tr>
                  <tr><td style="padding: 0.4rem; font-weight: 600;">Score</td>${scoreRow}</tr>
                </tbody>
              </table>
            </div>
          </div>
        `;
      }

      listHtml += `
        <div class="match-item">
          <div class="match-header">
            <span class="match-title">${courseName}</span>
            <span class="match-date">${dateStr}</span>
          </div>
          <div class="match-summary-row">
            <span><strong>${holesCount}</strong> Holes</span>
            <span><strong>${strokes}</strong> Total Strokes</span>
            ${toPar ? `<span class="match-score-badge">${toPar}</span>` : ""}
            <span>Type: <strong>${matchType}</strong></span>
            ${statusBadge}
          </div>
          ${holesTableHtml}
        </div>
      `;
    });

    container.innerHTML = listHtml;

    // Bind scorecard toggle buttons
    container.querySelectorAll(".btn-toggle-scorecard").forEach((btn) => {
      btn.addEventListener("click", () => {
        const idx = btn.dataset.idx;
        const panel = document.getElementById(`scorecard-holes-${idx}`);
        if (panel) {
          const isOpen = panel.classList.toggle("open");
          btn.textContent = isOpen ? "Hide Hole-by-Hole Scores ▲" : "View Hole-by-Hole Scores ▼";
        }
      });
    });
  } catch (err) {
    console.error("Recent matches fetch error:", err);
    container.innerHTML = `
      <div class="empty-state">
        <span class="empty-icon">⚠️</span>
        <p>Could not load matches: ${escapeHtml(err.message)}</p>
      </div>
    `;
  }
}

// ─── TAB 3: ACHIEVEMENTS & SWING ANALYSIS (LAZY-LOADED) ───
async function loadAchievementsAndSwing(user) {
  const achContainer = document.getElementById("achievements-grid-container");
  const swingContainer = document.getElementById("swing-issues-container");

  if (achContainer) {
    achContainer.innerHTML = `
      <div class="loading-state">
        <div class="spinner"></div>
        <p>Loading achievements…</p>
      </div>
    `;
  }
  if (swingContainer) {
    swingContainer.innerHTML = `
      <div class="loading-state">
        <div class="spinner"></div>
        <p>Loading swing trends…</p>
      </div>
    `;
  }

  try {
    const statsSnap = await getDoc(doc(db, "profiles", user.uid, "sync", "stats"));
    const statsData = statsSnap.exists() ? statsSnap.data() : {};
    loadedTabs.achievements = true;

    // 1. Achievements
    const unlockedMap = statsData.achievements?.unlocked || {};
    const unlockedKeys = Object.keys(unlockedMap);

    if (unlockedKeys.length === 0) {
      if (achContainer) {
        achContainer.innerHTML = `
          <div class="empty-state">
            <span class="empty-icon">🏆</span>
            <p>No achievements unlocked yet. Play rounds and minigames to unlock achievements!</p>
          </div>
        `;
      }
    } else {
      let achHtml = "";
      unlockedKeys.forEach((key) => {
        const meta = ACHIEVEMENT_LABELS[key] || { title: key.replace(/_/g, " "), desc: "Unlocked in-game challenge" };
        const ts = unlockedMap[key];
        const dateStr = ts ? new Date(ts * 1000).toLocaleDateString() : "";

        achHtml += `
          <div class="achievement-badge-card unlocked">
            <span class="achievement-icon">⭐</span>
            <div class="achievement-info">
              <h4>${escapeHtml(meta.title)}</h4>
              <p>${escapeHtml(meta.desc)}</p>
              ${dateStr ? `<p style="color: var(--green); font-size: 0.75rem;">Unlocked: ${dateStr}</p>` : ""}
            </div>
          </div>
        `;
      });
      if (achContainer) {
        achContainer.innerHTML = `<div class="achievements-grid">${achHtml}</div>`;
      }
    }

    // 2. Swing Issues / Tendencies
    const swingIssues = statsData.swing_issues || {};
    const months = Object.keys(swingIssues).sort().reverse();

    if (months.length === 0) {
      if (swingContainer) {
        swingContainer.innerHTML = `
          <div class="empty-state">
            <span class="empty-icon">📊</span>
            <p>No swing issues logged yet. Enable swing analysis on your launch monitor to track swing tendencies over time!</p>
          </div>
        `;
      }
    } else {
      let swingHtml = "";
      months.forEach((month) => {
        const tendencies = swingIssues[month] || {};
        const issueNames = Object.keys(tendencies);

        let pillsHtml = "";
        issueNames.forEach((name) => {
          const count = tendencies[name];
          pillsHtml += `
            <div class="swing-pill">
              <strong>${escapeHtml(name)}</strong>
              <span class="count-badge">${count}x</span>
            </div>
          `;
        });

        swingHtml += `
          <div class="swing-month-card">
            <div class="swing-month-title">📅 Month: ${escapeHtml(month)}</div>
            <div class="swing-tendencies">${pillsHtml}</div>
          </div>
        `;
      });
      if (swingContainer) {
        swingContainer.innerHTML = `<div class="swing-issues-list">${swingHtml}</div>`;
      }
    }
  } catch (err) {
    console.error("Achievements & swing analysis error:", err);
    if (achContainer) achContainer.innerHTML = `<p class="empty-state">Could not load achievements.</p>`;
    if (swingContainer) swingContainer.innerHTML = `<p class="empty-state">Could not load swing trends.</p>`;
  }
}

// ─── TAB 4: SHARED ACCESS & SETTINGS (REQUIREMENTS 3 & 4) ───
async function loadSharedAccessAndSettings(user) {
  loadedTabs.settings = true;
  await loadDelegatesList(user);
  await loadLeaderboardOptInStatus(user);
  bindAccountDeletion(user);
}

async function loadDelegatesList(user) {
  const container = document.getElementById("delegates-list-container");
  if (!container) return;

  container.innerHTML = `
    <div class="loading-state">
      <div class="spinner"></div>
      <p>Loading active simulator links…</p>
    </div>
  `;

  try {
    const snap = await getDocs(collection(db, "profiles", user.uid, "delegates"));
    const delegates = snap.docs.map((d) => ({ id: d.id, ...d.data() }));

    if (delegates.length === 0) {
      container.innerHTML = `
        <div class="empty-state" style="padding: 1.5rem;">
          <p>No secondary simulators or friends are currently linked to your profile.</p>
        </div>
      `;
      return;
    }

    let listHtml = "";
    delegates.forEach((d) => {
      const name = escapeHtml(d.delegate_name || "Linked Golfer");
      const email = escapeHtml(d.delegate_email || "");
      const dateStr = d.approved_at ? new Date(d.approved_at * 1000).toLocaleDateString() : "";

      listHtml += `
        <div class="delegate-item">
          <div class="delegate-info">
            <h4>${name}</h4>
            <p>${email}${dateStr ? ` · Approved on ${dateStr}` : ""}</p>
          </div>
          <button class="btn-revoke" data-delegate-uid="${d.delegate_uid || d.id}" data-request-id="${d.request_id || ""}">
            Revoke Access
          </button>
        </div>
      `;
    });

    container.innerHTML = listHtml;

    container.querySelectorAll(".btn-revoke").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const delegateUid = btn.dataset.delegateUid;
        const requestId = btn.dataset.requestId;
        await revokeDelegateAccess(user, delegateUid, requestId);
      });
    });
  } catch (err) {
    console.error("Delegates fetch error:", err);
    container.innerHTML = `<p class="empty-state">Could not load delegates: ${escapeHtml(err.message)}</p>`;
  }
}

async function revokeDelegateAccess(user, delegateUid, requestId) {
  if (!confirm("Are you sure you want to revoke simulator access for this device?")) {
    return;
  }

  try {
    const batch = writeBatch(db);
    batch.delete(doc(db, "profiles", user.uid, "delegates", delegateUid));

    if (requestId) {
      batch.update(doc(db, "link_requests", requestId), {
        status: "revoked",
        updated_at: Math.floor(Date.now() / 1000)
      });
    }

    await batch.commit();
    alert("Simulator access has been revoked.");
    await loadDelegatesList(user);
  } catch (err) {
    console.error("Revoke access error:", err);
    const pauseMsg = await handleWriteError(err);
    alert(pauseMsg || ("Could not revoke access: " + err.message));
  }
}

// ─── LEADERBOARD OPT-IN / OPT-OUT (REQUIREMENT 4) ───
async function loadLeaderboardOptInStatus(user) {
  const toggle = document.getElementById("leaderboard-opt-in-toggle");
  if (!toggle) return;

  try {
    const userDocSnap = await getDoc(doc(db, "users", user.uid));
    let isOptedIn = true; // default true (Owner Decision D6)
    if (userDocSnap.exists()) {
      const data = userDocSnap.data();
      if (typeof data.leaderboard_opt_in === "boolean") {
        isOptedIn = data.leaderboard_opt_in;
      }
    }
    toggle.checked = isOptedIn;

    // Remove previous listeners
    const newToggle = toggle.cloneNode(true);
    toggle.parentNode.replaceChild(newToggle, toggle);

    newToggle.addEventListener("change", async () => {
      const checked = newToggle.checked;
      try {
        await updateDoc(doc(db, "users", user.uid), {
          leaderboard_opt_in: checked
        });

        if (!checked) {
          // Delete public_profiles doc
          await deleteDoc(doc(db, "public_profiles", user.uid));
          alert("Your profile has been removed from public leaderboards.");
        } else {
          // Re-create/update public_profiles doc
          const profSnap = await getDoc(doc(db, "profiles", user.uid));
          const p = profSnap.exists() ? profSnap.data() : {};
          const lt = p.lifetime || {};
          const displayName = p.display_name || user.displayName || user.email.split("@")[0];

          const pubData = {
            schema_version: 1,
            uid: user.uid,
            display_name: displayName,
            updated_at: Math.floor(Date.now() / 1000)
          };

          if (typeof lt.longest_drive_yds === "number" && lt.longest_drive_yds >= 0 && lt.longest_drive_yds <= 450) pubData.longest_drive_yds = lt.longest_drive_yds;
          if (typeof lt.longest_putt_ft === "number" && lt.longest_putt_ft >= 0 && lt.longest_putt_ft <= 180) pubData.longest_putt_ft = lt.longest_putt_ft;
          if (typeof lt.best_gross_18 === "number" && lt.best_gross_18 >= 18 && lt.best_gross_18 <= 250) pubData.best_gross_18 = lt.best_gross_18;
          if (typeof lt.best_to_par_18 === "number" && lt.best_to_par_18 >= -36 && lt.best_to_par_18 <= 180) pubData.best_to_par_18 = lt.best_to_par_18;
          if (typeof lt.best_gross_9 === "number" && lt.best_gross_9 >= 9 && lt.best_gross_9 <= 130) pubData.best_gross_9 = lt.best_gross_9;
          if (typeof lt.best_to_par_9 === "number" && lt.best_to_par_9 >= -18 && lt.best_to_par_9 <= 90) pubData.best_to_par_9 = lt.best_to_par_9;
          if (typeof lt.achievements_count === "number" && lt.achievements_count >= 0 && lt.achievements_count <= 100) pubData.achievements_count = lt.achievements_count;
          if (typeof lt.matches_played === "number" && lt.matches_played >= 0 && lt.matches_played <= 100000) pubData.matches_played = lt.matches_played;
          if (typeof lt.wins === "number" && lt.wins >= 0 && lt.wins <= 100000) pubData.wins = lt.wins;
          if (typeof lt.hole_in_ones === "number" && lt.hole_in_ones >= 0 && lt.hole_in_ones <= 1000) pubData.hole_in_ones = lt.hole_in_ones;

          await setDoc(doc(db, "public_profiles", user.uid), pubData, { merge: true });
          alert("Your profile is now visible on public leaderboards!");
        }
      } catch (err) {
        console.error("Leaderboard opt-in error:", err);
        const pauseMsg = await handleWriteError(err);
        alert(pauseMsg || ("Could not update privacy setting: " + err.message));
        newToggle.checked = !checked;
      }
    });
  } catch (err) {
    console.warn("Could not load user opt-in status:", err);
  }
}

// ─── ACCOUNT DELETION (REQUIREMENT 4) ───
function bindAccountDeletion(user) {
  const btnDelete = document.getElementById("btn-delete-account");
  if (!btnDelete) return;

  // Replace node to clear old listeners
  const newBtn = btnDelete.cloneNode(true);
  btnDelete.parentNode.replaceChild(newBtn, btnDelete);

  newBtn.addEventListener("click", async () => {
    const confirmation = prompt(
      "CAUTION: This will permanently delete your Heckle Golf profile, personal bests, club averages, match summaries, and account.\n\nType DELETE to confirm:"
    );

    if (confirmation !== "DELETE") {
      alert("Account deletion cancelled.");
      return;
    }

    newBtn.textContent = "Deleting Account…";
    newBtn.disabled = true;

    try {
      // 1. Delete public_profiles/{uid}
      try { await deleteDoc(doc(db, "public_profiles", user.uid)); } catch {}

      // 2. Delete profiles/{uid}/sync/stats
      try { await deleteDoc(doc(db, "profiles", user.uid, "sync", "stats")); } catch {}

      // 3. Delete profiles/{uid}
      try { await deleteDoc(doc(db, "profiles", user.uid)); } catch {}

      // 4. Delete users/{uid}
      try { await deleteDoc(doc(db, "users", user.uid)); } catch {}

      // 5. Delete Firebase Auth user
      await deleteUser(user);

      alert("Your account and cloud data have been completely deleted.");
      window.location.reload();
    } catch (err) {
      console.error("Account deletion failed:", err);
      if (err.code === "auth/requires-recent-login") {
        alert("This operation is sensitive and requires recent authentication. Please sign out and sign back in before deleting your account.");
      } else {
        const pauseMsg = await handleWriteError(err);
        alert(pauseMsg || ("Could not complete account deletion: " + err.message));
      }
      newBtn.textContent = "Delete Account & Cloud Data";
      newBtn.disabled = false;
    }
  });
}

function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
