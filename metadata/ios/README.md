# iOS listing metadata

App: **Listen To Me** · App Store Connect ID `6811155732` · bundle `com.tomwu.ListenToMe.ios`.
The primary locale is English (Canada), `en-CA`.

These files are source-controlled copy, not an automatic upload. Saving them in Git does not update
App Store Connect. Apply and verify the online fields during the iOS release workflow:

| File in `en-CA/` | App Store Connect destination |
| --- | --- |
| `name.txt`, `subtitle.txt` | Distribution → App Information |
| `description.txt`, `keywords.txt` | Distribution → current iOS App Store version |
| `beta-description.txt` | TestFlight → Test Information → Beta App Description |
| `what-to-test-<version>.txt` | TestFlight → matching build → What to Test |

The store description tracks the current shipped iOS build. The first public release is configured to
be free in all available countries, as requested by the maintainer. Submission and availability must be
verified separately from metadata preparation and TestFlight upload; a successful TestFlight upload does
not establish App Store submission. Do not mark a candidate uploaded or tested on a physical device
until that is verified.

Public support page: <https://github.com/tomqwu/ListenToMe/blob/main/docs/ios-support.md>
([`docs/ios-support.md`](../../docs/ios-support.md))

Privacy policy: <https://github.com/tomqwu/ListenToMe/blob/main/docs/ios-privacy.md>
([`docs/ios-privacy.md`](../../docs/ios-privacy.md))

Both URLs are also linked from the app in More → Settings → Privacy. App Review contact details remain
in App Store Connect and are not checked into Git.

## Icon

The shared purple waveform brand is already configured as the iOS AppIcon asset:
[`AppIcon.png`](../../iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png).
It is a 1024 × 1024 opaque PNG. Xcode includes it in the app and Apple receives it with the uploaded
build; it is not a separate TestFlight description attachment. Verify the archive's primary icon
is `AppIcon`, then check the processed build and the installed Home Screen icon.

Apple instructions: [app icons](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon)
and [TestFlight descriptions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information).
