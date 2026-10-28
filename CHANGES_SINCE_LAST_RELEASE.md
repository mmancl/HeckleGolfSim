### Improvements
- Low graphics quality trees now feature a dedicated, clean stylized cartoon look with toon cel shading and smooth wood tones that harmonize with the low-poly stippled turf and stylized water.
- Disabled tall grass and shoreline reeds around water hazards on Low graphics quality to maintain a clean, lightweight visual presentation and improve performance.
- Removed bushes and low shrubbery from the driving range to ensure an unobstructed, clean outfield.

### Bug Fixes
- Fixed a crash when opening the Custom Course Creator caused by a duplicate `_exit_tree` method declaration.
- Fixed a GDScript parser type inference error on `rel_vec` during custom course generation.
- Fixed an issue where trees and bushes were occasionally placed directly on or too close to cart paths during course generation.
- Fixed an issue where random pin placement was ignored and placed the pin in the center of the green on every hole.
- Fixed an issue where gimme circles on the minimap extended past the putting surface into the fringe and rough; gimme circles across all camera views (3D, aerial, and minimap) now strictly conform to the green boundary.
- Fixed an issue where balls coming to rest off the green (such as on the collar, fringe, bunker, or rough) were incorrectly awarded gimmes; gimmes are now strictly confined to balls that come to rest on the green.
- Fixed an issue where the club selection button rendered on top of modal popups (such as the shot analysis and swing replay modal, previous shot details, and confirmation dialogs). Modals now consistently display in front of all HUD elements.
- Fixed an issue where downloading a course could pull in holes from neighboring golf courses located nearby (such as Little Haven pulling in Hole 15 from adjacent Hilly Haven); course boundary matching now strictly differentiates adjacent facilities, ensuring courses only import their own holes and golf features.
- Fixed an issue where textured elevated deep rough grass did not always appear when hitting from heavy rough with 25%+ ball lie resistance; deep rough textures and 3D blade fields now consistently render whenever a lie has 25% or more resistance across all game modes, course types, and tree-lined areas.
