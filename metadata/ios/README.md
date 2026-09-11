# iOS listing metadata

App: **Listen To Me** · App Store Connect ID `6811155732` · bundle `com.tomwu.ListenToMe.ios`.
The primary locale is English (Canada), `en-CA`.

These files are source-controlled copy, not an automatic upload. Saving them in Git does not update
App Store Connect. Apply and verify the online fields during the iOS release workflow:

| File in `en-CA/` | App Store Connect destination |
| --- | --- |
| `name.txt` | Distribution → App Information → Name |
| `subtitle.txt` | Distribution → App Information → Subtitle |
| `description.txt` | Distribution → iOS version 1.2.0 → Description |
| `beta-description.txt` | TestFlight → Test Information → Beta App Description |
| `what-to-test-1.1.0.txt` | TestFlight → build 1.1.0 (3) → What to Test |
| `what-to-test-1.2.0.txt` | TestFlight → build 1.2.0 (5) → What to Test |

The full store description targets 1.2.0. The beta description explicitly identifies the version
that adds Ollama so it remains accurate while testers still have 1.0.1. Do not mark a candidate
uploaded or tested on a physical device until that is verified. Contact and privacy fields require
the maintainer's actual details and are not supplied by these files.

## Icon

The shared purple waveform brand is already configured as the iOS AppIcon asset:
[`AppIcon.png`](../../iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png).
It is a 1024 × 1024 opaque PNG. Xcode includes it in the app and Apple receives it with the uploaded
build; it is not a separate TestFlight description attachment. Verify the archive's primary icon
is `AppIcon`, then check the processed build and the installed Home Screen icon.

Apple instructions: [app icons](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon)
and [TestFlight descriptions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information).
