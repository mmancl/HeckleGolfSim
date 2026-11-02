import { describe, it, before, after, beforeEach } from "node:test";
import assert from "node:assert";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from "firebase/firestore";
import { ref as rtdbRef, get as rtdbGet, set as rtdbSet, remove as rtdbRemove } from "firebase/database";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const PROJECT_ID = "heckle-golf-sim";

const firestoreRules = readFileSync(
  resolve(__dirname, "../../firestore.rules"),
  "utf8"
);
const databaseRules = readFileSync(
  resolve(__dirname, "../../database.rules.json"),
  "utf8"
);

describe("Firebase Backend Security Rules & Budget Guard Suite", () => {
  let testEnv;

  before(async () => {
    const fsHostPort = (process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080").split(":");
    const rtdbHostPort = (process.env.FIREBASE_DATABASE_EMULATOR_HOST || "127.0.0.1:9000").split(":");

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: firestoreRules,
        host: fsHostPort[0],
        port: parseInt(fsHostPort[1], 10),
      },
      database: {
        rules: databaseRules,
        host: rtdbHostPort[0],
        port: parseInt(rtdbHostPort[1], 10),
      },
    });
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    if (testEnv) {
      await testEnv.clearFirestore();
      if (typeof testEnv.clearDatabase === "function") {
        await testEnv.clearDatabase();
      } else {
        await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
          await rtdbSet(rtdbRef(adminCtx.database()), null);
        });
      }
    }
  });

  // 1. Owner & Delegate Access
  describe("1. Owner & Delegate Access", () => {
    it("enforces private user account ownership", async () => {
      const alice = testEnv.authenticatedContext("uid_1");
      const bob = testEnv.authenticatedContext("uid_2");
      const aliceDb = alice.firestore();
      const bobDb = bob.firestore();

      // Owner can create own user document
      await assertSucceeds(
        setDoc(doc(aliceDb, "users", "uid_1"), {
          schema_version: 1,
          display_name: "Alice",
        })
      );

      // Owner can read own user document
      await assertSucceeds(getDoc(doc(aliceDb, "users", "uid_1")));

      // Other user cannot read or write Alice's user document
      await assertFails(getDoc(doc(bobDb, "users", "uid_1")));
      await assertFails(
        setDoc(doc(bobDb, "users", "uid_1"), {
          schema_version: 1,
          display_name: "Attacker",
        })
      );
    });

    it("grants profile, stats, and match access to owner and approved delegates", async () => {
      const alice = testEnv.authenticatedContext("uid_1");
      const bob = testEnv.authenticatedContext("uid_2");
      const aliceDb = alice.firestore();
      const bobDb = bob.firestore();

      // Alice creates her profile
      await assertSucceeds(
        setDoc(doc(aliceDb, "profiles", "uid_1"), {
          schema_version: 1,
          owner_uid: "uid_1",
          display_name: "Alice Golf",
        })
      );

      // Bob cannot read or write to Alice's profile or stats before being approved as a delegate
      await assertFails(getDoc(doc(bobDb, "profiles", "uid_1")));
      await assertFails(
        setDoc(doc(bobDb, "profiles", "uid_1", "sync", "stats"), {
          schema_version: 1,
          clubs: {},
        })
      );

      // Alice approves Bob as a delegate
      await assertSucceeds(
        setDoc(doc(aliceDb, "profiles", "uid_1", "delegates", "uid_2"), {
          delegate_uid: "uid_2",
        })
      );

      // Now Bob (approved delegate) can read Alice's profile and write stats/matches
      await assertSucceeds(getDoc(doc(bobDb, "profiles", "uid_1")));
      await assertSucceeds(
        setDoc(doc(bobDb, "profiles", "uid_1", "sync", "stats"), {
          schema_version: 1,
          clubs: {
            Dr: [{ id: "shot1", tot: 260.0 }],
          },
        })
      );
      await assertSucceeds(
        setDoc(doc(bobDb, "profiles", "uid_1", "matches", "match_100"), {
          schema_version: 1,
          match_id: "match_100",
          strokes: 72,
          holes_count: 18,
        })
      );

      // Delegate cannot delete owner's profile or sync doc (only owner can delete)
      await assertFails(deleteDoc(doc(bobDb, "profiles", "uid_1")));
      await assertFails(deleteDoc(doc(bobDb, "profiles", "uid_1", "sync", "stats")));

      // Delegate can delete own delegate doc to revoke themselves
      await assertSucceeds(deleteDoc(doc(bobDb, "profiles", "uid_1", "delegates", "uid_2")));

      // After revocation, delegate access is immediately lost
      await assertFails(getDoc(doc(bobDb, "profiles", "uid_1")));
    });
  });

  // 2. Verified Email Requirement
  describe("2. Verified Email Requirement for Link Approvals", () => {
    it("requires a verified email token matching target_email_lower to approve link requests", async () => {
      const alice = testEnv.authenticatedContext("uid_1", {
        email: "alice@example.com",
        email_verified: true,
      });
      const unverifiedBob = testEnv.authenticatedContext("uid_2", {
        email: "bob@example.com",
        email_verified: false,
      });
      const verifiedBob = testEnv.authenticatedContext("uid_2", {
        email: "bob@example.com",
        email_verified: true,
      });

      const aliceDb = alice.firestore();
      const unverifiedDb = unverifiedBob.firestore();
      const verifiedDb = verifiedBob.firestore();

      // Alice sends link request to bob@example.com
      await assertSucceeds(
        setDoc(doc(aliceDb, "link_requests", "req_alice_to_bob"), {
          requester_uid: "uid_1",
          status: "pending",
          target_email_lower: "bob@example.com",
        })
      );

      // Unverified Bob attempts to approve the link request -> REJECTED
      await assertFails(
        updateDoc(doc(unverifiedDb, "link_requests", "req_alice_to_bob"), {
          status: "approved",
          target_uid: "uid_2",
          requester_uid: "uid_1",
          target_email_lower: "bob@example.com",
        })
      );

      // Verified Bob approves the link request -> SUCCEEDS
      await assertSucceeds(
        updateDoc(doc(verifiedDb, "link_requests", "req_alice_to_bob"), {
          status: "approved",
          target_uid: "uid_2",
          requester_uid: "uid_1",
          target_email_lower: "bob@example.com",
        })
      );
    });
  });

  // 3. Leaderboard Range Validation & PII Exclusion
  describe("3. Leaderboard Range Validation & Privacy Protection", () => {
    it("validates metric ranges and forbids email field in public_profiles", async () => {
      const alice = testEnv.authenticatedContext("uid_1");
      const aliceDb = alice.firestore();

      // Valid leaderboard entry succeeds
      await assertSucceeds(
        setDoc(doc(aliceDb, "public_profiles", "uid_1"), {
          schema_version: 1,
          uid: "uid_1",
          display_name: "Alice",
          longest_drive_yds: 312.4,
          longest_putt_ft: 44.2,
          best_gross_18: 70,
          best_to_par_18: -2,
          best_gross_9: 35,
          best_to_par_9: -1,
          achievements_count: 17,
          matches_played: 42,
          wins: 11,
          hole_in_ones: 1,
        })
      );

      // Out-of-range longest_drive_yds (> 450.0) is rejected
      await assertFails(
        setDoc(doc(aliceDb, "public_profiles", "uid_1"), {
          schema_version: 1,
          uid: "uid_1",
          display_name: "Alice",
          longest_drive_yds: 999.0,
        })
      );

      // Out-of-range best_gross_18 (> 250) is rejected
      await assertFails(
        setDoc(doc(aliceDb, "public_profiles", "uid_1"), {
          schema_version: 1,
          uid: "uid_1",
          display_name: "Alice",
          best_gross_18: 300,
        })
      );

      // Inclusion of email field (PII) is strictly rejected
      await assertFails(
        setDoc(doc(aliceDb, "public_profiles", "uid_1"), {
          schema_version: 1,
          uid: "uid_1",
          display_name: "Alice",
          email: "alice@example.com",
        })
      );
    });
  });

  // 4. Abandoned Lobby Cleanup Rule (RTDB)
  describe("4. RTDB Abandoned Lobby Cleanup Rule", () => {
    it("allows any authenticated user to purge abandoned lobbies (>45s) while preventing deletion of active lobbies", async () => {
      const host = testEnv.authenticatedContext("host_uid");
      const otherPlayer = testEnv.authenticatedContext("other_uid");
      const hostRtdb = host.database();
      const otherRtdb = otherPlayer.database();

      const nowSec = Math.floor(Date.now() / 1000);

      // Host creates an active lobby
      await assertSucceeds(
        rtdbSet(rtdbRef(hostRtdb, "lobbies/match_abc"), {
          host_uid: "host_uid",
          created_at: nowSec,
          last_seen: nowSec,
        })
      );

      // Other player cannot delete host's active lobby (last_seen within 45s)
      await assertFails(rtdbRemove(rtdbRef(otherRtdb, "lobbies/match_abc")));

      // Simulate abandoned lobby: last_seen is updated to 50 seconds ago
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        await rtdbSet(rtdbRef(adminCtx.database(), "lobbies/match_abc/last_seen"), nowSec - 50);
      });

      // Now other player CAN clean up the abandoned lobby
      await assertSucceeds(rtdbRemove(rtdbRef(otherRtdb, "lobbies/match_abc")));
    });
  });

  // 5. $10 Budget Circuit-Breaker Lock Test
  describe("5. $10 Budget Circuit-Breaker Lockout", () => {
    it("locks down writes while preserving public status and leaderboard reads when paused == true", async () => {
      // Seed public profile and status before trip
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const adminFs = adminCtx.firestore();
        const adminRtdb = adminCtx.database();

        await setDoc(doc(adminFs, "public_profiles", "budget_user"), {
          schema_version: 1,
          uid: "budget_user",
          display_name: "Alice",
          longest_drive_yds: 300.0,
        });
        // Circuit breaker trips: system/status.paused = true in Firestore and RTDB
        await setDoc(doc(adminFs, "system", "status"), {
          schema_version: 1,
          paused: true,
          reason: "monthly_budget_reached",
          message: "Multiplayer is temporarily paused for the remainder of the month...",
        });
        await rtdbSet(rtdbRef(adminRtdb, "system/status"), {
          paused: true,
          reason: "monthly_budget_reached",
        });
      });

      const alice = testEnv.authenticatedContext("budget_user");
      const unauthed = testEnv.unauthenticatedContext();
      const aliceDb = alice.firestore();
      const aliceRtdb = alice.database();
      const unauthedDb = unauthed.firestore();
      const unauthedRtdb = unauthed.database();

      // 1. Reading system/status still succeeds (unauthenticated and authenticated)
      await assertSucceeds(getDoc(doc(unauthedDb, "system", "status")));
      await assertSucceeds(rtdbGet(rtdbRef(unauthedRtdb, "system/status")));

      // 2. Reading public_profiles still succeeds so users can view leaderboards
      await assertSucceeds(getDoc(doc(unauthedDb, "public_profiles", "budget_user")));

      // 3. All client writes to Firestore are rejected by security rules
      await assertFails(
        setDoc(doc(aliceDb, "users", "budget_user"), {
          schema_version: 1,
          display_name: "Alice",
        })
      );
      await assertFails(
        setDoc(doc(aliceDb, "profiles", "budget_user"), {
          schema_version: 1,
          owner_uid: "budget_user",
          display_name: "Alice",
        })
      );
      await assertFails(
        setDoc(doc(aliceDb, "profiles", "budget_user", "sync", "stats"), {
          schema_version: 1,
          clubs: {},
        })
      );
      await assertFails(
        setDoc(doc(aliceDb, "profiles", "budget_user", "matches", "match_new"), {
          schema_version: 1,
          match_id: "match_new",
          strokes: 72,
          holes_count: 18,
        })
      );
      await assertFails(
        setDoc(doc(aliceDb, "link_requests", "req_blocked"), {
          requester_uid: "budget_user",
          status: "pending",
          target_email_lower: "someone@example.com",
        })
      );
      await assertFails(
        setDoc(doc(aliceDb, "public_profiles", "budget_user"), {
          schema_version: 1,
          uid: "budget_user",
          display_name: "Alice",
        })
      );

      // Client cannot write to system/status
      await assertFails(
        setDoc(doc(aliceDb, "system", "status"), {
          paused: false,
        })
      );

      // 4. All client writes to RTDB are rejected
      await assertFails(
        rtdbSet(rtdbRef(aliceRtdb, "codes/ABC123"), {
          host_uid: "budget_user",
        })
      );
      await assertFails(
        rtdbSet(rtdbRef(aliceRtdb, "lobbies/match_blocked"), {
          host_uid: "budget_user",
          last_seen: Math.floor(Date.now() / 1000),
        })
      );
      await assertFails(
        rtdbSet(rtdbRef(aliceRtdb, "matches/match_blocked/meta"), {
          host_uid: "budget_user",
        })
      );
      await assertFails(
        rtdbSet(rtdbRef(aliceRtdb, "system/status"), {
          paused: false,
        })
      );
    });
  });
});
