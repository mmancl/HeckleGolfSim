# Heckle Golf Simulator — Google Play Store Listing & Metadata

This document contains the ready-to-copy text, metadata, and asset specifications for publishing **Heckle Golf Simulator** to the Google Play Store and Open Beta testing track.

---

## 1. Store Listing Copy

### App Title (Max 30 characters)
Heckle Golf Simulator
(Length: 21 / 30 characters)

---

### Short Description (Max 80 characters)

**Primary (Recommended):**
Realistic golf sim with launch monitor support, AI swing tracker & heckles!
(Length: 77 / 80 characters)

**Alternative 1 (Hardware & Real Courses Focus):**
Full golf simulator with launch monitor support & real-world 3D courses!
(Length: 75 / 80 characters)

**Alternative 2 (Practice & Humor Focus):**
Golf sim with real course generator, AI swing analysis & witty heckles!
(Length: 75 / 80 characters)

---

### Full Description (Max 4000 characters)

Turn your Android device into a full-featured golf simulator and practice suite with Heckle Golf Simulator!

Whether you're dialing in your yardages on the driving range, reading breaks on undulating practice greens, analyzing your swing mechanics with AI, or playing 18 holes on real-world courses with a witty announcer roasting your slices—Heckle Golf Simulator brings the ultimate golf experience right to your setup.

⛳ REAL LAUNCH MONITOR & HARDWARE CONNECTIVITY
Connect your launch monitor directly to your device:
• Native Square Golf Launch Monitor support (Direct Bluetooth BLE, Serial, & TCP).
• GSPro Open Connect v1 TCP listener (Port 49152) — compatible with PiTrac, Garmin, FlightScope, and custom bridge software.
• Built-in on-screen Shot Injector for practice and testing anywhere, anytime!

🌍 PLAY REAL-WORLD GOLF COURSES WORLDWIDE
• OpenStreetMap (OSM) Course Generator: Search, download, and play almost ANY real-world golf course on Earth!
• Realistic 3D terrain, elevation changes, fairways, greens, tee boxes, and hazards generated directly from satellite open data.
• Built-in Custom Course Creator: Design and plot your own custom golf holes.

🏌️ FULL 18-HOLE MULTIPLAYER COURSE PLAY
• Play 9 or 18-hole rounds in Stroke Play, Match Play, or Skins formats.
• Realistic USGA rules of play, honors rotation, and scorecard tracking.
• Interactive top-down GPS Minimap with green zoom and dynamic Front/Middle/Back pin distances.
• Casual mulligan options and multi-player handicap management.

🤖 AI GOLFER CAMERA & SWING POSE TRACKING
• Real-time 33-point full-body skeletal tracking powered by Google MediaPipe on your Android GPU.
• Live swing tempo (e.g., 3:1 backswing-to-downswing ratio), shoulder turn, hip rotation, and spine angle tracking.
• Swing Replay & Slow-Motion Video Scrub: Review every phase of your swing from address to follow-through.

🎯 ACCURATE DRIVING RANGE & MINIGAMES
• Comprehensive Telemetry HUD: Carry Distance, Total Yardage, Ball Speed, Club Speed, Smash Factor, Launch Angles (VLA/HLA), Total Spin, Backspin, Sidespin, Spin Axis, and Apex Height.
• Dynamic 3D Shot Ribbon Trails & Club Dispersion Ellipses.
• Putting Practice: Read realistic green contours, slopes, and ridges with an interactive 3D Orbit Camera.
• Chipping Practice: Island target greens over water across 25 to 200 yards.
• Environmental controls: Adjust Wind, Altitude, Temperature, Humidity, and Turf firmness on the fly.

🎙️ DYNAMIC HECKLE ANNOUNCER ENGINE
• Experience dynamic, comedic commentary inspired by classic arcade sports games!
• The announcer praises your 300-yard bombed drives and roasts your topped shots, wicked slices, skyballs, and trips into the sand traps.
• Fully customizable pitch, rate, and heckle toggles.

🔬 ADVANCED BALL FLIGHT PHYSICS
• Built on the OpenFairway v1.0.6 aerodynamic model combined with JoltPhysics3D.
• True Reynolds number drag/lift coefficient calculations and USGA Stimpmeter-calibrated turf interactions.

---
DISCLAIMER:
Heckle Golf Simulator is an independent open-source project. It is not affiliated with, endorsed by, or sponsored by Square Golf (SquareGolf Co., Ltd.), GSPro (FlightPath Golf LLC), Garmin Ltd., or any launch monitor manufacturer. All trademarks belong to their respective owners.

---

## 2. Release Notes / What's New in this Version (Max 500 characters)

**For Open Beta Release 1:**
Welcome to the Heckle Golf Simulator Open Beta!
• 18-hole course play with OpenStreetMap worldwide course downloader
• Realistic driving range telemetry & shot dispersion tracking
• Putting & Chipping practice minigames
• Square Golf Launch Monitor BLE/Serial integration & GSPro Open Connect v1 TCP listener
• AI Golfer Camera swing pose analysis (MediaPipe GPU)
• Dynamic comedic heckle announcer engine

---

## 3. Store Categorization & Tags

- **Application Type:** Game
- **Category:** Sports / Simulation
- **Tags:** Golf, Sports, Physics, Multiplayer, Simulator, Realistic, Casual
- **Target Audience:** 13+ (or 18+)

---

## 4. Required Graphic Assets Checklist

| Asset | Specifications | Notes |
| :--- | :--- | :--- |
| **App Icon** | 512 × 512 px (32-bit PNG, up to 1 MB) | Found at ssets/icons/android/main_192.png or icon.png |
| **Feature Graphic** | 1024 × 500 px (JPEG or 24-bit PNG, no alpha) | Found at ssets/images/heckle_splash.png (resized to 1024x500) |
| **Phone Screenshots** | Min 2 screenshots (16:9 ratio, min 1080p) | Use screenshots from ssets/images/screenshots/ |
| **7-Inch Tablet Screenshots** | Min 1 screenshot (16:9 or 16:10 ratio) | Same as phone screenshots |
| **10-Inch Tablet Screenshots** | Min 1 screenshot (16:9 or 16:10 ratio) | Same as phone screenshots |

---

## 5. Permissions & Data Safety Declarations

| Permission | Google Play Justification / Declaration |
| :--- | :--- |
| **CAMERA** | Used strictly on-device for MediaPipe AI golfer swing tracking and skeletal pose analysis. No video or image data is stored, sent off-device, or shared with third parties. |
| **BLUETOOTH / BLUETOOTH_CONNECT / BLUETOOTH_SCAN** | Used solely to detect and connect to local Square Golf Launch Monitor hardware. |
| **INTERNET / ACCESS_NETWORK_STATE** | Used to download OpenStreetMap real-world course geometries and connect to local network launch monitor TCP bridges (GSPro Open Connect v1). |
