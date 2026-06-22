# Progress: Sideload Smartponic V2 on iPhone

**Last updated:** 2026-06-20
**Branch:** `dev-optimization` (on `Smart-Communication-Framework`)
**Remote repo:** `hyelif/Smart-Communication-Framework.git`
**Build platform:** Codemagic
**Sideload tool:** AltStore

---

## ✅ What's Done

- [x] Flutter project analyzed — **0 errors**, 29 style hints only
- [x] `codemagic.yaml` created at repo root — builds debug, packages `.ipa`
- [x] `NSLocationWhenInUseUsageDescription` added to Info.plist (for `geolocator`)
- [x] `DEVELOPMENT_TEAM = AAAAAAAAAA` dummy placeholder in project.pbxproj Debug config (satisfies Flutter 3.11 validation)
- [x] `import 'package:flutter/cupertino.dart'` added to app_theme.dart (fixes `CupertinoPageTransitionsBuilder`)
- [x] AltStore installed on iPhone 14 Pro (iOS 26.4)
- [x] Latest working code committed & pushed to `dev-optimization`

---

## ❌ Remaining Problem: App crashes on launch

**Symptom:** White screen for ~1 second → app force closes.
**iPhone:** 14 Pro, iOS 26.4
**How build was done:** Codemagic via `codemagic.yaml` with `--no-codesign`

### Root Cause Analysis

The white screen means the Flutter engine **does** start (UIKit loads, main() runs), but something fails immediately at the native level. Three possible causes:

| Cause | Likelihood | Explanation |
|-------|-----------|-------------|
| **1. Code still has errors** | Medium | The build that crashed used old `ios-testing` branch code (286 VS Code issues). We fixed the Cupertino import and pushed clean code — a rebuild is needed to test. |
| **2. `--no-codesign` corrupts framework structure** | High | `--no-codesign` tells Xcode to skip embedding code-signing structures in `Flutter.framework` and `App.framework`. When AltStore re-signs the .ipa, these frameworks may not get proper signing slots → Flutter engine loads then crashes trying to link. |
| **3. Missing or broken framework symlinks in .ipa** | Low | Already fixed with `cp -Rp` in the packaging step. |

### Theory on Fix (not yet tested)

The cleanest fix is probably to drop `--no-codesign` entirely. Instead:

1. Set `DEVELOPMENT_TEAM` to a real or dummy value
2. Build normally (Xcode will sign with the dummy team)
3. The `.app` will have **properly structured** `Flutter.framework` with valid code-signing slots
4. AltStore will strip the dummy signature and replace it with its own

The concern was that Flutter would reject a build without a real Apple Developer team. But `AAAAAAAAAA` already satisfied Flutter's validation — the question is whether Xcode will actually sign an `.app` with it. If yes, AltStore should have no problem re-signing it.

### Alternative: Switch to Sidestore.io

If AltStore keeps having issues with `--no-codesign` builds, an alternative is [SideStore](https://sidestore.io/) — it's AltStore-compatible but open source and handles some edge cases better.

---

## 🔜 Next Steps

1. **Rebuild on Codemagic** with current `dev-optimization` (after Cupertino fix)
2. If it still crashes → try building **without** `--no-codesign` (let Xcode sign with dummy team)
3. If still crashes → try `flutter build ios --debug --no-codesign` + use `ditto` instead of `cp` for packaging
4. Last resort → SideStore or Apple Developer Program ($99/year)

---

## Troubleshooting

| Problem | Likely Fix |
|---------|-----------|
| White screen → crash | Try building without `--no-codesign` (see theory above) |
| AltServer can't find iPhone | Reinstall iTunes from Apple's site (not MS Store) |
| "Untrusted Developer" | Settings > General > VPN & Device Management → Trust |
| 7-day expiry | Refresh in AltStore before day 7 |