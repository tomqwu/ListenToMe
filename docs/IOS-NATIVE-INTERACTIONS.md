# Native iOS conversation actions

History uses a SwiftUI List with system swipe actions, a context menu, system confirmation alerts
and the iOS activity sheet. The whole row opens its conversation. A chevron communicates navigation;
a short footer makes the gestures discoverable. Persistent trash icons were removed from the rows.

- Leading edge / swipe right: Share, tinted with the app accent.
- Trailing edge / swipe left: Delete, red, followed by confirmation.
- Touch and hold: Share, **Export as** (Markdown, plain text, SRT, WebVTT or JSON; #130), **Share audio**
  when the conversation has saved audio (#55), and Delete.
- VoiceOver: named Share and Delete actions on the row.
- **Delete all conversations…** (#220) sits at the bottom of the list (hidden while a search is typed)
  and asks first, naming the count.

Full-swipe execution is disabled. The swipe Delete button opens confirmation without applying
SwiftUI's immediate destructive-row removal animation. The confirmation's Delete action is destructive.
Cancel preserves the row. The system share sheet receives the selected record's text, including
its transcript, notes, all saved AI outputs and attachment names. Original attachment bytes remain
available through Notes → Attachment actions → Share original.

Implementation follows Apple's [SwiftUI swipe actions API](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:)).
The system supplies gesture animation, symbols, menus, sheets and appearance adaptation.

## Automatic Quick Summary

The Auto switch remains opt-in, with its value persisted on this device. The panel explains whether
Auto is off, waiting for speech or another response, updating, up to date, unavailable, or retrying.
Auto needs Ollama, a cloud AI service or an OpenAI-compatible server (not Apple Intelligence), and the
Auto control names where it sends speech (`summaryEndpointLabel`). A failure preserves the previous output
and shows the error in the Quick Summary panel.

After any summary request, the scheduler rechecks at the remaining automatic cooldown. If a response
took longer than the 15-second interval, changed speech can be summarized immediately. Unchanged
successful input is not resent. Failed input can retry. Leaving the Live tab does not stop scheduling.

## Verification

MobileNativeInteractionTests drives the real meeting view: Start listening, synthetic speech, automatic
updates across tabs, Auto opt-in/off, visible failure/retry, swipe Share → Copy, swipe Delete → Cancel,
and long-press Delete → confirmation → empty History. MobileAutomaticSummaryTests drives the actual
session Start/Stop callbacks and holds a response beyond the cooldown, then requires catch-up within
one second without a new speech callback. It also verifies selected-record and legacy text exports
without mutating the current session. Existing persistence/deletion tests cover relaunch behavior.

Simulator screenshots and test results are kept under `dist/ios-1.6.0-build14-evidence/`.
Synthetic recorder/provider fixtures are compiled only for Debug simulator builds. They do not
establish physical microphone or Apple Intelligence acceptance, or exercise a live cloud endpoint.
No provider transport or authentication code changed in this release.
