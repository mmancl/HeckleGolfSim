import { db, doc, getDoc } from "./firebase-init.js";

const BUDGET_CACHE_KEY = "hgs_system_status";
const BUDGET_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes
const DEFAULT_PAUSE_MESSAGE =
  "Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience.";

export async function checkBudgetStatus(forceRefresh = false) {
  try {
    if (!forceRefresh) {
      const cached = sessionStorage.getItem(BUDGET_CACHE_KEY);
      if (cached) {
        try {
          const parsed = JSON.parse(cached);
          if (Date.now() - parsed.timestamp < BUDGET_CACHE_TTL_MS) {
            updateBudgetUI(parsed.paused, parsed.message);
            return parsed;
          }
        } catch {
          // Ignore cache parse error
        }
      }
    }

    const snap = await getDoc(doc(db, "system", "status"));
    let isPaused = false;
    let message = DEFAULT_PAUSE_MESSAGE;

    if (snap.exists()) {
      const data = snap.data();
      isPaused = data.paused === true;
      if (data.message) {
        message = data.message;
      }
    }

    const statusObj = {
      paused: isPaused,
      message,
      timestamp: Date.now()
    };
    sessionStorage.setItem(BUDGET_CACHE_KEY, JSON.stringify(statusObj));
    updateBudgetUI(isPaused, message);
    return statusObj;
  } catch (err) {
    console.warn("Could not check system/status:", err.message);
    return { paused: false, message: "", timestamp: Date.now() };
  }
}

export function updateBudgetUI(isPaused, message = DEFAULT_PAUSE_MESSAGE) {
  const banners = document.querySelectorAll(".budget-paused-banner");
  banners.forEach((banner) => {
    if (isPaused) {
      banner.classList.add("active");
      const textEl = banner.querySelector(".banner-text");
      if (textEl) {
        textEl.innerHTML = `<strong>Service Paused</strong>${message || DEFAULT_PAUSE_MESSAGE}`;
      }
    } else {
      banner.classList.remove("active");
    }
  });
}

export async function handleWriteError(err) {
  if (err && (err.code === "permission-denied" || (err.message && err.message.includes("permission-denied")))) {
    const status = await checkBudgetStatus(true);
    if (status.paused) {
      return status.message || DEFAULT_PAUSE_MESSAGE;
    }
  }
  return null;
}
