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
Full `make validate-local` passed on `d525760`: exit 0, reaped, all 934 tracked inputs unchanged,
including all 69 Mac native tests and four real-server contracts. All three required hosted checks
also passed on that source. [The independently audited receipt](releases/mac-candidate-d525760-validation.json)
records the full matrix. Installed acceptance and merge remain required; this change is not published.

## Installed integrated candidate — October 28, 2026

On signed sandbox source `02528bf`, actual finalized-text double-click, blank Save refusal, Cancel,
accessibility/context Edit, single-line Save/restoration, pointer and keyboard/menu Copy and narrow/
wide reflow were exercised. Independent visual/AX review supports the recorded visible outcomes;
action sequences rely on the retained operator record. Six visible synthetic rows kept their content
except the temporary selected budget correction, which was restored. This does not establish disk
persistence across relaunch, VoiceOver speech or delayed-row saved-audio playback.

[The bounded installed receipt](releases/mac-candidate-02528bf-installed.json) retains screenshot
hashes, source/signature provenance and limitations. The original CUA captures are JPEG bytes and
were renamed without changing them; they are QA evidence, not App Store media. The completed Dev
bundle was archived, stopped and moved to Trash; only `com.tomwu.ListenToMe.dev` permissions were
reset. Full integrated validation separately failed in the Settings test and is being corrected
with [explicit failure evidence](validation-pipeline-recovery.md). #336's remaining acoustic/route/
playback acceptance and merge are still required; no publication is established.
