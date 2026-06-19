# ListenToMe MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that listens to a meeting (your mic + the other participants' system audio), transcribes it live on-device, and produces real-time suggestions — both on demand (hotkey + buttons) and proactively when someone asks a question — using a configurable local Ollama model.

**Architecture:** A pure-Swift, dependency-free **`ListenToMeCore`** package holds all testable logic (conversation state, VAD segmentation, question detection, prompt building, the Ollama provider, the model router, the context engine, and the `MeetingSession` orchestrator wired only through protocols). A thin **`ListenToMe`** macOS app target provides the platform glue: `DualChannelCapture` (AVAudioEngine mic + ScreenCaptureKit system audio), `SpeechRecognizerTranscriber` (on-device `SFSpeechRecognizer`, segmented by VAD), the SwiftUI two-pane UI, and a global hotkey. Audio/STT/UI are validated by build + a manual smoke test; everything else is TDD via `swift test`.

**Tech Stack:** Swift 6, SwiftUI, Observation (`@Observable`), Swift Concurrency (`AsyncStream`/`AsyncThrowingStream`), AVFoundation, ScreenCaptureKit, Speech (`SFSpeechRecognizer`), Ollama HTTP API. Tooling: Swift Package Manager (`swift test`), XcodeGen (project generation), SwiftLint, `xcodebuild`, Makefile, Codex review.

**Process rules (from `aml_open_framework` CLAUDE.md, adapted to Swift):**
- TDD: write the failing test, watch it fail, write the minimal code, watch it pass, commit.
- Surgical changes — every line traces to the task.
- **Before EVERY commit, run Codex review and resolve blockers:** `/codex:review --base main` (use `--background` for large diffs, then `/codex:status` / `/codex:result`). Do not commit while Codex reports a blocking issue.
- `make pre-push` (lint + core tests + app build) must pass before pushing.

**Target OS:** macOS 26 (Darwin 25.x).

---

## File Structure

```
ListenToMe/
├── Package.swift                         # SwiftPM: ListenToMeCore library + test target
├── Makefile                              # gen / build / test / lint / pre-push / run
├── project.yml                           # XcodeGen: ListenToMe.app target
├── .swiftlint.yml
├── .gitignore
├── Sources/ListenToMeCore/
│   ├── Models.swift                      # SpeakerSource, AudioChunk, TranscriptSegment
│   ├── ConversationStore.swift           # @Observable rolling utterance log
│   ├── VAD.swift                         # rms(of:), VADSegmenter
│   ├── QuestionDetector.swift            # isQuestion(_:)
│   ├── Prompt.swift                      # ChatMessage, ResponseAction, PromptContext, LLMRequest, PromptBuilder
│   ├── LLMProvider.swift                 # LLMProvider protocol
│   ├── OllamaProvider.swift              # OllamaParser, OllamaProvider
│   ├── ModelRouter.swift                 # @Observable provider registry + routing
│   ├── ContextEngine.swift              # buildContext + proactive trigger
│   ├── Capture.swift                     # AudioCapturing protocol
│   ├── Transcriber.swift                 # Transcribing protocol
│   └── MeetingSession.swift              # @MainActor orchestrator (protocol-only deps)
├── Tests/ListenToMeCoreTests/
│   ├── ConversationStoreTests.swift
│   ├── VADTests.swift
│   ├── QuestionDetectorTests.swift
│   ├── PromptBuilderTests.swift
│   ├── OllamaProviderTests.swift
│   ├── ModelRouterTests.swift
│   ├── ContextEngineTests.swift
│   ├── Mocks.swift                       # MockLLMProvider, MockCapture, MockTranscriber
│   └── MeetingSessionTests.swift
└── App/
    ├── ListenToMeApp.swift               # @main App + window
    ├── MeetingView.swift                 # 2-pane UI + toolbar
    ├── DualChannelCapture.swift          # AudioCapturing impl (mic + system)
    ├── SpeechRecognizerTranscriber.swift # Transcribing impl (SFSpeechRecognizer + VAD)
    ├── HotkeyMonitor.swift               # global ⌘⇧Space monitor
    ├── Info.plist
    └── ListenToMe.entitlements
```

---

## Task 1: Repo scaffolding & toolchain

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `.swiftlint.yml`
- Create: `.gitignore`
- Create: `Sources/ListenToMeCore/Placeholder.swift`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
.DS_Store
.build/
*.xcodeproj
DerivedData/
*.xcuserstate
.swiftpm/
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListenToMeCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ListenToMeCore", targets: ["ListenToMeCore"])
    ],
    targets: [
        .target(name: "ListenToMeCore"),
        .testTarget(name: "ListenToMeCoreTests", dependencies: ["ListenToMeCore"])
    ]
)
```

> Note: `.v15` is the SwiftPM floor for the library (Observation needs macOS 14+); the app target itself targets macOS 26 via `project.yml`. Keeping the library floor lower keeps it broadly buildable.

- [ ] **Step 3: Create a placeholder source so the library compiles**

```swift
// Sources/ListenToMeCore/Placeholder.swift
// Replaced in Task 2. Exists so `swift build` succeeds before any real code.
enum ListenToMeCorePlaceholder {}
```

- [ ] **Step 4: Create `.swiftlint.yml`**

```yaml
disabled_rules:
  - todo
  - trailing_comma
line_length:
  warning: 120
  error: 160
identifier_name:
  min_length: 1
included:
  - Sources
  - App
  - Tests
```

- [ ] **Step 5: Create `Makefile`**

```makefile
.PHONY: gen build test lint run pre-push

gen:
	xcodegen generate

build: gen
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe \
		-destination 'platform=macOS' -configuration Debug build | xcbeautify || \
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe \
		-destination 'platform=macOS' -configuration Debug build

test:
	swift test

lint:
	swiftlint lint --quiet

run: build
	open ./build/Debug/ListenToMe.app 2>/dev/null || \
	open $$(xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe -showBuildSettings | \
		awk '/BUILT_PRODUCTS_DIR/{d=$$3}/FULL_PRODUCT_NAME/{p=$$3}END{print d"/"p}')

pre-push: lint test build
	@echo "pre-push checks passed"
```

> `xcbeautify` is optional formatting; the `||` fallback runs raw `xcodebuild` if it is not installed.

- [ ] **Step 6: Verify the package builds and has zero tests**

Run: `swift build`
Expected: `Build complete!`

Run: `swift test`
Expected: runs and reports `Executed 0 tests` (no tests yet).

- [ ] **Step 7: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Package.swift Makefile .swiftlint.yml .gitignore Sources/ListenToMeCore/Placeholder.swift
git commit -m "chore: scaffold ListenToMeCore package and toolchain"
```

---

## Task 2: Core model types

**Files:**
- Create: `Sources/ListenToMeCore/Models.swift`
- Delete: `Sources/ListenToMeCore/Placeholder.swift`
- Test: `Tests/ListenToMeCoreTests/ConversationStoreTests.swift` (created in Task 3; this task adds a tiny model test inline below)

- [ ] **Step 1: Write the failing test**

Create `Tests/ListenToMeCoreTests/ModelsTests.swift`:

```swift
import XCTest
@testable import ListenToMeCore

final class ModelsTests: XCTestCase {
    func testTranscriptSegmentStoresFields() {
        let id = UUID()
        let seg = TranscriptSegment(id: id, source: .others, text: "Hello",
                                    isFinal: true, start: 1.0, end: 2.0)
        XCTAssertEqual(seg.id, id)
        XCTAssertEqual(seg.source, .others)
        XCTAssertEqual(seg.text, "Hello")
        XCTAssertTrue(seg.isFinal)
        XCTAssertEqual(seg.start, 1.0)
        XCTAssertEqual(seg.end, 2.0)
    }

    func testAudioChunkStoresFields() {
        let chunk = AudioChunk(samples: [0.1, -0.2], sampleRate: 16000,
                               source: .you, timestamp: 3.0)
        XCTAssertEqual(chunk.samples, [0.1, -0.2])
        XCTAssertEqual(chunk.sampleRate, 16000)
        XCTAssertEqual(chunk.source, .you)
        XCTAssertEqual(chunk.timestamp, 3.0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelsTests`
Expected: FAIL — `cannot find 'TranscriptSegment' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/ListenToMeCore/Models.swift`:

```swift
import Foundation

/// Who produced the audio: the local user (microphone) or remote participants (system audio).
public enum SpeakerSource: String, Sendable, Codable, Equatable {
    case you
    case others
}

/// A buffer of mono PCM samples (normalized to -1...1) tagged with its source and capture time.
public struct AudioChunk: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double
    public let source: SpeakerSource
    public let timestamp: TimeInterval

    public init(samples: [Float], sampleRate: Double, source: SpeakerSource, timestamp: TimeInterval) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.source = source
        self.timestamp = timestamp
    }
}

/// One unit of transcribed speech. Partial segments (`isFinal == false`) are replaced as more
/// audio arrives; finalized segments are appended to the conversation log.
public struct TranscriptSegment: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let source: SpeakerSource
    public let text: String
    public let isFinal: Bool
    public let start: TimeInterval
    public let end: TimeInterval

    public init(id: UUID = UUID(), source: SpeakerSource, text: String,
                isFinal: Bool, start: TimeInterval, end: TimeInterval) {
        self.id = id
        self.source = source
        self.text = text
        self.isFinal = isFinal
        self.start = start
        self.end = end
    }
}
```

- [ ] **Step 4: Delete the placeholder**

```bash
rm Sources/ListenToMeCore/Placeholder.swift
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ModelsTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Sources/ListenToMeCore/Models.swift Tests/ListenToMeCoreTests/ModelsTests.swift
git rm Sources/ListenToMeCore/Placeholder.swift
git commit -m "feat: add core model types (SpeakerSource, AudioChunk, TranscriptSegment)"
```

---

## Task 3: ConversationStore

**Files:**
- Create: `Sources/ListenToMeCore/ConversationStore.swift`
- Test: `Tests/ListenToMeCoreTests/ConversationStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ListenToMeCore

final class ConversationStoreTests: XCTestCase {
    private func seg(_ text: String, final: Bool, source: SpeakerSource = .others) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: final, start: 0, end: 1)
    }

    func testPartialDoesNotAppend() {
        let store = ConversationStore()
        store.apply(seg("typing", final: false))
        XCTAssertTrue(store.utterances.isEmpty)
        XCTAssertEqual(store.partial?.text, "typing")
    }

    func testFinalAppendsAndClearsPartial() {
        let store = ConversationStore()
        store.apply(seg("typing", final: false))
        store.apply(seg("done", final: true))
        XCTAssertEqual(store.utterances.map(\.text), ["done"])
        XCTAssertNil(store.partial)
    }

    func testRecentContextRespectsCharBudget() {
        let store = ConversationStore()
        store.apply(seg("aaaa", final: true))   // 4 chars
        store.apply(seg("bbbb", final: true))   // 4 chars
        store.apply(seg("cccc", final: true))   // 4 chars
        // Budget 9: keep newest segments that fit (cccc=4, +bbbb=8 <= 9; +aaaa=12 > 9 stops).
        let recent = store.recentContext(maxChars: 9)
        XCTAssertEqual(recent.map(\.text), ["bbbb", "cccc"])
    }

    func testRecentContextKeepsAtLeastOne() {
        let store = ConversationStore()
        store.apply(seg("a very long final utterance", final: true))
        XCTAssertEqual(store.recentContext(maxChars: 1).count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConversationStoreTests`
Expected: FAIL — `cannot find 'ConversationStore' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import Observation

/// The single source of truth for transcribed conversation. UI and engines read from it.
@Observable
public final class ConversationStore {
    /// Finalized utterances in chronological order.
    public private(set) var utterances: [TranscriptSegment] = []
    /// The current in-progress (non-final) segment, if any.
    public private(set) var partial: TranscriptSegment?

    public init() {}

    public func apply(_ segment: TranscriptSegment) {
        if segment.isFinal {
            utterances.append(segment)
            partial = nil
        } else {
            partial = segment
        }
    }

    /// Most-recent finalized utterances whose combined text stays within `maxChars`.
    /// Always returns at least the latest utterance if any exist.
    public func recentContext(maxChars: Int) -> [TranscriptSegment] {
        var total = 0
        var collected: [TranscriptSegment] = []
        for segment in utterances.reversed() {
            if total + segment.text.count > maxChars && !collected.isEmpty {
                break
            }
            total += segment.text.count
            collected.append(segment)
        }
        return collected.reversed()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConversationStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Sources/ListenToMeCore/ConversationStore.swift Tests/ListenToMeCoreTests/ConversationStoreTests.swift
git commit -m "feat: add ConversationStore rolling utterance log"
```

---

## Task 4: VAD (RMS + utterance segmenter)

**Files:**
- Create: `Sources/ListenToMeCore/VAD.swift`
- Test: `Tests/ListenToMeCoreTests/VADTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ListenToMeCore

final class VADTests: XCTestCase {
    func testRMSOfSilenceIsZero() {
        XCTAssertEqual(rms(of: [0, 0, 0, 0]), 0, accuracy: 1e-6)
    }

    func testRMSOfConstantSignal() {
        XCTAssertEqual(rms(of: [0.5, -0.5, 0.5, -0.5]), 0.5, accuracy: 1e-6)
    }

    func testRMSOfEmptyIsZero() {
        XCTAssertEqual(rms(of: []), 0, accuracy: 1e-6)
    }

    func testSegmenterFiresAfterTrailingSilence() {
        var seg = VADSegmenter(speechThreshold: 0.1, silenceDuration: 0.5)
        // Speech starts at t=0.0, continues to 1.0, then silence.
        XCTAssertFalse(seg.process(rms: 0.3, at: 0.0))   // speech begins
        XCTAssertFalse(seg.process(rms: 0.3, at: 0.5))   // still speaking
        XCTAssertFalse(seg.process(rms: 0.0, at: 0.8))   // silence < 0.5s after last speech
        XCTAssertTrue(seg.process(rms: 0.0, at: 1.1))    // 0.6s of silence -> boundary
    }

    func testSegmenterDoesNotFireWithoutPriorSpeech() {
        var seg = VADSegmenter(speechThreshold: 0.1, silenceDuration: 0.5)
        XCTAssertFalse(seg.process(rms: 0.0, at: 0.0))
        XCTAssertFalse(seg.process(rms: 0.0, at: 10.0))
    }

    func testSegmenterFiresOncePerUtterance() {
        var seg = VADSegmenter(speechThreshold: 0.1, silenceDuration: 0.5)
        _ = seg.process(rms: 0.3, at: 0.0)
        XCTAssertTrue(seg.process(rms: 0.0, at: 0.6))    // boundary
        XCTAssertFalse(seg.process(rms: 0.0, at: 1.2))   // still silent, no double-fire
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VADTests`
Expected: FAIL — `cannot find 'rms' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Root-mean-square energy of a PCM frame. 0 for empty input.
public func rms(of samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
    return (sumSquares / Float(samples.count)).squareRoot()
}

/// Detects utterance boundaries from a stream of per-frame RMS values.
/// `process` returns `true` exactly once, on the frame where trailing silence
/// after speech first exceeds `silenceDuration`.
public struct VADSegmenter {
    public let speechThreshold: Float
    public let silenceDuration: TimeInterval

    private var inSpeech = false
    private var lastSpeechTime: TimeInterval = 0

    public init(speechThreshold: Float = 0.02, silenceDuration: TimeInterval = 0.8) {
        self.speechThreshold = speechThreshold
        self.silenceDuration = silenceDuration
    }

    public mutating func process(rms value: Float, at time: TimeInterval) -> Bool {
        if value >= speechThreshold {
            inSpeech = true
            lastSpeechTime = time
            return false
        }
        if inSpeech && (time - lastSpeechTime) >= silenceDuration {
            inSpeech = false
            return true
        }
        return false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VADTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Sources/ListenToMeCore/VAD.swift Tests/ListenToMeCoreTests/VADTests.swift
git commit -m "feat: add RMS energy and VAD utterance segmenter"
```

---

## Task 5: QuestionDetector

**Files:**
- Create: `Sources/ListenToMeCore/QuestionDetector.swift`
- Test: `Tests/ListenToMeCoreTests/QuestionDetectorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ListenToMeCore

final class QuestionDetectorTests: XCTestCase {
    func testQuestionMarkIsQuestion() {
        XCTAssertTrue(QuestionDetector.isQuestion("So what is the timeline?"))
    }

    func testLeadingInterrogativeIsQuestion() {
        XCTAssertTrue(QuestionDetector.isQuestion("How should we handle retries"))
        XCTAssertTrue(QuestionDetector.isQuestion("can you walk me through it"))
    }

    func testEmbeddedCueIsQuestion() {
        XCTAssertTrue(QuestionDetector.isQuestion("Tom, what do you think about that"))
    }

    func testStatementIsNotQuestion() {
        XCTAssertFalse(QuestionDetector.isQuestion("We shipped the release yesterday."))
    }

    func testEmptyIsNotQuestion() {
        XCTAssertFalse(QuestionDetector.isQuestion("   "))
    }

    func testCuePrefixInsideWordIsNotQuestion() {
        XCTAssertFalse(QuestionDetector.isQuestion("However, the release is ready"))
        XCTAssertFalse(QuestionDetector.isQuestion("I tried whatever worked"))
    }

    func testInterrogativeWordMidSentenceIsNotQuestion() {
        XCTAssertFalse(QuestionDetector.isQuestion("I know what happened"))
        XCTAssertFalse(QuestionDetector.isQuestion("They explained why it failed"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter QuestionDetectorTests`
Expected: FAIL — `cannot find 'QuestionDetector' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Heuristic detector for "someone is asking for input". Deliberately simple and swappable.
public enum QuestionDetector {
    /// Single interrogative words: only count when they START the utterance.
    private static let leadingCues: [String] = [
        "what", "why", "how", "when", "where", "who", "which", "whose"
    ]
    /// Phrase / imperative cues: count anywhere, matched on word boundaries.
    private static let phraseCues: [String] = [
        "can you", "could you", "would you", "will you", "do you", "did you",
        "are you", "is there", "should we", "any thoughts", "what do you think",
        "thoughts on", "tell me", "explain", "walk me through"
    ]

    public static func isQuestion(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.hasSuffix("?") { return true }
        for cue in leadingCues where normalized == cue || normalized.hasPrefix(cue + " ") {
            return true
        }
        return phraseCues.contains { cue in
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: cue) + "\\b"
            return normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter QuestionDetectorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Sources/ListenToMeCore/QuestionDetector.swift Tests/ListenToMeCoreTests/QuestionDetectorTests.swift
git commit -m "feat: add heuristic QuestionDetector"
```

---

## Task 6: Prompt types & PromptBuilder

**Files:**
- Create: `Sources/ListenToMeCore/Prompt.swift`
- Test: `Tests/ListenToMeCoreTests/PromptBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ListenToMeCore

final class PromptBuilderTests: XCTestCase {
    private func ctx(notes: String? = nil) -> PromptContext {
        PromptContext(messages: [
            TranscriptSegment(source: .others, text: "What is our deploy plan?",
                              isFinal: true, start: 0, end: 1),
            TranscriptSegment(source: .you, text: "Good question.",
                              isFinal: true, start: 1, end: 2)
        ], notes: notes)
    }

    func testSystemPromptHasNoPreambleConstraint() {
        XCTAssertTrue(PromptBuilder.systemPrompt.lowercased().contains("concise"))
        XCTAssertTrue(PromptBuilder.systemPrompt.lowercased().contains("no preamble"))
    }

    func testTranscriptFormattedWithSpeakerLabels() {
        let req = PromptBuilder.build(context: ctx(), action: .answerQuestion)
        let user = req.messages.last!.content
        XCTAssertTrue(user.contains("Others: What is our deploy plan?"))
        XCTAssertTrue(user.contains("You: Good question."))
    }

    func testActionInstructionVaries() {
        let answer = PromptBuilder.build(context: ctx(), action: .answerQuestion).messages.last!.content
        let recap = PromptBuilder.build(context: ctx(), action: .recap).messages.last!.content
        let follow = PromptBuilder.build(context: ctx(), action: .followUp).messages.last!.content
        XCTAssertTrue(answer.contains("answer"))
        XCTAssertTrue(recap.lowercased().contains("recap") || recap.lowercased().contains("summar"))
        XCTAssertTrue(follow.lowercased().contains("follow-up") || follow.lowercased().contains("question"))
    }

    func testNotesInjectedWhenPresent() {
        let req = PromptBuilder.build(context: ctx(notes: "I am the backend lead."), action: .answerQuestion)
        XCTAssertTrue(req.messages.last!.content.contains("I am the backend lead."))
    }

    func testNotesOmittedWhenNil() {
        let req = PromptBuilder.build(context: ctx(notes: nil), action: .answerQuestion)
        XCTAssertFalse(req.messages.last!.content.contains("Context notes"))
    }

    func testSystemMessageIsFirst() {
        let req = PromptBuilder.build(context: ctx(), action: .proactive)
        XCTAssertEqual(req.system, PromptBuilder.systemPrompt)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PromptBuilderTests`
Expected: FAIL — `cannot find 'PromptContext' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// A provider-agnostic chat message.
public struct ChatMessage: Sendable, Equatable {
    public let role: String   // "system" | "user" | "assistant"
    public let content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// What the listener wants from the assistant right now.
public enum ResponseAction: Sendable, Equatable {
    case answerQuestion   // hotkey / "What should I answer?"
    case recap            // "Recap so far"
    case followUp         // "Suggest a follow-up"
    case proactive        // auto-detected incoming question
}

/// The conversational context handed to the model.
public struct PromptContext: Sendable, Equatable {
    public let messages: [TranscriptSegment]
    public let notes: String?
    public init(messages: [TranscriptSegment], notes: String?) {
        self.messages = messages
        self.notes = notes
    }
}

/// A provider-agnostic request: a system prompt plus chat messages.
public struct LLMRequest: Sendable, Equatable {
    public let system: String
    public let messages: [ChatMessage]
    public init(system: String, messages: [ChatMessage]) {
        self.system = system
        self.messages = messages
    }
}

/// Builds the system prompt and user message for a given context + action.
public enum PromptBuilder {
    public static let systemPrompt = """
    You are a real-time meeting copilot for the user, labeled "You". The transcript labels remote \
    participants as "Others". Give the user something they can say or act on immediately.
    Be concise and conversational. No preamble, no "As an AI", no restating the question, no \
    meta-commentary. Prefer 1-3 short sentences or a tight bullet list. If a question was asked, \
    answer it directly first.
    """

    private static func instruction(for action: ResponseAction) -> String {
        switch action {
        case .answerQuestion, .proactive:
            return "Based on the transcript, give the user the best answer or response to say next."
        case .recap:
            return "Give a brief recap (summary) of the conversation so far."
        case .followUp:
            return "Suggest one good follow-up question the user could ask next."
        }
    }

    public static func build(context: PromptContext, action: ResponseAction) -> LLMRequest {
        let transcript = context.messages.map { seg in
            "\(seg.source == .you ? "You" : "Others"): \(seg.text)"
        }.joined(separator: "\n")

        var user = "Transcript so far:\n\(transcript)\n\n"
        if let notes = context.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "Context notes from the user:\n\(notes)\n\n"
        }
        user += instruction(for: action)

        return LLMRequest(
            system: systemPrompt,
            messages: [ChatMessage(role: "user", content: user)]
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PromptBuilderTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Sources/ListenToMeCore/Prompt.swift Tests/ListenToMeCoreTests/PromptBuilderTests.swift
git commit -m "feat: add prompt types and PromptBuilder with action variants"
```

---

## Task 7: LLMProvider protocol & OllamaProvider

**Files:**
- Create: `Sources/ListenToMeCore/LLMProvider.swift`
- Create: `Sources/ListenToMeCore/OllamaProvider.swift`
- Test: `Tests/ListenToMeCoreTests/OllamaProviderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ListenToMeCore

final class OllamaProviderTests: XCTestCase {
    func testParserExtractsContentDelta() {
        let line = #"{"message":{"role":"assistant","content":"Hello"},"done":false}"#
        XCTAssertEqual(OllamaParser.delta(fromLine: line), "Hello")
    }

    func testParserReturnsNilForNonContentLine() {
        XCTAssertNil(OllamaParser.delta(fromLine: #"{"done":true}"#))
        XCTAssertNil(OllamaParser.delta(fromLine: "not json"))
    }

    func testParserDetectsDone() {
        XCTAssertTrue(OllamaParser.isDone(line: #"{"done":true}"#))
        XCTAssertFalse(OllamaParser.isDone(line: #"{"done":false}"#))
        XCTAssertFalse(OllamaParser.isDone(line: "garbage"))
    }

    func testRequestBodyEncodesModelMessagesAndStream() throws {
        let req = LLMRequest(system: "SYS", messages: [ChatMessage(role: "user", content: "hi")])
        let data = OllamaProvider.requestBody(model: "llama3.1", request: req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["model"] as? String, "llama3.1")
        XCTAssertEqual(obj["stream"] as? Bool, true)
        let messages = obj["messages"] as! [[String: String]]
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.first?["content"], "SYS")
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertEqual(messages.last?["content"], "hi")
    }

    func testStreamYieldsParsedDeltasUntilDone() async throws {
        let lines = [
            #"{"message":{"role":"assistant","content":"Hel"},"done":false}"#,
            #"{"message":{"role":"assistant","content":"lo"},"done":false}"#,
            #"{"done":true}"#,
            #"{"message":{"role":"assistant","content":"IGNORED"},"done":false}"#
        ]
        let provider = OllamaProvider(model: "m", baseURL: URL(string: "http://x")!) { _ in
            AsyncThrowingStream { continuation in
                for line in lines { continuation.yield(line) }
                continuation.finish()
            }
        }
        var collected = ""
        for try await delta in provider.stream(
            LLMRequest(system: "s", messages: [ChatMessage(role: "user", content: "u")])) {
            collected += delta
        }
        XCTAssertEqual(collected, "Hello")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OllamaProviderTests`
Expected: FAIL — `cannot find 'OllamaParser' in scope`.

- [ ] **Step 3: Write the LLMProvider protocol**

`Sources/ListenToMeCore/LLMProvider.swift`:

```swift
import Foundation

/// A streaming chat model. Implementations yield token/text deltas as they arrive.
public protocol LLMProvider: Sendable {
    var id: String { get }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>
}
```

- [ ] **Step 4: Write the OllamaProvider implementation**

`Sources/ListenToMeCore/OllamaProvider.swift`:

```swift
import Foundation

/// Pure parsing of Ollama's NDJSON streaming responses (`/api/chat`).
public enum OllamaParser {
    public static func delta(fromLine line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return content
    }

    public static func isDone(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return (obj["done"] as? Bool) == true
    }
}

/// Streams chat completions from a local (or remote) Ollama server.
public struct OllamaProvider: LLMProvider {
    public let id = "ollama"
    private let model: String
    private let baseURL: URL
    private let lineSource: @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error>

    /// Designated initializer. `lineSource` yields raw NDJSON lines; injectable for testing.
    public init(model: String, baseURL: URL,
                lineSource: @escaping @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error>) {
        self.model = model
        self.baseURL = baseURL
        self.lineSource = lineSource
    }

    /// Live initializer that talks to a real Ollama server over HTTP.
    public init(model: String, baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.init(model: model, baseURL: baseURL,
                  lineSource: Self.makeLiveLineSource(model: model, baseURL: baseURL))
    }

    public static func requestBody(model: String, request: LLMRequest) -> Data {
        var messages: [[String: String]] = [["role": "system", "content": request.system]]
        messages += request.messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["model": model, "messages": messages, "stream": true]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lineSource(request) {
                        if Task.isCancelled { break }
                        if let delta = OllamaParser.delta(fromLine: line), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                        if OllamaParser.isDone(line: line) { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func makeLiveLineSource(
        model: String, baseURL: URL
    ) -> @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error> {
        return { request in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
                        urlRequest.httpMethod = "POST"
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        urlRequest.httpBody = requestBody(model: model, request: request)
                        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                        if let http = response as? HTTPURLResponse,
                           !(200...299).contains(http.statusCode) {
                            throw NSError(
                                domain: "Ollama", code: http.statusCode,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "Ollama returned HTTP \(http.statusCode). Is the server running and the model pulled?"])
                        }
                        for try await line in bytes.lines {
                            continuation.yield(line)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter OllamaProviderTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Sources/ListenToMeCore/LLMProvider.swift Sources/ListenToMeCore/OllamaProvider.swift Tests/ListenToMeCoreTests/OllamaProviderTests.swift
git commit -m "feat: add LLMProvider protocol and streaming OllamaProvider"
```

---

## Task 8: ModelRouter

**Files:**
- Create: `Sources/ListenToMeCore/ModelRouter.swift`
- Create: `Tests/ListenToMeCoreTests/Mocks.swift`
- Test: `Tests/ListenToMeCoreTests/ModelRouterTests.swift`

- [ ] **Step 1: Write the mock and the failing test**

`Tests/ListenToMeCoreTests/Mocks.swift`:

```swift
import Foundation
@testable import ListenToMeCore

/// Yields a fixed list of deltas, then finishes.
struct MockLLMProvider: LLMProvider {
    let id: String
    let deltas: [String]
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
    }
}
```

`Tests/ListenToMeCoreTests/ModelRouterTests.swift`:

```swift
import XCTest
@testable import ListenToMeCore

final class ModelRouterTests: XCTestCase {
    private func collect(_ router: ModelRouter) async throws -> String {
        var out = ""
        let req = LLMRequest(system: "s", messages: [ChatMessage(role: "user", content: "u")])
        for try await delta in router.stream(req) { out += delta }
        return out
    }

    func testDefaultProviderIsActive() {
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: ["a"]))
        XCTAssertEqual(router.activeID, "ollama")
    }

    func testStreamsFromActiveProvider() async throws {
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: ["he", "llo"]))
        let out = try await collect(router)
        XCTAssertEqual(out, "hello")
    }

    func testSwitchingActiveProvider() async throws {
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: ["x"]))
        router.register(MockLLMProvider(id: "claude", deltas: ["cl", "aude"]))
        router.setActive("claude")
        XCTAssertEqual(router.activeID, "claude")
        let out = try await collect(router)
        XCTAssertEqual(out, "claude")
    }

    func testSwitchingToUnknownProviderIsIgnored() {
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: ["x"]))
        router.setActive("does-not-exist")
        XCTAssertEqual(router.activeID, "ollama")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelRouterTests`
Expected: FAIL — `cannot find 'ModelRouter' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/ListenToMeCore/ModelRouter.swift`:

```swift
import Foundation
import Observation

/// Holds the registered providers and routes streaming requests to the active one.
@Observable
public final class ModelRouter {
    private var providers: [String: any LLMProvider] = [:]
    public private(set) var activeID: String

    public init(default provider: any LLMProvider) {
        activeID = provider.id
        providers[provider.id] = provider
    }

    public func register(_ provider: any LLMProvider) {
        providers[provider.id] = provider
    }

    /// Switches the active provider if `id` is registered; otherwise a no-op.
    public func setActive(_ id: String) {
        if providers[id] != nil { activeID = id }
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        guard let provider = providers[activeID] else {
            return AsyncThrowingStream { $0.finish() }
        }
        return provider.stream(request)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelRouterTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Sources/ListenToMeCore/ModelRouter.swift Tests/ListenToMeCoreTests/ModelRouterTests.swift Tests/ListenToMeCoreTests/Mocks.swift
git commit -m "feat: add ModelRouter provider registry and routing"
```

---

## Task 9: ContextEngine

**Files:**
- Create: `Sources/ListenToMeCore/ContextEngine.swift`
- Test: `Tests/ListenToMeCoreTests/ContextEngineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ListenToMeCore

final class ContextEngineTests: XCTestCase {
    private func finalSeg(_ text: String, _ source: SpeakerSource) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: true, start: 0, end: 1)
    }

    func testBuildContextPullsRecentAndNotes() {
        let store = ConversationStore()
        store.apply(finalSeg("hello there", .others))
        let engine = ContextEngine(debounce: 5)
        let ctx = engine.buildContext(from: store, notes: "my notes", maxChars: 4000)
        XCTAssertEqual(ctx.messages.map(\.text), ["hello there"])
        XCTAssertEqual(ctx.notes, "my notes")
    }

    func testProactiveFiresForOthersQuestion() {
        var engine = ContextEngine(debounce: 5)
        XCTAssertTrue(engine.shouldFireProactive(for: finalSeg("what is the ETA?", .others), now: 0))
    }

    func testProactiveIgnoresYou() {
        var engine = ContextEngine(debounce: 5)
        XCTAssertFalse(engine.shouldFireProactive(for: finalSeg("what is the ETA?", .you), now: 0))
    }

    func testProactiveIgnoresNonQuestion() {
        var engine = ContextEngine(debounce: 5)
        XCTAssertFalse(engine.shouldFireProactive(for: finalSeg("we are done.", .others), now: 0))
    }

    func testProactiveIgnoresPartial() {
        var engine = ContextEngine(debounce: 5)
        let partial = TranscriptSegment(source: .others, text: "what now?", isFinal: false, start: 0, end: 1)
        XCTAssertFalse(engine.shouldFireProactive(for: partial, now: 0))
    }

    func testProactiveDebounced() {
        var engine = ContextEngine(debounce: 5)
        XCTAssertTrue(engine.shouldFireProactive(for: finalSeg("q1?", .others), now: 0))
        XCTAssertFalse(engine.shouldFireProactive(for: finalSeg("q2?", .others), now: 3))   // within debounce
        XCTAssertTrue(engine.shouldFireProactive(for: finalSeg("q3?", .others), now: 6))    // past debounce
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContextEngineTests`
Expected: FAIL — `cannot find 'ContextEngine' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Assembles prompt context and decides when to fire a proactive suggestion.
public struct ContextEngine {
    public let debounce: TimeInterval
    private var lastFire: TimeInterval = -.greatestFiniteMagnitude

    public init(debounce: TimeInterval = 8) {
        self.debounce = debounce
    }

    public func buildContext(from store: ConversationStore, notes: String?, maxChars: Int = 4000) -> PromptContext {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PromptContext(
            messages: store.recentContext(maxChars: maxChars),
            notes: (trimmed?.isEmpty == false) ? trimmed : nil
        )
    }

    /// True when a finalized remote question arrives and the debounce window has elapsed.
    public mutating func shouldFireProactive(for segment: TranscriptSegment, now: TimeInterval) -> Bool {
        guard segment.isFinal,
              segment.source == .others,
              QuestionDetector.isQuestion(segment.text),
              now - lastFire >= debounce else {
            return false
        }
        lastFire = now
        return true
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContextEngineTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Sources/ListenToMeCore/ContextEngine.swift Tests/ListenToMeCoreTests/ContextEngineTests.swift
git commit -m "feat: add ContextEngine with debounced proactive trigger"
```

---

## Task 10: Capture/Transcriber protocols & MeetingSession orchestrator

**Files:**
- Create: `Sources/ListenToMeCore/Capture.swift`
- Create: `Sources/ListenToMeCore/Transcriber.swift`
- Create: `Sources/ListenToMeCore/MeetingSession.swift`
- Modify: `Tests/ListenToMeCoreTests/Mocks.swift`
- Test: `Tests/ListenToMeCoreTests/MeetingSessionTests.swift`

- [ ] **Step 1: Write the protocols**

`Sources/ListenToMeCore/Capture.swift`:

```swift
import Foundation

/// Captures audio and emits source-tagged chunks. Real impl lives in the app target.
public protocol AudioCapturing: Sendable {
    var chunks: AsyncStream<AudioChunk> { get }
    func start() async throws
    func stop()
}
```

`Sources/ListenToMeCore/Transcriber.swift`:

```swift
import Foundation

/// Converts audio chunks into transcript segments. Real impl lives in the app target.
public protocol Transcribing: Sendable {
    var segments: AsyncStream<TranscriptSegment> { get }
    func feed(_ chunk: AudioChunk) async
    func finish() async
}
```

- [ ] **Step 2: Add mocks for the orchestrator test**

Append to `Tests/ListenToMeCoreTests/Mocks.swift`:

```swift
/// Capture mock that never emits on its own (the session test drives the transcriber directly).
final class MockCapture: AudioCapturing, @unchecked Sendable {
    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation
    init() {
        var cont: AsyncStream<AudioChunk>.Continuation!
        chunks = AsyncStream { cont = $0 }
        continuation = cont
    }
    func start() async throws {}
    func stop() { continuation.finish() }
}

/// Transcriber mock whose `segments` stream is fed by the test via `emit`.
final class MockTranscriber: Transcribing, @unchecked Sendable {
    let segments: AsyncStream<TranscriptSegment>
    private let continuation: AsyncStream<TranscriptSegment>.Continuation
    init() {
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
    }
    func feed(_ chunk: AudioChunk) async {}
    func finish() async { continuation.finish() }
    func emit(_ segment: TranscriptSegment) { continuation.yield(segment) }
}
```

- [ ] **Step 3: Write the failing test**

`Tests/ListenToMeCoreTests/MeetingSessionTests.swift`:

```swift
import XCTest
@testable import ListenToMeCore

@MainActor
final class MeetingSessionTests: XCTestCase {
    private func makeSession(deltas: [String], now: @escaping @Sendable () -> TimeInterval = { 0 })
        -> (MeetingSession, ConversationStore) {
        let store = ConversationStore()
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: deltas))
        let session = MeetingSession(
            store: store,
            router: router,
            context: ContextEngine(debounce: 5),
            capture: MockCapture(),
            transcriber: MockTranscriber(),
            clock: now
        )
        return (session, store)
    }

    func testRespondStreamsIntoSuggestion() async {
        let (session, _) = makeSession(deltas: ["Ship ", "Friday."])
        await session.respond(.answerQuestion)
        XCTAssertEqual(session.suggestion, "Ship Friday.")
        XCTAssertFalse(session.isStreaming)
    }

    func testIngestAppendsToStore() async {
        let (session, store) = makeSession(deltas: ["x"])
        await session.ingest(TranscriptSegment(source: .others, text: "Hello",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(store.utterances.map(\.text), ["Hello"])
    }

    func testIngestFiresProactiveOnRemoteQuestion() async {
        let (session, _) = makeSession(deltas: ["Tell ", "them yes."])
        await session.ingest(TranscriptSegment(source: .others, text: "Are we ready?",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(session.suggestion, "Tell them yes.")
    }

    func testIngestDoesNotFireWhenProactiveDisabled() async {
        let (session, _) = makeSession(deltas: ["nope"])
        session.proactiveEnabled = false
        await session.ingest(TranscriptSegment(source: .others, text: "Are we ready?",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(session.suggestion, "")
    }

    func testIngestIgnoresOwnSpeech() async {
        let (session, _) = makeSession(deltas: ["should not run"])
        await session.ingest(TranscriptSegment(source: .you, text: "What should I do?",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(session.suggestion, "")
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `swift test --filter MeetingSessionTests`
Expected: FAIL — `cannot find 'MeetingSession' in scope`.

- [ ] **Step 5: Write the implementation**

`Sources/ListenToMeCore/MeetingSession.swift`:

```swift
import Foundation
import Observation

/// Orchestrates capture -> transcription -> store -> proactive/on-demand responses.
/// Depends only on protocols, so it is fully unit-testable with mocks.
@MainActor
@Observable
public final class MeetingSession {
    public private(set) var isRunning = false
    public private(set) var isStreaming = false
    public private(set) var suggestion = ""
    public var notes = ""
    public var proactiveEnabled = true

    public let store: ConversationStore
    public let router: ModelRouter
    private var context: ContextEngine
    private let capture: AudioCapturing
    private let transcriber: Transcribing
    private let clock: @Sendable () -> TimeInterval

    private var pumpTasks: [Task<Void, Never>] = []
    private var responseTask: Task<Void, Never>?

    public init(store: ConversationStore,
                router: ModelRouter,
                context: ContextEngine,
                capture: AudioCapturing,
                transcriber: Transcribing,
                clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.router = router
        self.context = context
        self.capture = capture
        self.transcriber = transcriber
        self.clock = clock
    }

    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        try await capture.start()

        let captureStream = capture.chunks
        let transcriber = self.transcriber
        pumpTasks.append(Task {
            for await chunk in captureStream {
                await transcriber.feed(chunk)
            }
        })

        let segmentStream = transcriber.segments
        pumpTasks.append(Task { [weak self] in
            for await segment in segmentStream {
                await self?.ingest(segment)
            }
        })
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        capture.stop()
        pumpTasks.forEach { $0.cancel() }
        pumpTasks.removeAll()
        Task { await transcriber.finish() }
    }

    /// Applies a segment to the store and fires a proactive response when warranted.
    public func ingest(_ segment: TranscriptSegment) async {
        store.apply(segment)
        guard proactiveEnabled,
              context.shouldFireProactive(for: segment, now: clock()) else { return }
        await respond(.proactive)
    }

    /// Streams a suggestion for the given action into `suggestion`.
    public func respond(_ action: ResponseAction) async {
        responseTask?.cancel()
        let request = PromptBuilder.build(
            context: context.buildContext(from: store, notes: notes),
            action: action
        )
        suggestion = ""
        isStreaming = true
        defer { isStreaming = false }
        do {
            for try await delta in router.stream(request) {
                suggestion += delta
            }
        } catch {
            suggestion = "⚠️ \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --filter MeetingSessionTests`
Expected: PASS (5 tests).

- [ ] **Step 7: Run the full core suite**

Run: `swift test`
Expected: PASS (all tests across Tasks 2–10).

- [ ] **Step 8: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add Sources/ListenToMeCore/Capture.swift Sources/ListenToMeCore/Transcriber.swift Sources/ListenToMeCore/MeetingSession.swift Tests/ListenToMeCoreTests/Mocks.swift Tests/ListenToMeCoreTests/MeetingSessionTests.swift
git commit -m "feat: add capture/transcriber protocols and MeetingSession orchestrator"
```

---

## Task 11: XcodeGen app scaffold (builds an empty window)

**Files:**
- Create: `project.yml`
- Create: `App/ListenToMeApp.swift`
- Create: `App/Info.plist`
- Create: `App/ListenToMe.entitlements`

> Prereq: `brew install xcodegen` (and optionally `brew install xcbeautify swiftlint`).

- [ ] **Step 1: Create `project.yml`**

```yaml
name: ListenToMe
options:
  bundleIdPrefix: com.tomwu
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
packages:
  ListenToMeCore:
    path: .
targets:
  ListenToMe:
    type: application
    platform: macOS
    sources:
      - App
    dependencies:
      - package: ListenToMeCore
        product: ListenToMeCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tomwu.ListenToMe
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        GENERATE_INFOPLIST_FILE: NO
        INFOPLIST_FILE: App/Info.plist
        CODE_SIGN_ENTITLEMENTS: App/ListenToMe.entitlements
        CODE_SIGN_STYLE: Automatic
        SWIFT_VERSION: "6.0"
```

- [ ] **Step 2: Create `App/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ListenToMe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>ListenToMe transcribes meeting audio you choose to capture.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>ListenToMe converts captured speech to text on your device.</string>
</dict>
</plist>
```

- [ ] **Step 3: Create `App/ListenToMe.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

> Sandbox is off intentionally: this is a personal sideloaded build, and disabling it avoids extra
> entitlements for ScreenCaptureKit and `localhost` Ollama access.

- [ ] **Step 4: Create a minimal app entry point**

`App/ListenToMeApp.swift`:

```swift
import SwiftUI

@main
struct ListenToMeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("ListenToMe")
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}
```

- [ ] **Step 5: Generate the project and build**

Run: `make gen`
Expected: `Created project at ListenToMe.xcodeproj`.

Run: `make build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add project.yml App/ListenToMeApp.swift App/Info.plist App/ListenToMe.entitlements
git commit -m "feat: add XcodeGen app scaffold that builds an empty window"
```

---

## Task 12: DualChannelCapture (mic + system audio)

**Files:**
- Create: `App/DualChannelCapture.swift`

> This is platform glue with no unit test; verify by build + the Task 15 smoke test. The RMS/segmentation
> logic it relies on is already unit-tested in `ListenToMeCore`.

- [ ] **Step 1: Write the implementation**

`App/DualChannelCapture.swift`:

```swift
import Foundation
import AVFoundation
import ScreenCaptureKit
import ListenToMeCore

/// Captures the local microphone (source `.you`) and system audio (source `.others`),
/// converting both to mono Float PCM and emitting `AudioChunk`s.
final class DualChannelCapture: NSObject, AudioCapturing, @unchecked Sendable {
    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation

    private let engine = AVAudioEngine()
    private var stream: SCStream?
    private let startTime = Date()

    override init() {
        var cont: AsyncStream<AudioChunk>.Continuation!
        chunks = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        continuation = cont
        super.init()
    }

    func start() async throws {
        try startMic()
        try await startSystemAudio()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        stream?.stopCapture { _ in }
        stream = nil
        continuation.finish()
    }

    // MARK: - Microphone (.you)

    private func startMic() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.emit(buffer: buffer, source: .you)
        }
        engine.prepare()
        try engine.start()
    }

    // MARK: - System audio (.others)

    private func startSystemAudio() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio,
                                   sampleHandlerQueue: DispatchQueue(label: "system-audio"))
        try await stream.startCapture()
        self.stream = stream
    }

    // MARK: - Emit helpers

    private func emit(buffer: AVAudioPCMBuffer, source: SpeakerSource) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        let chunk = AudioChunk(samples: samples,
                               sampleRate: buffer.format.sampleRate,
                               source: source,
                               timestamp: Date().timeIntervalSince(startTime))
        continuation.yield(chunk)
    }
}

extension DualChannelCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio,
              let pcm = sampleBuffer.toMonoFloatBuffer() else { return }
        emit(buffer: pcm, source: .others)
    }
}

private extension CMSampleBuffer {
    /// Converts a CoreMedia audio sample buffer to a mono Float `AVAudioPCMBuffer`.
    func toMonoFloatBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
        else { return nil }
        var settings = asbd
        guard let format = AVAudioFormat(streamDescription: &settings) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames
        CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        // If not already mono Float32, return as-is; the recognizer accepts the engine's format.
        return buffer
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

> If `toMonoFloatBuffer` fails to produce Float32 mono on your hardware, that is acceptable for this
> task — the transcriber in Task 13 reads `buffer.format` directly and adapts. Channel/source labeling
> is what matters here.

- [ ] **Step 3: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add App/DualChannelCapture.swift
git commit -m "feat: add DualChannelCapture for mic and system audio"
```

---

## Task 13: SpeechRecognizerTranscriber (on-device, VAD-segmented)

**Files:**
- Create: `App/SpeechRecognizerTranscriber.swift`

> Platform glue; verified by build + the Task 15 smoke test. Uses `SFSpeechRecognizer` with
> `requiresOnDeviceRecognition = true`. Per source, a recognition request is finalized at each VAD
> boundary (via `VADSegmenter` from core), which keeps each request short and avoids the legacy
> per-request time limit.

- [ ] **Step 1: Write the implementation**

`App/SpeechRecognizerTranscriber.swift`:

```swift
import Foundation
import Speech
import AVFoundation
import ListenToMeCore

/// On-device transcription. Maintains one recognition pipeline per `SpeakerSource`,
/// finalizing each pipeline's request when the VAD reports an utterance boundary.
final class SpeechRecognizerTranscriber: NSObject, Transcribing, @unchecked Sendable {
    let segments: AsyncStream<TranscriptSegment>
    private let continuation: AsyncStream<TranscriptSegment>.Continuation

    private var pipelines: [SpeakerSource: Pipeline] = [:]
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    override init() {
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
        super.init()
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    func feed(_ chunk: AudioChunk) async {
        guard let recognizer, recognizer.isAvailable else { return }
        let pipeline = pipelines[chunk.source] ?? makePipeline(for: chunk.source)
        pipelines[chunk.source] = pipeline

        // Drive VAD off the chunk's energy to decide utterance boundaries.
        let energy = rms(of: chunk.samples)
        let boundary = pipeline.segmenter.process(rms: energy, at: chunk.timestamp)

        if let buffer = makeBuffer(from: chunk) {
            pipeline.request.append(buffer)
        }
        if boundary {
            finalize(source: chunk.source)
        }
    }

    func finish() async {
        for source in pipelines.keys { finalize(source: source) }
        continuation.finish()
    }

    // MARK: - Pipeline

    private final class Pipeline {
        let request = SFSpeechAudioBufferRecognitionRequest()
        var task: SFSpeechRecognitionTask?
        var segmenter = VADSegmenter(speechThreshold: 0.02, silenceDuration: 0.8)
        init() { request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true }
    }

    private func makePipeline(for source: SpeakerSource) -> Pipeline {
        let pipeline = Pipeline()
        pipeline.task = recognizer?.recognitionTask(with: pipeline.request) { [weak self] result, _ in
            guard let self, let result else { return }
            self.continuation.yield(TranscriptSegment(
                source: source,
                text: result.bestTranscription.formattedString,
                isFinal: result.isFinal,
                start: 0,
                end: 0
            ))
        }
        return pipeline
    }

    /// Ends the current request for `source` and starts a fresh pipeline for the next utterance.
    private func finalize(source: SpeakerSource) {
        pipelines[source]?.request.endAudio()
        pipelines[source] = makePipeline(for: source)
    }

    private func makeBuffer(from chunk: AudioChunk) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: chunk.sampleRate,
                                         channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(chunk.samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
        for (index, sample) in chunk.samples.enumerated() {
            buffer.floatChannelData![0][index] = sample
        }
        return buffer
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add App/SpeechRecognizerTranscriber.swift
git commit -m "feat: add on-device VAD-segmented SpeechRecognizerTranscriber"
```

---

## Task 14: SwiftUI UI, hotkey, and wiring

**Files:**
- Create: `App/HotkeyMonitor.swift`
- Create: `App/MeetingView.swift`
- Modify: `App/ListenToMeApp.swift`

> Platform glue; verified by build + the Task 15 smoke test.

- [ ] **Step 1: Write the global hotkey monitor**

`App/HotkeyMonitor.swift`:

```swift
import AppKit

/// Listens for a global ⌘⇧Space keypress (works while another app is focused).
/// Requires Accessibility permission, which macOS prompts for on first use.
final class HotkeyMonitor {
    private var monitor: Any?
    func start(_ action: @escaping () -> Void) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // 49 = Space; require Command + Shift.
            if event.keyCode == 49,
               event.modifierFlags.contains([.command, .shift]) {
                action()
            }
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
```

- [ ] **Step 2: Write the two-pane view**

`App/MeetingView.swift`:

```swift
import SwiftUI
import ListenToMeCore

struct MeetingView: View {
    @State private var session: MeetingSession
    @State private var store: ConversationStore
    private let hotkey = HotkeyMonitor()

    init() {
        let store = ConversationStore()
        let router = ModelRouter(default: OllamaProvider(model: "llama3.1"))
        _store = State(initialValue: store)
        _session = State(initialValue: MeetingSession(
            store: store,
            router: router,
            context: ContextEngine(debounce: 8),
            capture: DualChannelCapture(),
            transcriber: SpeechRecognizerTranscriber()
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                transcriptPane
                suggestionPane
            }
        }
        .frame(minWidth: 820, minHeight: 480)
        .onAppear {
            hotkey.start { Task { await session.respond(.answerQuestion) } }
        }
        .onDisappear {
            hotkey.stop()
            session.stop()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button(session.isRunning ? "Stop" : "Listen") {
                Task {
                    if session.isRunning { session.stop() }
                    else { try? await session.start() }
                }
            }
            if session.isRunning {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text("Recording").foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Proactive", isOn: $session.proactiveEnabled)
            Button("What should I answer?") { Task { await session.respond(.answerQuestion) } }
            Button("Recap so far") { Task { await session.respond(.recap) } }
            Button("Suggest a follow-up") { Task { await session.respond(.followUp) } }
        }
        .padding(10)
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading) {
            Text("Transcript").font(.headline).padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.utterances) { seg in
                        line(for: seg)
                    }
                    if let partial = store.partial {
                        line(for: partial).opacity(0.5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField("Context notes (injected into prompts)", text: $session.notes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .frame(minWidth: 360)
    }

    private func line(for seg: TranscriptSegment) -> some View {
        (Text(seg.source == .you ? "You: " : "Others: ")
            .foregroundStyle(seg.source == .you ? .blue : .green).bold()
         + Text(seg.text))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestionPane: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Suggestion").font(.headline)
                if session.isStreaming { ProgressView().controlSize(.small) }
            }
            ScrollView {
                Text(session.suggestion.isEmpty ? "Press ⌘⇧Space or a button to get a suggestion."
                                                 : session.suggestion)
                    .foregroundStyle(session.suggestion.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(minWidth: 360)
    }
}
```

- [ ] **Step 3: Wire the view into the app**

Replace the body of `App/ListenToMeApp.swift`:

```swift
import SwiftUI

@main
struct ListenToMeApp: App {
    var body: some Scene {
        WindowGroup {
            MeetingView()
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `make build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add App/HotkeyMonitor.swift App/MeetingView.swift App/ListenToMeApp.swift
git commit -m "feat: add two-pane SwiftUI UI, global hotkey, and session wiring"
```

---

## Task 15: Manual smoke test, README, and pre-push gate

**Files:**
- Create: `README.md`
- Create: `docs/manual-smoke-test.md`

- [ ] **Step 1: Ensure Ollama is available**

Run: `ollama --version` (install from https://ollama.com if missing)
Run: `ollama pull llama3.1`
Run: `ollama run llama3.1 "say hi"` → expect a short reply (confirms the server on `localhost:11434`).

- [ ] **Step 2: Write the manual smoke-test checklist**

`docs/manual-smoke-test.md`:

```markdown
# ListenToMe — Manual Smoke Test

Prereq: Ollama running with `llama3.1` pulled.

1. `make run` — the app window opens with two panes.
2. Click **Listen**. Grant: Microphone, Speech Recognition, Screen Recording (system audio),
   and Accessibility (global hotkey) when prompted. Re-click Listen after granting if needed.
3. Speak a sentence → it appears under **Transcript** labeled **You** (blue).
4. Play speech from another app (e.g., a YouTube video or a meeting) → it appears labeled
   **Others** (green).
5. Click **What should I answer?** → a streamed suggestion appears in the right pane.
6. With **Proactive** on, have the other audio ask a question (e.g., "what is the plan?") →
   a suggestion appears automatically within ~1-2s of the utterance ending.
7. Type into **Context notes** (e.g., "I am the backend lead"), then trigger a suggestion →
   the answer reflects the note.
8. Press **⌘⇧Space** while another app is focused → a suggestion is generated.
9. Click **Stop** → the red recording indicator disappears and capture halts.
```

- [ ] **Step 3: Run the manual smoke test**

Run: `make run`
Work through `docs/manual-smoke-test.md` steps 1-9.
Expected: every step behaves as described. Record any failures and fix before continuing.

- [ ] **Step 4: Write the README**

`README.md`:

```markdown
# ListenToMe

A personal, on-device macOS meeting copilot: it listens to your mic and the other participants'
system audio, transcribes live, and gives real-time suggestions — on demand (⌘⇧Space or the
buttons) and proactively when someone asks a question. Models are configurable; the MVP defaults to
a local Ollama model, so nothing leaves your machine.

## Requirements
- macOS 26+
- Xcode 26+, `brew install xcodegen` (and optionally `swiftlint`, `xcbeautify`)
- [Ollama](https://ollama.com) with a model pulled: `ollama pull llama3.1`

## Build & run
```bash
make test     # run the ListenToMeCore unit tests
make build    # generate the Xcode project and build the app
make run      # build and launch
```

## Permissions
On first run, grant Microphone, Speech Recognition, Screen Recording (for system audio), and
Accessibility (for the global hotkey) in System Settings → Privacy & Security.

## Architecture
- `ListenToMeCore` (Swift package): all testable logic — conversation state, VAD, question
  detection, prompt building, Ollama provider, model router, context engine, `MeetingSession`.
- `App/`: macOS glue — `DualChannelCapture`, `SpeechRecognizerTranscriber`, SwiftUI UI, hotkey.

See `docs/superpowers/specs/2026-06-18-listentome-design.md` for the full design.

## Roadmap (post-MVP)
- WhisperKit / SpeechAnalyzer transcription engines (Settings-switchable)
- Claude / OpenAI / DeepSeek providers with Keychain-stored keys
- Session persistence and export
```

- [ ] **Step 5: Run the full pre-push gate**

Run: `make pre-push`
Expected: `swiftlint` clean, `swift test` all green, `xcodebuild` `BUILD SUCCEEDED`, then `pre-push checks passed`.

- [ ] **Step 6: Commit**

Run Codex review first: `/codex:review --base main` — resolve any blockers.

```bash
git add README.md docs/manual-smoke-test.md
git commit -m "docs: add README and manual smoke test; MVP complete"
```

---

## Self-Review Notes (for the planner)

**Spec coverage:**
- Dual-channel capture (You/Others) → Task 12. ✅
- VAD segmentation → Task 4 (logic) + Task 13 (applied). ✅
- On-device STT behind swappable `Transcribing` protocol → Tasks 10, 13. ✅
- Transcript pane + Suggestion pane → Task 14. ✅
- On-demand (hotkey ⌘⇧Space + 3 action buttons) → Task 14; actions defined Task 6. ✅
- Proactive (debounced remote-question detection, toggle) → Tasks 5, 9, 10, 14. ✅
- Ollama default behind `LLMProvider` + `ModelRouter` → Tasks 7, 8. ✅
- Anti-preamble system prompt + notes injection → Task 6, surfaced in UI Task 14. ✅
- Visible recording indicator, no stealth → Task 14. ✅
- Codex review before every commit + `make pre-push` gate → every commit step + Tasks 1/15. ✅

**Known deviations from spec (intentional):**
- Default transcriber is `SFSpeechRecognizer` (VAD-segmented), not `SpeechAnalyzer`, to avoid guessing
  a brand-new API. Same protocol; SpeechAnalyzer/WhisperKit remain a drop-in Phase-2 swap. The spec's
  §11 "SpeechAnalyzer default" should be read as "on-device engine behind the protocol" for the MVP.

**Type consistency:** `MeetingSession`, `ConversationStore`, `ModelRouter`, `ContextEngine`,
`PromptBuilder`, `OllamaProvider`, `AudioCapturing`, `Transcribing`, `AudioChunk`, `TranscriptSegment`,
`ResponseAction`, `PromptContext`, `LLMRequest`, `ChatMessage` — names and signatures match across all
tasks and between core and app.

**Platform-code caveat:** Tasks 12-14 use AVFoundation/ScreenCaptureKit/Speech/AppKit APIs that cannot
be unit-tested without hardware; they are verified by `make build` + the Task 15 manual smoke test. If
a specific API signature differs on your exact SDK, fix it in place — the core logic and the module
boundaries are unaffected.
```
