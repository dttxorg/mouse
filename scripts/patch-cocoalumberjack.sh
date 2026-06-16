#!/usr/bin/env bash
# ============================================================================
#  patch-cocoalumberjack.sh
#  ---------------------------------------------------------------------------
#  Patches the local CocoaLumberjack 3.8.5 SPM checkout so it builds under
#  Xcode 26's stricter Swift 6 cross-module C interop rules.
#
#  Run this ONCE before your first build (or whenever xcodebuild regenerates
#  the SPM cache in build/SourcePackages/).
#
#  Idempotent: running it twice does no harm. If upstream CocoaLumberjack
#  ships a fix (3.9.x), this becomes a no-op.
# ============================================================================
set -euo pipefail

TARGET="$1"
if [ -z "$TARGET" ]; then
    echo "Usage: $0 <path-to-CocoaLumberjack.swift>"
    echo ""
    echo "Most users don't need to call this directly — scripts/build.sh"
    echo "invokes it automatically as part of the build pipeline."
    exit 1
fi

if [ ! -f "$TARGET" ]; then
    echo "Error: file not found: $TARGET" >&2
    echo "Did you run \`xcodebuild -resolvePackageDependencies\` first?" >&2
    exit 1
fi

# Mark with our signature so we know whether we've already patched.
MARKER="// PATCH_APPLIED_dttxorg_2026_06_17"

# Patch both files in the same directory.
DIR="$(dirname "$TARGET")"
for F in "$TARGET" "$DIR/DDAssert.swift"; do
    if [ ! -f "$F" ]; then
        continue
    fi
    if grep -q "$MARKER" "$F"; then
        echo "Already patched: $F"
        continue
    fi
    chmod u+w "$F"
    python3 - "$F" <<'PY'
import sys
path = sys.argv[1]
with open(path) as f:
    src = f.read()

old_pattern = "level: DDLogLevel = DDDefaultLogLevel"
new_pattern = "level: DDLogLevel = .info"
count = src.count(old_pattern)
if count == 0:
    sys.exit("no 'level: DDLogLevel = DDDefaultLogLevel' references found in " + path)
src = src.replace(old_pattern, new_pattern)

marker = "// PATCH_APPLIED_dttxorg_2026_06_17"
# Only insert marker if not already there (DDAssert.swift doesn't have @_exported import CocoaLumberjack line)
if marker not in src:
    # Insert at top of file
    src = marker + "\n" + src

with open(path, "w") as f:
    f.write(src)

print(f"  Rewrote {count} default-argument references in {path}")
PY
done

echo "Patched: $DIR"
