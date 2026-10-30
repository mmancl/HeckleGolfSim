### New Features
- **Shot tracking diagrams in Match History:** The history scorecard now includes a full Shot Review section. After opening a match's scorecard from Match History, scroll down to see per-player shot path diagrams for every hole — just like the in-round scorecard. Select any hole using the hole-number buttons to instantly view each player's shot path, distances, and satellite overlay for that hole.

### Improvements
- Fixed putting green slope grid and gimme circle placement so they lie flat against the green turf rather than floating in mid-air. Grid lines now follow the green's natural contours closely, and gimme circles properly respect 3D depth against the ball, cup, and surrounding terrain.
- Fixed an issue on the Driving Range where tall 3D rough grass appeared and balls landing outside the center corridor suffered shot reduction penalties and rough lie resistance; all balls on the driving range now always register as on the tee box with 0% resistance, and tall rough grass clumps are completely removed for an open, clean outfield.
- Low graphics quality trees now feature a dedicated, clean stylized cartoon look with toon cel shading and smooth wood tones that harmonize with the low-poly stippled turf and stylized water.
- Disabled tall grass and shoreline reeds around water hazards on Low graphics quality to maintain a clean, lightweight visual presentation and improve performance.
- Removed bushes and low shrubbery from the driving range to ensure an unobstructed, clean outfield.
- Short shots under 20 yards (such as tap-in putts and chip-outs) no longer display a line or distance label on the shot overview diagram in the scorecard, keeping the map clean and focused on meaningful shot paths.
- The blue aim reticle circle is no longer shown when aiming on the putting green, keeping the view clean for putting. The distance card and guideline still display normally.
- **iOS File Sharing & In-Game Log Copy:** Enabled native iOS document and file sharing (`UIFileSharingEnabled`), allowing players to view and copy diagnostic log files directly from the iOS Files app (under "On My iPhone / iPad" -> "Heckle Golf Simulator") or via Mac/PC file sharing. Added a one-tap "Copy Full Log" button in Developer Settings to instantly copy all engine and diagnostic logs to the device clipboard.
- **Improved Course Download Reliability & Server Mirrors:** Updated OpenStreetMap course downloading to utilize high-speed, modern global Overpass API mirrors (including OpenStreetMap France, Kumi Systems, and Private.coffee) while removing deprecated subdomains that previously caused downloads to hang or time out.

### Bug Fixes
- Fixed an issue where the ball could be teed up on subsequent shots if it came to rest inside a tee box area; teeing up the ball (with elevated tee peg) is now strictly restricted to the player's first shot on a hole (0 strokes taken), and balls landing on any tee box thereafter are played from the turf.
- Fixed an issue where switching clubs on the driving range did not clear the current active shot tracers from the field.
- Prevented bushes from spawning in front of tee boxes and in the flight corridor towards fairways, and ensured course bushes cluster naturally around trees.
- Fixed a crash when opening the Custom Course Creator caused by a duplicate `_exit_tree` method declaration.
- Fixed a GDScript parser type inference error on `rel_vec` during custom course generation.
- Fixed an issue where trees and bushes were occasionally placed directly on or too close to cart paths during course generation.
- Fixed an issue where random pin placement was ignored and placed the pin in the center of the green on every hole.
- Fixed an issue where gimme circles on the minimap extended past the putting surface into the fringe and rough; gimme circles across all camera views (3D, aerial, and minimap) now strictly conform to the green boundary.
- Fixed an issue where balls coming to rest off the green (such as on the collar, fringe, bunker, or rough) were incorrectly awarded gimmes; gimmes are now strictly confined to balls that come to rest on the green.
- Fixed an issue where gimmes were calculated against the default center of the green rather than the actual cup location when random pin placement was enabled; gimme awards, distance measurements, and visual rings now stay perfectly synchronized with the active pin.
- Fixed an issue where the club selection button rendered on top of modal popups (such as the shot analysis and swing replay modal, previous shot details, and confirmation dialogs). Modals now consistently display in front of all HUD elements.
- Fixed an issue where downloading a course could pull in holes from neighboring golf courses located nearby (such as Little Haven pulling in Hole 15 from adjacent Hilly Haven); course boundary matching now strictly differentiates adjacent facilities, ensuring courses only import their own holes and golf features.
- Fixed an issue where textured elevated deep rough grass did not always appear when hitting from heavy rough with 25%+ ball lie resistance; deep rough textures and 3D blade fields now consistently render whenever a lie has 25% or more resistance across all game modes, course types, and tree-lined areas.
- Fixed an issue where newly downloaded or custom-created courses triggered an unnecessary "Upgrading Downloaded Courses" progress popup on game startup; downloaded courses now generate directly with the latest graphics settings and version stamp, avoiding redundant startup course upgrades.
- Fixed a crash on iOS when opening the Settings menu caused by native desktop file dialog hooks attempting to run on mobile.
- Fixed an issue where OpenStreetMap course downloads timed out with "OverPass API request timed out after multiple retries" due to decommissioned API endpoints.
