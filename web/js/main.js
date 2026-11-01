import { initLeaderboards } from "./leaderboards.js";
import { initPortal } from "./portal.js";
import { checkBudgetStatus } from "./budget.js";

function setupApp() {
  initLeaderboards();
  initPortal();
  checkBudgetStatus();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setupApp);
} else {
  setupApp();
}
