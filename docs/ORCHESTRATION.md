# Conversation ownership and validation

Core owns shared policy and cancellable work. App targets retain device APIs, rendering, settings
and user decisions. The coverage floor measures the SwiftPM Core target only; no overall product
percentage is claimed. Selected native adapters have separate executable tests. iOS unit/UI and
Mac/Watch native suites run locally through make validate-local under the current AGENTS.md policy;
CI runs Core tests/coverage and compiles both app targets.

| Work | Owner | Native effects |
| --- | --- | --- |
| Start, Stop, language restart | CaptureCoordinator, shared by Mac and iOS | Recorder/transcriber construction, capability and permission checks, final checkpoint |
| Archive durability and cleanup ordering | ConversationRepository on Mac; SessionArchive and erasure policy shared across platforms | Platform archive location, iOS active-snapshot file protection/backup, secondary indexes, audio and folder cleanup |
| iOS active/history save transaction | ConversationPersistenceCoordinator | Stable encoding, archive and active snapshot writes, private storage/backup flags, folder export and UI messages |
| Mac checkpoint identity and dirty state | ConversationCheckpointCoordinator | Eligibility, record assembly, durable write and Save to folder |
| Automatic naming | ConversationTitleCoordinator, shared by Mac and iOS | Current title state, allowed provider and saved-record update |
| New conversation | NewConversationCoordinator | Drain, history write, Save As/Cancel/discard, resetting native state |
| Window close decision | ConversationCloseCoordinator | Drain/save/export decision; cancel context only after acceptance |
| File import | FileImportCoordinator and MeetingSession | File picker, local media reader, progress and native transcriber |
| Calendar context | CalendarContextCoordinator | EventKit lookup, current conversation snapshot and UI binding |
| Reference grounding | ReferenceContextCoordinator | Selected URLs, bounded local file loading and visible skipped-file reasons |
| Model refresh | ModelCatalogCoordinator | Configured destination, Keychain credentials, native discovery and settings persistence |
| Capability, suggestion and speaker follow-up results | LatestResultCoordinator | Native query and current engine/locale/conversation checks |
| Speaker pass scheduling | SpeakerPassCoordinator | Native diarizer and recording/run identity |
| Pane command tasks | MeetingSession | Synchronous request registration; native buttons/hotkeys do not launch wrapper tasks |

The Mac root MeetingView is 274 lines at this checkpoint. Its extensions contain no explicit Task
bodies. MacMeetingEnvironment constructs the shared store/session and separate channel buffers;
its production extension selects the existing native capture, engine and provider factories.
Splitting construction or layout does not itself prove capture correctness. Native graph tests
prove store/buffer wiring, while installed GUI, permissions and actual OTHERS transcription remain
separate acceptance.

MobileSession remains a native adapter with platform-specific language detection, background audio,
Watch delivery and summary presentation. This change does not claim every native method moved to
Core. Both platforms use shared capture ownership, archive policy, naming and summary prompt rules.
iOS save dirty-state/ordering now belongs to ConversationPersistenceCoordinator; MobileSession
only supplies native effects. Its active-snapshot/backup behavior remains platform-specific.
The shared Markdown renderer remains in SharedPlatform.

## Behavior contracts and reproduction

The exact selectors are in Behaviors/conversation-orchestration.json (ORCH-001–014). Run
make bdd-check with the actual stacked base, then the bound native suites and make validate-local.
The checker proves traceability, not assertion quality; independent review compares outcomes.

Baseline adoption, without an invented historical red:

- Calendar formatting, title protection and applicable failure messages (ORCH-001).
- Selected-file loading, bounded reference formatting and skipped-file reporting (ORCH-003).
- Existing local-ranking, pinned-choice and explicit cloud/custom selection policy (ORCH-006).
- New checkpoint → drain → save/decision → reset ordering (ORCH-008).
- Native background audio snapshots and environment graph wiring (ORCH-012/013).
- iOS save transaction (ORCH-014): seven native tests passed against original save code before
  extraction, including real storage failures, empty edits and identical-byte retry. The new Core
  tests and the same seven native tests then verify unchanged policy after extraction. The logs
  are persistence-native-baseline.log, persistence-core-baseline-green.log and
  persistence-native-after-extraction.log; no product regression or historical red is claimed.

External evidence lives in the session's listentome-features/orchestration-134 folder. The following
logs preserve actual failing assertions before their fixes, followed by passing focused commands:

| Contract | Red evidence | Green evidence |
| --- | --- | --- |
| ORCH-002 | calendar-ownership-red.log: late Calendar context/title/error and loading ownership, 11 assertions | calendar-ownership-green.log |
| ORCH-004 | reference-ownership-red.log: cancelled-before-execution I/O and late publication, two assertions | reference-ownership-green.log |
| ORCH-005 | context-close-wired-red.log: rejected/busy/overlapping close invalidation, three assertions | context-close-green.log |
| ORCH-007 | model-ownership-red.log: AI-off lookup/healing, cancellation and obsolete-route publication, eight assertions | model-ownership-green.log |
| ORCH-009 | import-ownership-red.log: cancelled-before-execution media access/transcript, two assertions | import-new-green.log |
| ORCH-010 | pane-command-red.log: extracted unregistered button-task pattern still started Quick/Deep/Summary after immediate Stop, six assertions | pane-command-green.log; prompt-command-green.log also covers literal prompt/chip requests after prompt-command-red.log reproduced four assertions |
| ORCH-011 | background-ownership-red.log: cancelled/superseded requests still queried before execution, two assertions | background-ownership-green.log |

The full thin-view-core-coverage.log run exposed a refactor regression: waiting for Summary's first
task omitted its continuation batches (51 failed assertions across two existing tests). The original
continuation-aware wait is restored; summary-chain-corrected-green.log passes all 50 focused tests.
That failed full run remains failed. A subsequent complete frozen validation must establish green.
The initial Calendar fixture used a non-default title with placeholder state; correcting that test
fixture was not a product fix and is not counted as regression red evidence.

Cancellation fences publication. Already-running synchronous file I/O and OS/network requests may
finish afterward. Core generation checks prevent those results from changing another conversation,
current controls or messages. New's save transaction retains ownership until its drain and explicit
decision finish. Import remains busy after Cancel until transcription drain completes.

## Acceptance still required

Follow docs/manual-smoke-test.md for context edits during lookup, Clear, rejected/accepted close,
New during finalization, immediate pane Stop, multi-batch Summary and import cancellation. Capture
fresh native Mac screenshots and verify real system-audio transcription labeled OTHERS. Automated
native graph tests and Core coverage do not establish rendered UI or physical capture acceptance.

The consolidated PR #308 candidate is frozen separately at b763ac3. This local #134 continuation
does not change its artifact, screenshots or validation provenance. No extra feature PR was opened.
Do not call this work merged or published until the repository's corresponding gates are complete.
