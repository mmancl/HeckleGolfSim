#!/usr/bin/env bash
# ==============================================================================
# Heckle Golf Simulator - macOS / iOS Build Script
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

echo "======================================================="
echo "   Heckle Golf Simulator - iOS Export on macOS         "
echo "======================================================="

VERSION=$(grep 'config/version=' project.godot | cut -d '"' -f 2)
if [ -z "$VERSION" ]; then
    VERSION="0.35.0"
fi
echo "Version: $VERSION"

# 1. Locate Godot
GODOT_BIN=""
for candidate in \
    "$GODOT_BIN" \
    "/Applications/Godot_mono.app/Contents/MacOS/Godot" \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Godot/Godot" \
    "$(which godot 2>/dev/null)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        GODOT_BIN="$candidate"
        break
    fi
done

if [ -z "$GODOT_BIN" ]; then
    echo "[ERROR] Godot 4.7 Mono not found!"
    echo "Please install Godot Mono to /Applications/Godot_mono.app or ensure 'godot' is in your PATH."
    exit 1
fi
echo "Godot: $GODOT_BIN"

# 2. Check .NET SDK
if ! command -v dotnet &>/dev/null; then
    echo "[ERROR] .NET SDK not found. Please install .NET 9 SDK (brew install dotnet or from dot.net)."
    exit 1
fi
echo ".NET: $(dotnet --version)"

# 3. Build C# Solution
echo "Compiling C# .NET solution..."
dotnet build HeckleGolfSim.csproj -c Release

# 4. Check Templates
TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/4.7.stable.mono"
if [ ! -f "$TEMPLATES_DIR/ios.zip" ]; then
    echo "Downloading Godot 4.7 export templates..."
    mkdir -p "$TEMPLATES_DIR"
    TMP_TPZ=$(mktemp /tmp/godot_templates.XXXXXX.zip)
    curl -L --progress-bar -o "$TMP_TPZ" "https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_mono_export_templates.tpz"
    unzip -q "$TMP_TPZ" -d /tmp/godot_templates_extracted
    cp -r /tmp/godot_templates_extracted/templates/* "$TEMPLATES_DIR/"
    rm -rf "$TMP_TPZ" /tmp/godot_templates_extracted
fi

# 5. Export iOS Xcode Project
mkdir -p dist
OUTPUT_ZIP="dist/HeckleGolfSim-iOS-v${VERSION}.zip"
echo "Exporting iOS preset to $OUTPUT_ZIP..."
"$GODOT_BIN" --headless --path "$REPO_ROOT" --export-release "iOS" "$OUTPUT_ZIP"

echo "Export complete: $OUTPUT_ZIP"

# 6. Build and package .ipa if xcodebuild is available
if command -v xcodebuild &>/dev/null; then
    echo "Xcode detected! Compiling Xcode project into .ipa..."
    TMP_XCODE_DIR="/tmp/hecklegolf_xcode_build"
    rm -rf "$TMP_XCODE_DIR"
    mkdir -p "$TMP_XCODE_DIR"
    unzip -q "$OUTPUT_ZIP" -d "$TMP_XCODE_DIR"
    
    XCODEPROJ=$(find "$TMP_XCODE_DIR" -name "*.xcodeproj" -maxdepth 2 | head -n 1)
    SCHEME_NAME=$(xcodebuild -list -project "$XCODEPROJ" | awk '/Schemes:/{flag=1;next}/^$/{flag=0}flag' | head -n 1 | xargs)
    if [ -z "$SCHEME_NAME" ]; then
        SCHEME_NAME="Heckle Golf"
    fi

    echo "Ensuring Bluetooth usage descriptions in iOS Info.plist..."
    find "$TMP_XCODE_DIR" -name "*-Info.plist" -o -name "Info.plist" | while read -r plist; do
        /usr/libexec/PlistBuddy -c "Add :NSBluetoothAlwaysUsageDescription string Heckle Golf Simulator requires Bluetooth to connect to launch monitors like the Square Golf Launch Monitor." "$plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :NSBluetoothAlwaysUsageDescription Heckle Golf Simulator requires Bluetooth to connect to launch monitors like the Square Golf Launch Monitor." "$plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :NSBluetoothPeripheralUsageDescription string Heckle Golf Simulator requires Bluetooth to connect to launch monitors like the Square Golf Launch Monitor." "$plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :NSBluetoothPeripheralUsageDescription Heckle Golf Simulator requires Bluetooth to connect to launch monitors like the Square Golf Launch Monitor." "$plist" 2>/dev/null || true
    done
    
    ARCHIVE_DIR="$TMP_XCODE_DIR/archive.xcarchive"
    xcodebuild -project "$XCODEPROJ" \
      -scheme "$SCHEME_NAME" \
      -configuration Release \
      -destination 'generic/platform=iOS' \
      -archivePath "$ARCHIVE_DIR" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY="" \
      archive
      
    IPA_OUTPUT="dist/HeckleGolfSim.ipa"
    mkdir -p "$TMP_XCODE_DIR/Payload"
    cp -r "$ARCHIVE_DIR/Products/Applications/"*.app "$TMP_XCODE_DIR/Payload/"
    cd "$TMP_XCODE_DIR"
    zip -qr "$REPO_ROOT/$IPA_OUTPUT" Payload
    cd "$REPO_ROOT"
    rm -rf "$TMP_XCODE_DIR"
    
    echo "======================================================="
    echo "[SUCCESS] IPA Package Generated!"
    echo "Output: $IPA_OUTPUT"
    echo "======================================================="
    echo "Ready to upload to Google Drive for Sideloadly / AltStore!"
else
    echo "======================================================="
    echo "[SUCCESS] iOS Export Complete!"
    echo "Output: $OUTPUT_ZIP"
    echo "======================================================="
    echo "To build in Xcode:"
    echo "1. Unzip $OUTPUT_ZIP."
    echo "2. Open the .xcodeproj file in Xcode."
    echo "3. Connect iPhone via USB."
    echo "4. In Signing & Capabilities, select your Personal Team (Apple ID)."
    echo "5. Hit 'Play' / Run to compile and launch directly on your device!"
fi
