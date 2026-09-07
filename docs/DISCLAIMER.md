# Legal Disclaimers & Notices

## 1. Hardware Non-Affiliation & Independent Project Notice
**Heckle Golf Simulator** is an independent, community-driven, open-source personal project. It is **NOT** affiliated with, endorsed by, sponsored by, authorized by, or in any way officially connected with:
- **Square Golf** / **SquareGolf Co., Ltd.**
- **GSPro** / **FlightPath Golf LLC**
- **Garmin Ltd.** (Garmin Approach R10)
- **PiTrac**
- **SkyTrak** / **SkyTrak LLC**
- **Bushnell Golf** / **Bushnell Holdings Inc.** (Launch Pro)
- **Foresight Sports**
- **TrackMan A/S**
- **FlightScope**
- **Rapsodo Inc.**
- **Full Swing Golf**
- **Uneekor**
- Or any of their respective subsidiaries, parent companies, or affiliates.

---

## 2. Trademarks & Nominative Fair Use
All product names, trademarks, registered trademarks, logos, and brand names referenced in this software, documentation, and repository are the property of their respective owners. 

The use of these names (such as *"Square Golf Launch Monitor"*, *"Garmin R10"*, or *"GSPro Open Connect v1"*) is strictly for technical identification, compatibility description, and interoperability purposes under nominative fair use principles.

---

## 3. Clean-Room Interoperability & Protocol Implementation
Device communication in Heckle Golf Simulator is implemented using standard, open wireless **Bluetooth Low Energy (BLE) GATT** services and local **TCP/IP socket network streams**:
- **No proprietary manufacturer software, binary drivers, decompiled copyrighted source code, firmware dumps, or official SDKs** are packaged, copied, or distributed with this repository.
- Network and Bluetooth packet parsing routines are clean-room implementations designed solely to enable interoperability between user-owned hardware devices and the open-source simulator in accordance with US Copyright Law (*Sega Enterprises Ltd. v. Accolade, Inc.*, 977 F.2d 1510; *Sony Computer Entertainment, Inc. v. Connectix Corp.*, 203 F.3d 596) and Section 1201(f) of the Digital Millennium Copyright Act (DMCA).

---

## 4. Course Geometry & OpenStreetMap Data
- **OpenStreetMap Data**: Course vector geography, hole paths, green perimeters, hazards, and layout metadata are queried dynamically from the OpenStreetMap project. OpenStreetMap data is licensed under the [Open Data Commons Open Database License 1.0 (ODbL)](https://opendatacommons.org/licenses/odbl/) by the OpenStreetMap Foundation. © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright).
- **Elevation Geodata**: Terrain elevation arrays are derived from public domain US Geological Survey (USGS 3DEP) data and AWS Terrain Tiles / Mapzen Terrarium open data.
- **Factual Real-World Geometry**: Physical golf course layouts, hole lengths, par ratings, and geographic contours represent factual geographic data not subject to copyright.
- **Course Names**: The names of real-world golf clubs, resorts, and courses are queried directly from open geographic databases and used purely as factual geographic location references. Heckle Golf Simulator claims no affiliation with, endorsement from, or sponsorship by any golf club, course architect, resort, or governing organization (including the USGA, The R&A, or the PGA TOUR).

---

## 5. Announcer Commentary, Humor & Homage
- **Original Content**: All announcer voice lines, jokes, roasts, and commentary scripts are original creative works and comedic parodies created for Heckle Golf Simulator.
- **Parody & Homage**: Any stylistic references to classic PlayStation 2 era golf video games serve purely as an artistic homage and nostalgic inspiration to the arcade golf genre. This project does not use or redistribute any proprietary audio recordings, sound effects, musical scores, or trademarked characters belonging to Sony Interactive Entertainment, Electronic Arts, or any commercial game publisher.

---

## 6. Open-Source Licenses & Mandatory Attributions
Heckle Golf Simulator utilizes open-source components under permissive licenses:
- **Godot Engine**: MIT License. Copyright © 2014-present Godot Engine contributors; Copyright © 2007-2014 Juan Linietsky, Ariel Manzur.
- **OpenFairway**: MIT License. Realistic Reynolds-number golf ball aerodynamics and rollout physics engine by Jesse Inman and Jakobi.
- **OpenShotGolf**: MIT License. Base repository architecture by jhauck2.
- **Jolt Physics 3D**: MIT License. Advanced 3D physics solver by Jorrit Rouwe.
- **Google MediaPipe & TensorFlow.js**: Apache License 2.0. Copyright © Google LLC.
- **Sky3D Plugin & Textures**: Sky3D by Cory Petkovsek & J. Cuéllar (MIT License).
  - *Milky Way Texture*: *"The Milky Way panorama"* by ESO/S. Brunier, licensed under [Creative Commons Attribution 4.0 (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/) and used in original and modified forms ([ESO Image Archive](https://www.eso.org/public/images/eso0932a/)).
  - *Moon Texture*: Copyright © 2019 GPoSM (MIT License).
- **Terrain3D**: MIT License by Cory Petkovsek, Roope Palmroos, and Contributors.
- **Phantom Camera**: MIT License by Marcus Skov.
- **PBR Textures & Low-Poly Foliage**: Textures sourced from [ambientCG.com](https://ambientcg.com/) and Shapespark low-poly exterior plants, dedicated to the public domain under [Creative Commons CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).
- **Music & Soundtracks**: Minigame sound loop tracks: Music from #Uppbeat (free for Creators!):
  - *8beatz* (by 21 On The Block): [https://uppbeat.io/t/21-on-the-block/8beatz](https://uppbeat.io/t/21-on-the-block/8beatz)
  - *Boogie* (by Pecan Pie): [https://uppbeat.io/t/pecan-pie/boogie](https://uppbeat.io/t/pecan-pie/boogie)

---

## 7. Privacy & Local Data Storage
- **100% Local Storage**: All user profiles, handicaps, player names, optional email addresses, and shot statistics are stored strictly on your local device.
- **No Cloud Database or Remote Telemetry**: Heckle Golf Simulator does not operate external database servers or track user data remotely.
- **User-Controlled Email Export**: When exporting scorecards or session data, the Application generates a local file (`.csv` / `.eml`) and requests the operating system to open your default email client. No emails are transmitted in the background, and users retain complete control over sending and recipient selection.
- For complete details, see our [Privacy Policy](file:///c:/Users/micha/Repositories/HeckleGolfSim/PRIVACY.md).

---

## 8. Physical Safety & Health Warning
Golf simulation involves swinging real physical golf clubs and striking golf balls at high velocities:
- **Always verify surrounding clearances**: Ensure adequate ceiling height, side clearance, and depth in your simulator enclosure.
- **Impact protection**: Use proper, tested golf impact screens, netting, and enclosure padding. Ensure no ricochet path exists toward humans, pets, windows, or electronics.
- **Spectator safety**: Keep all spectators, pets, and children safely outside the club swing path and ball trajectory.
- The developers and contributors accept **NO responsibility or liability** for any bodily injury, property damage, structural damage, hardware malfunction, or broken clubs/screens occurring during the use of this software.

---

## 9. Disclaimer of Warranties & Limitation of Liability
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## 10. Intellectual Property Inquiries & Contact
Heckle Golf Simulator is committed to full compliance with all open-source licenses and respectful treatment of intellectual property rights. 

If you are a copyright or trademark owner with any questions, licensing inquiries, or feedback regarding materials in this repository, please open an issue or start a discussion on our [GitHub repository](https://github.com/mmancl/HeckleGolfSim/issues) so that we can promptly review and address your communication in good faith.
