#!/usr/bin/env bash
# ============================================================================
#  build.sh
#  ---------------------------------------------------------------------------
#  One-shot wrapper around `xcodebuild` that:
#    1. Resolves SPM packages (so CocoaLumberjack.swift is on disk)
#    2. Patches the local CocoaLumberjack 3.8.5 source for Xcode 26 compat
#    3. Runs the actual build with ad-hoc signing
#
#  Use this instead of bare `xcodebuild` until upstream ships a CocoaLumberjack
#  version that builds cleanly under Xcode 26 (probably 3.9.1 once they
#  actually publish the SPM 6.0 fix).
#
#  Usage:
#      ./scripts/build.sh           # Release build, ad-hoc signed
#      ./scripts/build.sh Debug     # Debug build
#
#  The .app lands at build/Build/Products/Release/Mac Mouse Fix.app (or
#  Debug/...).
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-Release}"
echo "==> Config: $CONFIG"

# 1. Resolve SPM packages (creates build/SourcePackages/checkouts/).
echo "==> Resolving SPM packages..."
xcodebuild \
    -project "Mouse Fix.xcodeproj" \
    -scheme "App - Release" \
    -configuration "$CONFIG" \
    -derivedDataPath ./build \
    -resolvePackageDependencies

# 2. Patch CocoaLumberjack for Xcode 26. Idempotent.
echo "==> Patching CocoaLumberjack for Xcode 26..."
SPM_TARGET="build/SourcePackages/checkouts/CocoaLumberjack/Sources/CocoaLumberjackSwift/CocoaLumberjack.swift"
if [ -f "$SPM_TARGET" ]; then
    ./scripts/patch-cocoalumberjack.sh "$SPM_TARGET"
else
    echo "WARN: $SPM_TARGET not found after resolve — skipping patch." >&2
fi

# 3. Build.
echo "==> Building..."
xcodebuild \
    -project "Mouse Fix.xcodeproj" \
    -scheme "App - Release" \
    -configuration "$CONFIG" \
    -derivedDataPath ./build \
    -destination 'generic/platform=macOS' \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    PROVISIONING_PROFILE_SPECIFIER="" \
    DEVELOPMENT_TEAM="" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS="FORCE_LICENSED" \
    GCC_PREPROCESSOR_DEFINITIONS='$(inherited) DISABLE_UPDATES=1' \
    ENABLE_HARDENED_RUNTIME=NO \
    build

# 4. Locate the .app and tell the user.
APP="build/Build/Products/$CONFIG/Mac Mouse Fix.app"
echo
echo "==> Build complete."
if [ -d "$APP" ]; then
    echo "    App bundle: $(pwd)/$APP"
    echo
    echo "Next steps:"
    echo "  1.  cp -R '$APP' /Applications/"
    echo "  2.  xattr -dr com.apple.quarantine /Applications/Mac\\ Mouse\\ Fix.app"
    echo "  3.  open /Applications/Mac\\ Mouse\\ Fix.app"
    echo "      (or right-click → Open the first time to clear Gatekeeper)"
    echo "  4.  Grant Accessibility + Background Items in System Settings."
else
    echo "    ERROR: $APP not found. See build log above." >&2
    exit 1
fi
