import { auth, onAuthStateChanged } from "./firebase-init.js";

function setupApp() {
  const btnSignin = document.getElementById("nav-signin-btn");
  const greeting = document.getElementById("user-greeting");
  const avatarEl = document.getElementById("user-avatar");
  const nameEl = document.getElementById("user-name");

  onAuthStateChanged(auth, (user) => {
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
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setupApp);
} else {
  setupApp();
}
