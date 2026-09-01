# Minigames Implementation Walkthrough

We have successfully implemented and refined the minigame system, incorporating all user feedback to match the desired premium visual design, physics accuracy, and camera behaviors.

## Summary of Improvements

### 1. Visual Enhancements (Real Game Grass Texture & Retaining Walls)
- **Putting Green**: Applied the real game's grass texture (`res://Courses/Environments/grass-green/albedo.png`) with UV mapping coordinates over the sloped mesh, ensuring a consistent look and feel with the main simulator holes.
- **Chipping Islands**: Designed a two-tier cylinder structure:
  - **Wood Retaining Wall Base**: A slightly wider cylinder with a warm wood brown color (`Color(0.35, 0.25, 0.15)`) representing wood panels/logs floating in the water.
  - **Grass Turf Top**: A cylinder sitting on top with the same `grass-green/albedo.png` texture as the green.

### 2. Staggered Island Layout (Chipping Minigame)
- The 7 chipping islands (25, 50, 75, 100, 125, 150, and 200 yards) are **staggered on the Z-axis** (left and right of the player) instead of being in a single straight line.
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
- Players can select different targets by clicking **Hole 1 - 8** (Putting) or **Target 25 - 200 YDS** (Chipping) directly from the screen, in addition to clicking on the 3D world targets.

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
   - Click the buttons on the left panel (**5 - 50 FT**) or click near flags in the 3D scene to change targets.
   - Hit or simulate a putt. The camera will follow the ball rollout.
   - Putts rolling slowly over the white cup marker snap and drop into the cup.
3. Select **Chipping Practice**:
   - View the staggered green islands with their wood base retaining walls and flags showing **25 - 200 YDS**.
   - Select targets (e.g. **25 - 200 YDS**) on the left panel or click on the islands.
   - Hit shot on Launch Monitor (or test hit). The camera will track the ball flight.
