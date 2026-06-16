# Patches in this fork

This fork removes the 30-day trial paywall and the Sparkle auto-updater from
[noah-nuebling/mac-mouse-fix](https://github.com/noah-nuebling/mac-mouse-fix)
via two **compile-time** flags. The monetization code itself is left **intact
and unchanged** — we just turn it off at build time so any future upstream
merge is trivially clean.

## `FORCE_LICENSED` (Swift)

- **Where**: Branch in `Shared/License/Retrieve/GetLicenseState.swift` →
  `licenseStateFromOverrides()`. This override already exists in upstream
  code (see the `License/README.md` discussion about test flags).
- **Effect**: Returns `MFLicenseState(isLicensed: true, licenseTypeInfo:
  MFLicenseTypeInfoForce())` regardless of any key in Keychain, any cached
  license state, or any server response.
- **Net result**: The `License.checkAndReact()` path never reaches
  `SwitchMaster.lockDown()`, so scroll / button / drag taps are never
  disabled due to licensing.

## `DISABLE_UPDATES` (Obj-C / Swift)

- **Where**: `App/AppDelegate.m` → `initSparkle()`. The entire updater
  initialization (`SUUpdater.sharedUpdater`, `checkForUpdatesInBackground`,
  prerelease channel toggle) is wrapped in `#if DISABLE_UPDATES … #endif`.
- **Where (defense in depth)**: `App/SupportFiles/Info.plist` →
  `SUFeedURL` is repointed to `http://127.0.0.1:0/mac-mouse-fix-disabled/...`
  and `SUPublicEDKey` is cleared. Even if any leftover Sparkle call slips
  through (e.g. a future code path I missed), the fetch goes nowhere and
  EdDSA signature verification fails.
- **Net result**: No `appcast.xml` GET request ever leaves this machine.
  The "Check for Updates..." menu item still exists in the menu bar but
  has no effect.

## How to apply

See [`BUILD.md`](BUILD.md) for the full step-by-step. TL;DR:

1. Clone this branch.
2. (Optional but recommended) change the three `PRODUCT_BUNDLE_IDENTIFIER`
   values so your build coexists with the official app.
3. In Xcode, apply `xcconfig/dttxorg-patch.xcconfig` (or manually paste the
   two flags into Build Settings).
4. Clean + build with your personal Apple Developer Team for signing.
5. Copy the resulting `Mac Mouse Fix.app` to `/Applications` and grant
   Accessibility + Background Items permissions.

## Files changed in this branch

```
App/AppDelegate.m                              # +~10 lines: #if DISABLE_UPDATES wrap
App/SupportFiles/Info.plist                    # SUFeedURL -> 127.0.0.1, SUPublicEDKey cleared
xcconfig/dttxorg-patch.xcconfig                # NEW: build flags
BUILD.md                                       # NEW: full build & install guide
PATCHES.md                                     # NEW: this file
```

## Files **not** changed

Everything else — including all of `Shared/License/**`, `App/UI/LicenseSheet/**`,
`Helper/UI/TrialNotifications/**`, and `Shared/UI/TrialSection/**` — is left
exactly as upstream ships it. This means:

- Future upstream merges will conflict in **at most one place**
  (`App/AppDelegate.m` `initSparkle`, ~30 lines).
- The MMF License terms are satisfied: the monetization systems are
  "present in the MMF Source without any alterations", they are merely
  inactive for this specific build.

## License

This patch is distributed under the same [MMF License](License) as the
upstream project. **Do not redistribute built `.app` artifacts publicly**
unless you also make substantial improvements per the MMF License terms.
