# Translation recovery — #343

The tester screenshot shows Summary translation to Simplified Chinese displaying “Translating…”
while Translate remains available. It does not reveal which native operation stalled. Earlier
tests injected pair readiness and translated output; simulator captures proved controls, not the
Apple engine. The original feature record retained that limitation, but it left this failure untested.

## Behavior change

TestFlight 1.20.2 (42) on iPhone/iPad, and the unreleased Mac source, own the actual `TranslationSession` through completion and forward Cancel to its
native cancellation API. Task cancellation also reaches that same request. Late readiness or text
cannot become a new result. A second native operation is refused until the prior operation exits.

Each text chunk has a 45-second readiness/translation deadline. Prose paragraphs longer than 8,000 characters are split into multiple chunks. Expiry ends the progress indication,
blocks the remaining batch and explains that originals are kept. Cancel immediately ends visible
progress. An uncooperative native operation retains its slot while stopping; controls explain why
retry is temporarily unavailable and advise reopening the app if the service never exits. This
does not pretend the underlying framework can always be forcibly stopped. A cancelled paragraph
timer cannot stop a newer paragraph. Translate and Retry are disabled during work or drainage;
Summary offers an explicit Cancel translation action and preserves readable originals.

No automatic download, cloud fallback, AI-provider change, audio change or new saved data is added.
The same lifecycle applies to live translation; its opt-in and original-transcript ownership remain.

## Reproduced failures and focused checks

- Core stalled-service/cancellation tests: three tests initially produced 17 assertions with the
  behavior-preserving timeout/API scaffold. The completed implementation passes all four recovery
  methods and the 12 existing live/summary tests (16 total, zero failures).
- Independent review found a completion/deadline race. A controlled old timer resumed during the
  next paragraph: one test, four failures before the cancellation/current-input guard; green after.
- Native ownership: six tests, eight genuine assertion failures before cancellation forwarding;
  six pass after. Earlier selector/Swift concurrency/missing-API compile failures are retained as
  harness diagnostics, not regression reds. iOS and Mac bind the same native ownership scenarios.
- Native iPhone simulator controls: one test, two failures (Translate enabled and Cancel missing);
  all five translation UI tests pass after the fix, including Duo, largest text, setup and ready
  states. Three recovery-state screenshots were individually inspected. Held-service fixture
  captures are QA evidence, not store screenshots or native model accuracy evidence.
- A new native Mac test uses the actual Apple adapter and complete summary coordinator. Its
  installed English→Simplified Chinese branch passed in 1.74 seconds, preserving two Chinese
  paragraphs, budget 120, Thursday, original text and fenced code. Missing-pair or unsupported
  outcomes are separately named by the test and cannot establish an inference pass. This is a
  newly added real-engine acceptance check, not an invented historical red.

Contracts: `TRANSLATESTALLED-001`–`004`, `TRANSLATENATIVE-001`–`003`, `TRANSLATEUI-001`
and `TRANSLATEINSTALLED-001`. Structural BDD validity is separate from passing assertions.

## Native evidence and limits

An external baseline Mac probe also translated a synthetic English sentence to Simplified Chinese
using the unchanged published adapter. A separate revised full-Core CLI probe instead reported
setup required and did not translate. These process-context observations are preserved separately;
they do not identify the cause of the phone's original stall. No packs were requested by any probe.

The connected iPhone was initially locked. A compiled, signed isolated probe was later preserved after a scoped signing repair (the original xcodebuild exited 65), but Apple’s device service could not confirm a usable connection; no phone installation or execution occurred. The native desktop tool
also reported the Mac locked. No unlock, authentication or permission-change request was sent to
the maintainer; their TestFlight app and private conversations were left intact. Installed Mac GUI
and physical iPhone translation acceptance remain unverified. Simulator UI and real Mac model
tests do not establish the phone's behavior, broad language quality or production readiness.

Focused evidence is retained under
`/Users/tomwu/Documents/Codex/2026-10-28/listentome-translation-recovery/`: Core red/green logs,
`native/adapter-evidence.json`, `native/installed-evidence.json`, `ui/ui-review.json`, native
result bundles/screenshots, and `device-probe/` source, binary, output and blocked-device records.
Full local validation passed on unchanged `abe5218f61c193421178a2debab16ea2c2b1b2dc` (933 tracked inputs): Core 1,258 tests / 7 optional skips / 0 failures and 98.184% coverage; iOS 83 UI / 5 skips and 503 unit / 7 skips, Mac 48, Watch 29 unit + 5 UI, all with zero failures. All 162 BDD scenarios, four helper suites and four real-server contracts passed. The actual installed Chinese inference branch passed again in 1.26 seconds, separately from setup-required outcomes.

[Validation receipt](releases/ios-1.20.2-build42-validation.json) and [fresh seven-profile media](images/ios/release-1.20.2-en-US.json) preserve source and hashes. The fix then merged with required CI green; the accepted beta receipt below records publication separately. This validation is not a publication receipt. The completed Mac Dev bundle was moved to Trash and only `com.tomwu.ListenToMe.dev` permissions reset, with no active Dev session. Logs, source/signing evidence and native results were retained; production permissions and data were untouched.


## Accepted beta — 1.20.2 (42)

Apple accepted **1.20.2 (42)** through the official TestFlight helper at **2026-10-28T21:11:37.664213+00:00** from `a6b90e83f775cc9dc88df3c2805ecacedca044af`. Apple build `8967f095-470f-40c0-aba0-b1188bbb699c` is **VALID / IN_BETA_TESTING**. Readback at 2026-10-28T21:15:33.796221+00:00 confirms **en-US**, **Listen To Me - Real Time AI**, exact beta description/What to Test and unchanged access for the existing two-member Dev group. Access does not establish physical installation of build 42.

[Publication receipt](releases/ios-1.20.2-build42.json) · [Release notes and native previews](https://github.com/tomqwu/ListenToMe/releases/tag/ios-v1.20.2-build42).

Physical phone translation/lock-screen/multilingual and Watch acceptance remain pending. Public production remains **1.19.1 (39)**; this beta made no new public submission or listing-media upload. Mac changes remain unreleased and keep separate installed-app acceptance gates.
