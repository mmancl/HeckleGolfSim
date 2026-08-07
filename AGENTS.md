# AGENTS.md

## Workspace Instructions for AI Assistants (Gemini / Antigravity)

### Automatic App Version Incrementing Rule
Whenever you make changes to this codebase that add features, fix bugs, modify UI, or refactor code:
1. Check the current version in [project.godot](file:///c:/Users/micha/Repositories/HeckleGolfSim/project.godot) (`config/version="X.Y.Z"`).
2. Increment the version number according to Semantic Versioning (`X.Y.Z`):
   - **Patch (`Z`)**: Bug fixes, minor visual adjustments, small refactors (e.g. `0.1.3` -> `0.1.4`).
   - **Minor (`Y`)**: New features, new minigames, new controls, major options (e.g. `0.1.3` -> `0.2.0`).
   - **Major (`X`)**: Full milestone releases or breaking project structural changes (e.g. `0.1.3` -> `1.0.0`).
3. Update `config/version` in `project.godot` (and `version` in `addons/openfairway/plugin.cfg` if modified).
4. Inform the user of the new version number in your response summary.
