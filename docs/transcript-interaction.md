# Mac transcript interaction regression (#337)

Installed sandbox acceptance on `9bcad27` reproduced a double-click on the budget line selecting
the word instead of opening its editor. Right-clicking text also consumed the surrounding row menu;
the timestamp menu still opened the correct editor. Existing Save/Cancel worked through that menu.
This was found while accepting the delayed-channel transcript fix, not by a scalar model test.

The candidate replaces selectable SwiftUI Text with a read-only native text view that owns both
selection and edit gestures. Double-click on finalized text opens the existing row editor; its
native context menu and accessibility action also offer Edit line. Partial text remains read-only.
The existing editor, correction callback and metadata persistence remain unchanged. Formatting
helpers moved unchanged into `CommandCenterLabels.swift` so the native suite can host the actual row.

`MACEDIT-001` binds four native methods in `MacTranscriptInteractionTests`. Evidence is preserved in
`/Users/tomwu/Documents/Codex/2026-10-28/listentome-edit337/`:

- `native-red.log` reproduced the missing editor in the actual production row (one failed test).
- `native-red3.log` reproduced missing editor/native edit support; partial refusal already passed.
- `native-red2.log` contains a harness compilation error, not a product regression result.
- Early green attempts requested an unadvertised pasteboard format; the corrected test uses the
  native view's advertised types and asserts that only the selected phrase is serialized.
- `native-layout.log` and `native-layout-green.log` exposed overlap and clipping during resize.
  Measurement now uses an independent layout container: SwiftUI's speculative width probes must
  not mutate the displayed text container. These are implementation regressions, not historical reds.
- `native-green4.log`: all four methods passed. Narrow and wide multiline/CJK captures were inspected;
  the adjacent line stays separate and selected text survives an unchanged-text/theme refresh.
- Independent review cleared implementation and test changes, while retaining the distinction
  between programmatic selection serialization and installed pointer-drag selection acceptance.

`make bdd-check` passed 149 scenarios. The signed sandbox build succeeded, with exact identifier
`com.tomwu.ListenToMe.dev`, strict signature verification and sandbox entitlements checked. Its
binary SHA-256 is `552e70701b6c5d96372d1ef90a9d969e39a46f1a5b19f90d8e06ed0880063423`;
`installed/provenance.json` retains the dirty-source input hashes. Native automation reported the
Mac locked before it could open the app. No installed gesture/Copy/Save/Cancel acceptance is claimed.
Full validation, exact-source CI and merge remain required; this change is not published.
