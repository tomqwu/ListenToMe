# OpenAI-compatible Endpoint Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user point ListenToMe at any OpenAI-compatible `/v1/chat/completions` endpoint (LM Studio, OpenRouter, vLLM, DeepSeek, …) as an alternative AI backend to Ollama, selected globally in Settings.

**Architecture:** Generalize the existing, fully-tested-but-dormant `DeepSeekProvider` into a configurable `OpenAICompatibleProvider`; add a pure `/v1/models` parser in Core + an App-side HTTP fetcher; add `aiBackend` + `openAIBaseURL` settings (key in Keychain); and branch the provider factory, model discovery, and privacy indicator on the chosen backend. Spec: `docs/superpowers/specs/2026-06-30-openai-compatible-endpoints-design.md`.

**Tech Stack:** Swift 6, SwiftUI (macOS), SwiftPM `ListenToMeCore` library + `App/` target.

## Global Constraints

- **Engine code (`Sources/ListenToMeCore`) has tests** (`swift test`); **the `App/` target has NO test bundle** — App changes are verified by `make build` + a manual `make run`. Do not invent App-target unit tests.
- **`LLMProvider` protocol is unchanged.** Providers are built per role by `MeetingSession`'s `makeProvider: @Sendable (String) -> any LLMProvider` factory.
- **Backend default is `"ollama"`** — existing users see no behavior change.
- **Base-URL convention:** the user enters the OpenAI base **including `/v1`** (e.g. `http://localhost:1234/v1`). The provider appends `chat/completions`; discovery appends `models`.
- **API key is optional:** send `Authorization: Bearer <key>` **only when the key is non-empty** (LM Studio / vLLM often need none).
- **Keychain accounts:** the OpenAI key uses a **new account `"openai-compatible"`**; the existing `"ollama"` account is untouched.
- **Do NOT touch the appearance default** (`SettingsView.swift` line ~52, still `"dark"` on this branch) — that change lives in PR #51.
- **Definition of Done (per `CLAUDE.md`):** `make build` clean, `swift test` green, `make e2e` passes; `README.md` + `docs/manual-smoke-test.md` updated; the PR closes issue #52 and states what was verified.
- Build: `make build`. Engine tests: `swift test`. Full check: `make e2e`.

---

### Task 1: Generalize the dormant provider → `OpenAICompatibleProvider`

**Files:**
- Rename: `Sources/ListenToMeCore/DeepSeekProvider.swift` → `Sources/ListenToMeCore/OpenAICompatibleProvider.swift`
- Rename: `Tests/ListenToMeCoreTests/DeepSeekProviderTests.swift` → `Tests/ListenToMeCoreTests/OpenAICompatibleProviderTests.swift`

**Interfaces:**
- Produces: `OpenAICompatibleProvider` (`LLMProvider`) with inits
  `init(id: String = "openai-compatible", model: String, apiKey: String?, baseURL: URL, urlSession: URLSession = .shared)`
  and the injectable `init(id:model:apiKey:baseURL:lineSource:)`; static `requestBody(model:request:) -> Data`;
  and `OpenAICompatibleParser.delta(fromLine:)` / `.isDone(line:)`. Error domain string `"OpenAICompatible"`.

- [ ] **Step 1: Rename both files (preserve history)**

```bash
cd /Users/tomwu/Projects/ListenToMe
git mv Sources/ListenToMeCore/DeepSeekProvider.swift Sources/ListenToMeCore/OpenAICompatibleProvider.swift
git mv Tests/ListenToMeCoreTests/DeepSeekProviderTests.swift Tests/ListenToMeCoreTests/OpenAICompatibleProviderTests.swift
```

- [ ] **Step 2: Replace the provider file contents**

Overwrite `Sources/ListenToMeCore/OpenAICompatibleProvider.swift` with exactly:

```swift
import Foundation

/// Pure parsing of OpenAI-compatible SSE streaming responses (`/chat/completions`).
public enum OpenAICompatibleParser {
    public static func delta(fromLine line: String) -> String? {
        let stripped = stripDataPrefix(line)
        guard !stripped.isEmpty else { return nil }
        guard stripped != "[DONE]" else { return nil }
        guard let data = stripped.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }

    public static func isDone(line: String) -> Bool {
        stripDataPrefix(line).trimmingCharacters(in: .whitespaces) == "[DONE]"
    }

    private static func stripDataPrefix(_ line: String) -> String {
        if line.hasPrefix("data: ") {
            return String(line.dropFirst(6))
        } else if line.hasPrefix("data:") {
            return String(line.dropFirst(5))
        }
        return ""
    }
}

/// Streams chat completions from any OpenAI-compatible `/v1/chat/completions` endpoint
/// (LM Studio, OpenRouter, vLLM, DeepSeek, …). `baseURL` is the OpenAI base *including* `/v1`;
/// the provider appends `chat/completions`. `apiKey` is optional — a Bearer header is sent only
/// when it is non-empty (local servers like LM Studio / vLLM often need no key).
public struct OpenAICompatibleProvider: LLMProvider {
    public let id: String
    private let model: String
    private let apiKey: String?
    private let baseURL: URL
    private let lineSource: @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error>

    /// Designated initializer. `lineSource` yields raw SSE lines; injectable for testing.
    public init(id: String = "openai-compatible", model: String, apiKey: String?, baseURL: URL,
                lineSource: @escaping @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error>) {
        self.id = id
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.lineSource = lineSource
    }

    /// Live initializer that talks to a real OpenAI-compatible endpoint over HTTP.
    public init(id: String = "openai-compatible", model: String, apiKey: String?, baseURL: URL,
                urlSession: URLSession = .shared) {
        self.init(id: id, model: model, apiKey: apiKey, baseURL: baseURL,
                  lineSource: Self.makeLiveLineSource(model: model, apiKey: apiKey,
                                                      baseURL: baseURL, session: urlSession))
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
                        if OpenAICompatibleParser.isDone(line: line) { break }
                        if let delta = OpenAICompatibleParser.delta(fromLine: line), !delta.isEmpty {
                            continuation.yield(delta)
                        }
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
        model: String, apiKey: String?, baseURL: URL, session: URLSession
    ) -> @Sendable (LLMRequest) -> AsyncThrowingStream<String, Error> {
        return { request in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        var urlRequest = URLRequest(
                            url: baseURL.appendingPathComponent("chat/completions"))
                        urlRequest.httpMethod = "POST"
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        if let apiKey, !apiKey.isEmpty {
                            urlRequest.setValue("Bearer \(apiKey)",
                                                forHTTPHeaderField: "Authorization")
                        }
                        urlRequest.httpBody = requestBody(model: model, request: request)
                        let (bytes, response) = try await session.bytes(for: urlRequest)
                        if let http = response as? HTTPURLResponse,
                           !(200...299).contains(http.statusCode) {
                            throw NSError(
                                domain: "OpenAICompatible", code: http.statusCode,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "Endpoint returned HTTP \(http.statusCode)."])
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

- [ ] **Step 3: Update the test file — rename identifiers, fix domain, optional-key helper**

In `Tests/ListenToMeCoreTests/OpenAICompatibleProviderTests.swift` apply these exact replacements (every occurrence):
- `DeepSeekStubURLProtocol` → `OpenAICompatibleStubURLProtocol`
- `DeepSeekParser` → `OpenAICompatibleParser`
- `DeepSeekProvider` → `OpenAICompatibleProvider`
- `makeDeepSeekStubSession` → `makeStubSession`
- `makeDeepSeekProvider` → `makeProvider`
- `deepSeekSampleRequest` → `sampleRequest`
- the class name `final class DeepSeekProviderTests:` → `final class OpenAICompatibleProviderTests:`
- the assertion `XCTAssertEqual(err.domain, "DeepSeek")` → `XCTAssertEqual(err.domain, "OpenAICompatible")`

Then change the `makeProvider` helper so `apiKey` is optional and the call passes it through:

```swift
private func makeProvider(
    model: String = "test-model",
    apiKey: String? = "test-key",
    baseURL: URL = URL(string: "http://stub.local")!,
    session: URLSession
) -> OpenAICompatibleProvider {
    OpenAICompatibleProvider(model: model, apiKey: apiKey, baseURL: baseURL, urlSession: session)
}
```

- [ ] **Step 4: Add the new "no key → no Authorization header" test (RED behavior)**

Add this test method inside the `OpenAICompatibleProviderTests` class (after `testLiveRequestCarriesBearerAuthHeader`):

```swift
    // MARK: 9. No apiKey → no Authorization header (local servers need none)

    func testLiveRequestOmitsAuthWhenNoKey() async throws {
        var capturedRequest: URLRequest?
        OpenAICompatibleStubURLProtocol.handler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: URL(string: "http://stub.local/chat/completions")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("data: [DONE]".utf8))
        }
        let provider = makeProvider(apiKey: nil, session: makeStubSession())
        for try await _ in provider.stream(sampleRequest()) {}
        let req = try XCTUnwrap(capturedRequest)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }
```

- [ ] **Step 5: Run the provider tests**

Run: `swift test --filter OpenAICompatibleProviderTests`
Expected: PASS — all renamed tests plus the new `testLiveRequestOmitsAuthWhenNoKey` (verifies the optional-key path; the old code always sent Bearer, the new `if let apiKey, !apiKey.isEmpty` guard makes this pass).

- [ ] **Step 6: Commit**

```bash
git add Sources/ListenToMeCore/OpenAICompatibleProvider.swift Tests/ListenToMeCoreTests/OpenAICompatibleProviderTests.swift
git commit -m "feat(core): generalize DeepSeekProvider into OpenAICompatibleProvider (optional key, /v1 base)"
```

---

### Task 2: `/v1/models` discovery — pure parser (Core, TDD) + HTTP fetcher (App)

**Files:**
- Create: `Sources/ListenToMeCore/OpenAIModelParsing.swift`
- Create: `Tests/ListenToMeCoreTests/OpenAIModelParsingTests.swift`
- Create: `App/OpenAIModels.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `OpenAIModelParsing.ids(from: Data) -> [String]` (Core, public); `OpenAIModels.installed(baseURL: URL, apiKey: String?) async -> [String]` (App).

- [ ] **Step 1: Write the failing parser test**

Create `Tests/ListenToMeCoreTests/OpenAIModelParsingTests.swift`:

```swift
import XCTest
@testable import ListenToMeCore

final class OpenAIModelParsingTests: XCTestCase {
    func testParsesIdsFromDataArray() {
        let json = #"{"object":"list","data":[{"id":"gpt-4o","object":"model"},{"id":"llama-3.1-8b"}]}"#
        XCTAssertEqual(OpenAIModelParsing.ids(from: Data(json.utf8)), ["gpt-4o", "llama-3.1-8b"])
    }

    func testEmptyOnMissingDataKey() {
        XCTAssertEqual(OpenAIModelParsing.ids(from: Data(#"{"object":"list"}"#.utf8)), [])
    }

    func testEmptyOnGarbage() {
        XCTAssertEqual(OpenAIModelParsing.ids(from: Data("not json".utf8)), [])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter OpenAIModelParsingTests`
Expected: FAIL to compile — `OpenAIModelParsing` is not defined yet.

- [ ] **Step 3: Implement the parser**

Create `Sources/ListenToMeCore/OpenAIModelParsing.swift`:

```swift
import Foundation

/// Pure parsing of an OpenAI-compatible `/v1/models` response body.
public enum OpenAIModelParsing {
    /// Returns the model ids from `{ "data": [ { "id": ... } ] }`. Empty on garbage / empty / missing.
    public static func ids(from data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["id"] as? String }
    }
}
```

- [ ] **Step 4: Run the parser test**

Run: `swift test --filter OpenAIModelParsingTests`
Expected: PASS (3/3).

- [ ] **Step 5: Create the App-side HTTP fetcher**

Create `App/OpenAIModels.swift`:

```swift
import Foundation
import ListenToMeCore

/// Queries an OpenAI-compatible endpoint for its available models (`GET {baseURL}/models`).
/// `baseURL` is the OpenAI base *including* `/v1`. Lists all returned model ids — the `/v1/models`
/// shape exposes no chat-capability flag, so (unlike `OllamaModels`) there is no capability probe.
enum OpenAIModels {
    static func installed(baseURL: URL, apiKey: String?) async -> [String] {
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        req.timeoutInterval = 5
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return OpenAIModelParsing.ids(from: data)
    }
}
```

- [ ] **Step 6: Build (App target must compile)**

Run: `make build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Sources/ListenToMeCore/OpenAIModelParsing.swift Tests/ListenToMeCoreTests/OpenAIModelParsingTests.swift App/OpenAIModels.swift
git commit -m "feat: OpenAI-compatible /v1/models discovery (pure Core parser + App fetcher)"
```

---

### Task 3: Wire the backend — settings, factory dispatch, discovery, privacy, UI

**Files:**
- Modify: `App/SettingsView.swift` (ProviderSettings keys; `@State` + UI; `save()`)
- Modify: `App/MeetingView.swift` (`buildProvider`, `openAIKey`, `discoverModels`, `isCloudActive`, `makeProvider` closure, `reloadModels`/`reloadAndHealModels`, footer)

**Interfaces:**
- Consumes: `OpenAICompatibleProvider` (Task 1), `OpenAIModels.installed` (Task 2), existing `OllamaProvider`, `OllamaModels.chatModels`, `KeychainStore`, `ProviderSettings`.
- Produces: `ProviderSettings.aiBackend` / `.openAIBaseURL`; `MeetingView.buildProvider(model:)`, `.openAIKey()`, `.discoverModels()`, `.isCloudActive()`, `.isLocalHost(_:)` (all `static`).

- [ ] **Step 1: Add the settings keys**

In `App/SettingsView.swift`, immediately after the `ollamaModel` property (the block that closes at line 9), insert:

```swift
    /// Which AI backend the panes use: "ollama" (default) or "openai" (an OpenAI-compatible endpoint).
    static var aiBackend: String {
        get { UserDefaults.standard.string(forKey: "aiBackend") ?? "ollama" }
        set { UserDefaults.standard.set(newValue, forKey: "aiBackend") }
    }
    /// Base URL for the OpenAI-compatible endpoint, including `/v1` (e.g. http://localhost:1234/v1).
    static var openAIBaseURL: String {
        get { UserDefaults.standard.string(forKey: "openAIBaseURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openAIBaseURL") }
    }
```

- [ ] **Step 2: Add the static provider/discovery/privacy helpers to `MeetingView`**

In `App/MeetingView.swift`, immediately after the existing `ollamaBaseURL()` static method (ends at line ~177), insert:

```swift
    private static func openAIKey() -> String? {
        let k = KeychainStore.get("openai-compatible")
        return (k?.isEmpty == false) ? k : nil
    }

    /// Builds the per-pane provider for the currently-selected AI backend. Reads settings live so a
    /// backend change in Settings applies on the next provider rebuild (Settings dismiss → reloadAndHealModels).
    static func buildProvider(model: String) -> any LLMProvider {
        if ProviderSettings.aiBackend == "openai",
           !ProviderSettings.openAIBaseURL.isEmpty,
           let url = URL(string: ProviderSettings.openAIBaseURL) {
            return OpenAICompatibleProvider(model: model, apiKey: openAIKey(), baseURL: url)
        }
        return OllamaProvider(model: model, baseURL: ollamaBaseURL(), apiKey: ollamaKey())
    }

    /// Discovers selectable model ids for the current backend.
    static func discoverModels() async -> [String] {
        if ProviderSettings.aiBackend == "openai",
           !ProviderSettings.openAIBaseURL.isEmpty,
           let url = URL(string: ProviderSettings.openAIBaseURL) {
            return await OpenAIModels.installed(baseURL: url, apiKey: openAIKey())
        }
        return await OllamaModels.chatModels(baseURL: ollamaBaseURL(), apiKey: ollamaKey())
    }

    private static func isLocalHost(_ url: URL) -> Bool {
        let host = url.host?.lowercased()
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    /// True when the active backend sends data off-device (drives the footer's privacy line).
    static func isCloudActive() -> Bool {
        if ProviderSettings.aiBackend == "openai" {
            guard !ProviderSettings.openAIBaseURL.isEmpty,
                  let url = URL(string: ProviderSettings.openAIBaseURL) else { return false }
            return !isLocalHost(url)
        }
        return ollamaKey() != nil
    }
```

- [ ] **Step 3: Route the provider factory through `buildProvider`**

In `App/MeetingView.swift`, replace the `makeProvider:` closure (lines ~155-157):

```swift
            makeProvider: { model in
                OllamaProvider(model: model, baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey())
            },
```
with:
```swift
            makeProvider: { model in
                Self.buildProvider(model: model)
            },
```

- [ ] **Step 4: Route model discovery through `discoverModels`**

In `App/MeetingView.swift`, in `reloadModels()` (lines ~708-711) replace its body assignment:

```swift
        chatModels = await OllamaModels.chatModels(
            baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey())
```
with:
```swift
        chatModels = await Self.discoverModels()
```

And in `reloadAndHealModels()` (lines ~717-719) replace the same opening assignment:

```swift
        chatModels = await OllamaModels.chatModels(
            baseURL: Self.ollamaBaseURL(), apiKey: Self.ollamaKey())
```
with:
```swift
        chatModels = await Self.discoverModels()
```
(Leave the rest of `reloadAndHealModels` — the `ModelRanking.roleDefaults` healing loop — unchanged.)

- [ ] **Step 5: Generalize the footer's privacy indicator**

In `App/MeetingView.swift` `body`, replace (line ~199):

```swift
            CommandCenterFooter(cloudActive: Self.ollamaKey() != nil)
```
with:
```swift
            CommandCenterFooter(cloudActive: Self.isCloudActive())
```

- [ ] **Step 6: Add the Settings UI — state, fields, persistence**

In `App/SettingsView.swift`, add three `@State` properties after `@State private var speakerDiarization: Bool` (line ~137):

```swift
    @State private var aiBackend: String
    @State private var openAIBaseURL: String
    @State private var openAIKey: String
```

In `init()`, after the `_speakerDiarization` line (~146), add:

```swift
        _aiBackend = State(initialValue: ProviderSettings.aiBackend)
        _openAIBaseURL = State(initialValue: ProviderSettings.openAIBaseURL)
        _openAIKey = State(initialValue: KeychainStore.get("openai-compatible") ?? "")
```

In `body`, immediately after the Ollama-key caption `Text(...)` block (the one ending `.font(.caption).foregroundStyle(.secondary)` at line ~196), insert a new section:

```swift
            Divider()

            Picker("AI backend", selection: $aiBackend) {
                Text("Ollama").tag("ollama")
                Text("OpenAI-compatible endpoint").tag("openai")
            }
            if aiBackend == "openai" {
                TextField("Base URL (e.g. http://localhost:1234/v1)", text: $openAIBaseURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API key (optional)", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                Text(
                    "Point at any OpenAI-compatible /v1 endpoint \u{2014} LM Studio, OpenRouter, vLLM, etc. " +
                    "Include /v1 in the URL. The key is optional (local servers often need none) and is " +
                    "stored in your macOS Keychain. Local endpoints (localhost) stay private."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
```

In `save()`, after the existing `KeychainStore.set(ollamaKey...)` line (~253), add:

```swift
        ProviderSettings.aiBackend = aiBackend
        ProviderSettings.openAIBaseURL = openAIBaseURL
        KeychainStore.set(openAIKey.isEmpty ? nil : openAIKey, for: "openai-compatible")
```

- [ ] **Step 7: Build**

Run: `make build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Manual smoke check**

Run: `make run`. In **Settings → AI backend**, choose **OpenAI-compatible endpoint**, set Base URL to a running OpenAI-compatible server's `/v1` (e.g. LM Studio `http://localhost:1234/v1`, key blank), Save. Confirm: the per-pane model dropdowns populate from that endpoint's `/v1/models`; clicking a Quick action streams a reply from it; the footer reads "local models stay private" for a localhost URL (and the cloud wording for a remote URL). Switch back to **Ollama** and confirm the old behavior returns. (If you have no OpenAI-compatible server handy, at minimum confirm the UI shows/hides the fields and Save persists across reopen.)

- [ ] **Step 9: Commit**

```bash
git add App/SettingsView.swift App/MeetingView.swift
git commit -m "feat(app): global OpenAI-compatible backend toggle (settings, factory, discovery, privacy)"
```

---

### Task 4: Docs + final verification (Definition of Done)

**Files:**
- Modify: `README.md`
- Modify: `docs/manual-smoke-test.md`

**Interfaces:** none (docs + verification).

- [ ] **Step 1: README — mention the OpenAI-compatible backend**

Read `README.md`, find where it describes the Ollama / model setup (the BYO-model / providers area). Add this sentence there (adapt surrounding Markdown to fit the sentence cleanly):

```markdown
You can also point ListenToMe at any **OpenAI-compatible endpoint** (LM Studio, OpenRouter, vLLM, …) in **Settings → AI backend** — enter the base URL including `/v1` and an optional API key. Still bring-your-own-model, and fully private when the endpoint is local.
```

- [ ] **Step 2: Smoke-test doc — add an endpoint-config step**

In `docs/manual-smoke-test.md`, append this subsection at the end of the file (additive, to avoid colliding with PR #51's edits to the numbered steps):

```markdown

## OpenAI-compatible endpoint (optional)

1. Start any OpenAI-compatible server locally (e.g. LM Studio on `http://localhost:1234/v1`).
2. **Settings → AI backend → OpenAI-compatible endpoint**; set the Base URL to that server's `/v1`
   (key blank for a local server); Save.
3. Confirm the per-pane model dropdowns populate from the endpoint's `/v1/models`, and that a Quick
   action streams a reply. The footer should still read "local models stay private" for a localhost URL.
4. Switch the backend back to **Ollama** and confirm normal operation resumes.
```

- [ ] **Step 3: Final verification**

Run: `make build` → BUILD SUCCEEDED.
Run: `swift test` → all engine tests pass (includes `OpenAICompatibleProviderTests`, `OpenAIModelParsingTests`).
Run: `make e2e` → passes (unchanged Ollama contract test; the OpenAI path has no e2e by design).

- [ ] **Step 4: Commit**

```bash
git add README.md docs/manual-smoke-test.md
git commit -m "docs: document OpenAI-compatible endpoint support (closes #52)"
```

---

## Self-Review

**Spec coverage:**
- Generalize dormant provider (configurable id, optional key, `/v1`) → Task 1. ✓
- Settings keys (`aiBackend`, `openAIBaseURL`) + Keychain `"openai-compatible"` → Task 3 Steps 1, 6. ✓
- Factory dispatch in `makeProvider` → Task 3 Steps 2-3 (`buildProvider`). ✓
- `/v1/models` discovery (pure Core parser + App fetch, list all ids) → Task 2; dispatch → Task 3 Step 4 (`discoverModels`). ✓
- Settings UI (backend picker + base URL + optional key) → Task 3 Step 6. ✓
- Privacy indicator (localhost = private) → Task 3 Steps 2, 5 (`isCloudActive`/`isLocalHost`). ✓
- Tests (provider contract + optional-key + parse) → Tasks 1, 2. ✓
- Docs + close #52 → Task 4. ✓
- Out-of-scope items (per-pane backends, named lists, capability filtering, OpenAI e2e, ModelRouter) → not implemented. ✓

**Placeholder scan:** No TBD/vague steps — every code step shows literal code; the one prose doc edit (README) gives the exact sentence to insert. ✓

**Type consistency:** `OpenAICompatibleProvider` / `OpenAICompatibleParser` (Task 1) used by name nowhere else needing change; `OpenAIModelParsing.ids(from:)` (Task 2) consumed by `OpenAIModels.installed` (Task 2) and indirectly via `discoverModels` (Task 3); `buildProvider`/`discoverModels`/`openAIKey`/`isCloudActive`/`isLocalHost` defined in Task 3 Step 2 and used in Steps 3-5; `ProviderSettings.aiBackend`/`.openAIBaseURL` defined in Step 1 and read in Steps 2, 6. All consistent. ✓

**Note on branch interaction:** `docs/manual-smoke-test.md` is also edited by PR #51; Task 4 appends a new subsection rather than touching the numbered steps to minimize merge conflict. The appearance default is deliberately untouched (PR #51 owns it).
