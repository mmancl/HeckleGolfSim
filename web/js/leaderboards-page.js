import { initLeaderboards } from "./leaderboards.js";
import { checkBudgetStatus } from "./budget.js";

function setupLeaderboardsPage() {
  initLeaderboards();
  checkBudgetStatus();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setupLeaderboardsPage);
} else {
  setupLeaderboardsPage();
}
