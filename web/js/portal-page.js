import { initPortal } from "./portal.js";
import { checkBudgetStatus } from "./budget.js";

function setupPortalPage() {
  initPortal();
  checkBudgetStatus();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setupPortalPage);
} else {
  setupPortalPage();
}
