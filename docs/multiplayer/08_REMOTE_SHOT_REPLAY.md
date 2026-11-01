# Work Package 08 — Remote Shot Replay (Direct Point A → Point B, Zero Rollout / Collision-Free)

> **Prerequisite:** Read [`00_OVERVIEW.md`](00_OVERVIEW.md).
> **Can start:** Immediately (Phase 0). Pure local gameplay/visual feature with **zero** Firebase dependencies.
> **Owns:** `Player/remote_shot_replayer.gd`, minimal kinematic-replay mode flag in `Player/ball.gd`, `tests/test_remote_shot_replay.gd`.
> **Must NOT edit:** `Courses/Range/range.gd`, `Courses/CoursePlay/course_play.gd`, `Utils/MultiplayerManager.gd` (Package 09 wires the replayer into those).

---

## 1. Scope & Goals

Per Requirement G10, Owner Decision D7, and Hole H19:
- Procedural trees, rocks, and local terrain meshes can have minor variations across devices or graphics quality settings.
- Therefore, when a remote player hits a shot in online multiplayer, the only position data needed is **Point A (`start_pos`)** and **Point B (`end_pos`)** (plus `club` so we know whether it was an air shot or a putt).
- **Non-Putter Shots (Driver, Woods, Hybrids, Irons, Wedges):**
  - **No ball rollout at all.** The ball launches from Point A (`start_pos`), flies through the air in a clean arc with average speed and loft directly to Point B (`end_pos`), and **stops immediately at Point B** upon landing.
  - Ignores all tree, rock, and terrain collisions along the way so it is 100% guaranteed to land and stop on the exact spot the remote player ended up.
- **Putts (`Pt` / `Putter`):**
  - Putts always roll from Point A (`start_pos`) to Point B (`end_pos`) along a straight line **without worrying about green slope or physics**, decelerating smoothly to a stop right at Point B.
- **Crucial Guardrail (Hole H19):** Replaying a remote shot must **NEVER** emit `ball.rest` or `player.rest` (which would trigger `range._on_golf_ball_rest`, water-hazard relief drops, local stat recording, or double turn advancement). Instead, `RemoteShotReplayer` emits its own `replay_started` and `replay_finished(event_data)` signals.

---

## 2. Public API (`Player/remote_shot_replayer.gd`)

```gdscript
class_name RemoteShotReplayer
extends Node

signal replay_started(shot_event: Dictionary)
signal replay_progress(current_pos: Vector3)
signal replay_finished(shot_event: Dictionary)

# Plays a simple, collision-free trajectory directly from start_pos (A) to end_pos (B) and stops at B.
# Required keys in shot_event:
#   "start": Vector3 or [x, y, z]
#   "end": Vector3 or [x, y, z]
#   "club": String (e.g. "Dr", "7i", "SW", "Pt")
func play_remote_shot(
    ball_node: Node3D,
    shot_event: Dictionary,
    tracer_node: Node = null
) -> void

func is_replaying() -> bool
func skip_to_end() -> void

# Pure helper (exposed static for unit testing without a 3D scene):
static func build_trajectory_profile(start_pos: Vector3, end_pos: Vector3, club: String) -> Dictionary
static func sample_trajectory_at_time(profile: Dictionary, elapsed_s: float) -> Vector3
```

---

## 3. Simple Point A → Point B Replay Model

Given `start_pos` ($A$) and `end_pos` ($B$) and `club`:

Let horizontal distance $D = \text{Vector2}(A.x, A.z).\text{distance\_to}(\text{Vector2}(B.x, B.z))$ in meters.

### 3.1 Case 1 — Non-Putter Shots (`club != "Pt"`): Direct Air Arc from A → B, Then Stop (Zero Rollout)
1. **Average Speed & Peak Height by Club Type:**
   - **Driver / Woods (`Dr`, `3W`, `5W`, `7W`):** average horizontal speed = `42 m/s`, arc peak height = `clamp(D * 0.14, 3.0, 34.0)` meters above straight line $A \to B$.
   - **Hybrids / Long Irons (`2H`–`5H`, `3i`–`5i`):** average horizontal speed = `36 m/s`, arc peak height = `clamp(D * 0.18, 3.0, 32.0)` meters.
   - **Mid / Short Irons (`6i`–`9i`, `PW`):** average horizontal speed = `30 m/s`, arc peak height = `clamp(D * 0.22, 2.5, 30.0)` meters.
   - **Wedges (`GW`, `SW`, `LW`):** average horizontal speed = `22 m/s`, arc peak height = `clamp(D * 0.28, 1.5, 26.0)` meters.
2. **Flight Duration:**
   - `duration_s = clamp(D / avg_speed_mps, 0.8, 5.5)` seconds.
3. **Position at normalized time `u = clamp(elapsed_s / duration_s, 0.0, 1.0)`:**
   - Base straight-line interpolation from $A$ to $B$: `base_pos = A.lerp(B, u)`
   - Vertical arc height added on top: `arc_y = 4.0 * peak_height_m * u * (1.0 - u)` (which is `0` at $u=0$, `peak_height_m` at the midpoint $u=0.5$, and `0` at $u=1$).
   - `pos = Vector3(base_pos.x, base_pos.y + arc_y, base_pos.z)`.
   - At `u == 1.0`, `pos` is **identically `end_pos` ($B$)** and the ball stops immediately with **zero rollout**.

### 3.2 Case 2 — Putts (`club == "Pt"`): Straight Roll from A → B Ignoring Slope
1. **Duration:**
   - Average putt speed = `3.5 m/s` → `duration_s = clamp(D / 3.5, 0.6, 4.0)` seconds.
2. **Position at normalized time `u = clamp(elapsed_s / duration_s, 0.0, 1.0)`:**
   - Smooth ease-out deceleration so the putt slows down naturally as it reaches Point B: `w = 1.0 - (1.0 - u) * (1.0 - u)`.
   - Straight-line interpolation ignoring slope: `pos = A.lerp(B, w)`.
   - At `u == 1.0`, `pos` is **identically `end_pos` ($B$)** and stops.

---

## 4. Ball State & Collision Isolation (`Player/ball.gd`)

During `play_remote_shot()`:
1. Set a boolean property on `ball_node`: `ball.is_replaying_remote_shot = true`.
2. In `Player/ball.gd` `_physics_process(delta)`:
   - Add a 2-line guard at the very top of `_physics_process`:
     ```gdscript
     if is_replaying_remote_shot:
         return
     ```
   - This guarantees `ball.gd` will not run `move_and_slide()`, will not collide with trees/rocks/water/cup triggers, and will **never** emit `rest`.
3. `RemoteShotReplayer` updates `ball_node.global_position` in `_process(delta)`, appends points to `tracer_node` (if provided) so the remote player's shot tracer ribbon renders cleanly, and when `elapsed_s >= duration_s`:
   - Sets `ball_node.global_position = end_pos`
   - Sets `ball.is_replaying_remote_shot = false`
   - Sets `ball.state = PhysicsEnums.BallState.REST` (without emitting `rest`)
   - Emits `replay_finished.emit(shot_event)`.

---

## 5. Verification & Unit Tests

Create `tests/test_remote_shot_replay.gd`:
1. **Direct A → B Endpoint & Zero Rollout Guarantee:** Test `build_trajectory_profile` and `sample_trajectory_at_time` for Driver, 7-Iron, Sand Wedge, and Putter, verifying that `t = 0.0` is exactly `start_pos`, `t = duration_s` is exactly `end_pos`, and non-putter shots have zero rollout phase (`roll_s == 0.0`).
2. **Putter Straight-Line Roll:** Verify that a `"Pt"` replay interpolates directly along the straight segment `A.lerp(B, w)` with zero vertical arc offset (`peak_height_m == 0.0`).
3. **Zero `rest` Signal Emission (Hole H19):** Instantiate `GolfBall` and `RemoteShotReplayer`, connect a spy counter to `ball.rest`, run a replay from $A$ to $B$, and assert `replay_finished` fired once while `ball.rest` fired **0** times.
