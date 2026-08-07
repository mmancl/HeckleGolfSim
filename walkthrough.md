# Minigames Implementation Walkthrough

We have successfully implemented and refined the minigame system, incorporating all user feedback to match the desired premium visual design, physics accuracy, and camera behaviors.

## Summary of Improvements

### 1. Visual Enhancements (Real Game Grass Texture & Retaining Walls)
- **Putting Green**: Applied the real game's grass texture (`res://Courses/Environments/grass-green/albedo.png`) with UV mapping coordinates over the sloped mesh, ensuring a consistent look and feel with the main simulator holes.
- **Chipping Islands**: Designed a two-tier cylinder structure:
  - **Wood Retaining Wall Base**: A slightly wider cylinder with a warm wood brown color (`Color(0.35, 0.25, 0.15)`) representing wood panels/logs floating in the water.
  - **Grass Turf Top**: A cylinder sitting on top with the same `grass-green/albedo.png` texture as the green.

### 2. Staggered Island Layout (Chipping Minigame)
- The 6 chipping islands (50, 100, 150, 200, 250, and 300 feet) are now **staggered on the Z-axis** (left and right of the player) instead of being in a single straight line.
- This prevents visual blocking, gives clear flight paths, and forces players to adjust their horizontal aim (HLA) for each island!

### 3. Height Topography & Reader Slopes (Putting Minigame)
- The height function for the putting green now generates a larger variety of slopes, including a prominent **diagonal ridge** (southwest-to-northeast), a gentle valley, and rolling hills.
- This creates realistic ball break curves when putting across slopes.

### 4. Interactive Look-Around Orbit Camera & Aim Controls
- **Right-Click Drag**: Hold the right mouse button and drag left/right to orbit the camera and aim.
- **Keyboard Rotation**: Press the **Left/Right Arrow Keys** or **A/D** keys to rotate your aim yaw and camera left/right in fine-tuned 1.5° steps.
- **Aim Angle Slider**: Orbiting updates the UI Aim Offset slider.

### 5. Floating Target Selector Panels
- Added a floating panel on the **left side of the screen** in both minigames.
- Players can select different targets by clicking **Hole 1 - 5** (Putting) or **Target 50 - 300 FT** (Chipping) directly from the screen, in addition to clicking on the 3D world targets.

### 6. Accurate Programmatic Cup Entry SNAP (Putting Minigame)
- Since the procedurally generated green mesh is continuous, the ball would normally roll right over the cup marker.
- Added a dynamic rolling check: if the ball passes over the cup slowly (XZ distance < 0.14m, speed < 2.4 m/s), the physics engine snaps it to the center, drops it `0.04m` down into the cup, and stops it, triggering a successful **Holed Out** score and playing the golf clap stream.

### 7. Real Game Camera Ball Follow
- Once the ball is hit (putt or chip), the camera switches to a follow mode, maintaining its launch offset relative to the moving ball and tracking its flight or rollout.
- When the ball comes to rest, the camera automatically snaps back behind the ball, re-aligned towards the selected target.

---

## How to Verify / Play

1. Select **MINI GAMES** on the main menu.
2. Select **Putting Practice**:
   - Hold the **Right Mouse Button** and drag to rotate the camera around the ball to read breaks or look around the green.
   - Press **A/D** or **Left/Right arrows** to rotate.
   - Click the buttons on the left panel (**Hole 1 - 5**) or click near flags in the 3D scene to change targets.
   - Click **PUTT** (or press **H**) to stroke. The camera will follow the ball rollout.
   - Putts rolling slowly over the white cup marker snap and drop into the cup.
3. Select **Chipping Practice**:
   - View the staggered green islands with their wood base retaining walls.
   - Select targets (e.g. **Target: 150 FT**) on the left panel or click on the islands.
   - Adjust loft angle (VLA) and power.
   - Click **CHIP** (or press **H**). The camera will track the ball flight.
