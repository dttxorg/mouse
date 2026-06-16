#!/usr/bin/env bash
# ============================================================================
#  patch-reactivecocoa.sh
#  ---------------------------------------------------------------------------
#  Patches the local ReactiveCocoa 12.0.0 SPM checkout so it builds under
#  Xcode 26. Same root cause as CocoaLumberjack: Swift 6 strict-concurrency
#  + cross-module C-const interop is broken.
#
#  The C const / function references are rewritten to use the public ObjC
#  runtime API directly, so the build doesn't depend on the C-const import
#  being visible from Swift.
#
#  Idempotent.
# ============================================================================
set -euo pipefail

SRC_ROOT="${1:-$HOME/Library/Developer/Xcode/DerivedData}"
# Try common locations
for CAND in \
    "build/SourcePackages/checkouts/ReactiveCocoa/ReactiveCocoa" \
    "$SRC_ROOT/Mouse_Fix"*/SourcePackages/checkouts/ReactiveCocoa/ReactiveCocoa; do
    if [ -d "$CAND" ]; then
        DIR="$CAND"
        break
    fi
done

if [ -z "${DIR:-}" ] || [ ! -d "$DIR" ]; then
    echo "Error: could not find ReactiveCocoa/ReactiveCocoa source dir" >&2
    echo "Pass the path as first argument." >&2
    exit 1
fi

MARKER="// PATCH_APPLIED_dttxorg_2026_06_17"
NEEDS_PATCH=0
for F in "$DIR/NSObject+Association.swift" "$DIR/NSObject+Intercepting.swift" "$DIR/ObjC+RuntimeSubclassing.swift"; do
    if [ ! -f "$F" ]; then continue; fi
    if ! grep -q "$MARKER" "$F"; then
        NEEDS_PATCH=1
        break
    fi
done
if [ "$NEEDS_PATCH" = "0" ]; then
    echo "Already patched: $DIR"
    exit 0
fi

chmod u+w "$DIR"/*.swift

python3 - "$DIR" <<'PY'
import sys, re
dir_ = sys.argv[1]
marker = "// PATCH_APPLIED_dttxorg_2026_06_17"

# ---- File 1: NSObject+Association.swift ----
# Original (line 134):
#   _rac_objc_setAssociatedObject(address, key.address, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
# Rewrite to:
#   objc_setAssociatedObject(Unmanaged<AnyObject>.fromOpaque(address).takeUnretainedValue(),
#                            key.address,
#                            value,
#                            .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
# But that's gnarly. Actually the function is just a wrapper that does
# exactly this. The simpler rewrite: just use objc_setAssociatedObject directly.

p = f"{dir_}/NSObject+Association.swift"
with open(p) as f: src = f.read()
old = "_rac_objc_setAssociatedObject(address, key.address, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)"
new = (
    "objc_setAssociatedObject("
    "unsafeBitCast(address, to: AnyObject.self), "
    "key.address, "
    "value, "
    ".OBJC_ASSOCIATION_RETAIN_NONATOMIC)"
)
if old in src:
    src = src.replace(old, new)
else:
    print(f"WARN: pattern not found in {p}")
src = marker + "\n" + src if marker not in src else src
with open(p, "w") as f: f.write(src)
print(f"  Patched: {p}")

# ---- Files 2-3: NSObject+Intercepting.swift + ObjC+RuntimeSubclassing.swift ----
# Original: method_getImplementation(method) == _rac_objc_msgForward
# _rac_objc_msgForward is just `const IMP = _objc_msgForward`
# So rewrite to compare against _objc_msgForward directly via unsafeBitCast.

for fname in ("NSObject+Intercepting.swift", "ObjC+RuntimeSubclassing.swift"):
    p = f"{dir_}/{fname}"
    if not os.path.exists(p) if False else True:  # pythonic guard
        pass
    with open(p) as f: src = f.read()
    # Wrap each comparison
    # We add a private IMP helper that reads _objc_msgForward lazily.
    if "_rac_objc_msgForward" not in src:
        continue
    # Replace `== _rac_objc_msgForward` and `?? _rac_objc_msgForward`
    src = src.replace("== _rac_objc_msgForward", "== ReactiveCocoaObjC_Private.msgForward")
    src = src.replace("?? _rac_objc_msgForward", "?? ReactiveCocoaObjC_Private.msgForward")
    # Add helper at top (after imports)
    helper = """

// PATCH [dttxorg]: Swift 6 strict-concurrency can't see the extern const
// _rac_objc_msgForward from the ReactiveCocoaObjC C header. Look it up
// lazily from the public ObjC runtime. Safe to call repeatedly.
private enum ReactiveCocoaObjC_Private {
    static let msgForward: IMP = {
        // _objc_msgForward is the public ObjC runtime symbol; we resolve
        // it via dlsym to avoid the same Swift 6 cross-module C-const issue.
        typealias MsgForwardFn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>!
        let handle = dlopen(nil, RTLD_NOW)
        let sym = dlsym(handle, "_objc_msgForward")
        return unsafeBitCast(sym, to: IMP.self)
    }()
}
"""
    if "ReactiveCocoaObjC_Private" not in src:
        # Insert after the last import line
        lines = src.split("\n")
        last_import = 0
        for i, line in enumerate(lines):
            if line.startswith("import "):
                last_import = i
        lines.insert(last_import + 1, helper)
        src = "\n".join(lines)
    with open(p, "w") as f: f.write(src)
    print(f"  Patched: {p}")

print("Done.")
PY

echo "Patched: $DIR"
