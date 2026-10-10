# AGENTS.md

## Workspace Instructions for AI Assistants (Gemini / Antigravity)

### Automatic App Version Incrementing Rule
Whenever you make changes to this codebase that add features, fix bugs, modify UI, or refactor code:
1. Check the current version in [project.godot](file:///c:/Users/micha/Repositories/HeckleGolfSim/project.godot) (`config/version="X.Y.Z"`).
2. Increment the version number according to Semantic Versioning (`X.Y.Z`):
   - **Patch (`Z`)**: Bug fixes, minor visual adjustments, small refactors (e.g. `0.1.3` -> `0.1.4`).
   - **Minor (`Y`)**: New features, new minigames, new controls, major options (e.g. `0.1.3` -> `0.2.0`).
   - **Major (`X`)**: Full milestone releases or breaking project structural changes (e.g. `0.1.3` -> `1.0.0`).
3. Update versions in project configuration files:
   - Update `config/version` in [project.godot](file:///c:/Users/micha/Repositories/HeckleGolfSim/project.godot).
   - **Google Play Android `version/code` rule**: Whenever a **Major (`X`)** or **Minor (`Y`)** version is updated for the full app version:
     - Automatically increment `version/code` under the Android preset in [export_presets.cfg](file:///c:/Users/micha/Repositories/HeckleGolfSim/export_presets.cfg) (e.g. `13` -> `14`).
   - Always keep `version/name` under the Android preset in [export_presets.cfg](file:///c:/Users/micha/Repositories/HeckleGolfSim/export_presets.cfg) synchronized with `config/version` (e.g. `"X.Y.Z"`).
   - Synchronize `application/short_version` and `application/version` in [export_presets.cfg](file:///c:/Users/micha/Repositories/HeckleGolfSim/export_presets.cfg) for macOS and iOS presets to match the new version.
   - (Note: You can run `powershell -ExecutionPolicy Bypass -File .\scripts\tools\bump_version.ps1 -Minor` / `-Patch` / `-Major` to perform this automatically).
   - Update `version` in [addons/openfairway/plugin.cfg](file:///c:/Users/micha/Repositories/HeckleGolfSim/addons/openfairway/plugin.cfg) if modified.
4. Inform the user of both the new app version (`config/version`) and the Google Play version code (`version/code`) in your response summary.

### Token & Execution Efficiency Rules
1. **Targeted File Inspection (Always Slice File Views)**:
   - Always slice file reads using `StartLine` and `EndLine` in `view_file` to examine only relevant methods, blocks, or line ranges.
   - Do NOT load full files into context unless the file is under 50 lines or full content is strictly necessary.
   - Find relevant ranges using concise search commands (`Select-String`, grep) rather than opening whole files.

2. **Quiet Terminal & Command Outputs**:
   - Always use quiet or minimal flags for build tools, package managers, and CLI utilities (e.g., `--quiet`, `-q`, `--verbosity quiet`, `--nologo`).
   - Filter or truncate verbose terminal output (e.g., pipe to `Select-Object -First`, `findstr`, or specific queries) to prevent noisy log dumps from polluting context.

3. **Targeted Testing & Execution Restrictions**:
   - **Do NOT run the full project unit test suite** unless explicitly asked by the user.
   - **Do NOT launch or run the application** (e.g., Godot runtime or game instances) unless explicitly asked by the user.
   - **Targeted validation only**: When implementing features or bugfixes, add appropriate new tests and run **only** the specific newly added or modified test(s) to validate functionality.
   - Avoid repetitive, redundant full-suite test cycles.

