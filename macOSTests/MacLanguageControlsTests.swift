import AppKit
import SwiftUI
import XCTest
import ListenToMeCore

/// Exercises the actual shared native controls and Core session binding without opening personal
/// history, requesting audio permissions, using cloud inference or requiring a desktop unlock.
@MainActor
final class MacLanguageControlsTests: XCTestCase {
    func testActualTranslationStatusMeetsContrastOnMacSurfacesAndAppearances() async throws {
        // Native HighContrast appearance names did not propagate colorSchemeContrast in
        // the preserved first attempt. This matrix covers only established Aqua/Dark Aqua;
        // increased-contrast environment coverage remains separate. Never alter user settings.
        let appearances: [(NSAppearance.Name, ColorScheme, ColorSchemeContrast)] = [
            (.aqua, .light, .standard), (.darkAqua, .dark, .standard)
        ]
        let surfaces: [(String, Color)] = [("summary-card", Theme.cardBackground),
                                            ("language-rail", Theme.windowBackground)]
        for (name, scheme, contrast) in appearances {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for (surfaceName, surface) in surfaces {
                // This is the production availability branch, not a test Text or color swatch.
                // Its nil translator/configuration never starts language setup, inference or audio.
                let worker = LiveTranslationCoordinator()
                XCTAssertEqual(worker.availability.reason, "Record speech to translate.")
                let observed = MacTranslationRenderEnvironment()
                let content = MacTranslationStatusRenderHost(worker: worker, surface: surface, observed: observed)
                let host = NSHostingView(rootView: content)
                host.appearance = appearance
                let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 380, height: 90),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = appearance
                window.contentView = host
                window.orderFront(nil) // Owned offscreen window; never make it key or activate the app.
                defer { window.orderOut(nil); window.close() }
                host.frame = NSRect(x: 0, y: 0, width: 380, height: 90)
                // A bounded transaction settle allows the actual host's onAppear environment
                // readback. Missing appearance propagation is a render-setup failure, not red contrast.
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(3))
                while clock.now < deadline {
                    host.layoutSubtreeIfNeeded()
                    if observed.value?.colorScheme == scheme,
                       observed.value?.colorSchemeContrast == contrast,
                       let size = observed.contentSize, size.width > 0, size.height > 0 { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                let environment = try XCTUnwrap(observed.value, "Actual NSHostingView environment was not observed")
                XCTAssertEqual(environment.colorScheme, scheme)
                XCTAssertEqual(environment.colorSchemeContrast, contrast,
                               "Requested native appearance must reach SwiftUI before measuring")
                guard environment.colorScheme == scheme, environment.colorSchemeContrast == contrast else { continue }
                let contentSize = try XCTUnwrap(observed.contentSize, "Actual status bounds were not observed")
                XCTAssertGreaterThan(contentSize.width, 0)
                XCTAssertGreaterThan(contentSize.height, 0)
                XCTAssertLessThanOrEqual(contentSize.width + 40, host.bounds.width + 1,
                                         "The whole caption plus horizontal padding must fit the native host")
                XCTAssertLessThanOrEqual(contentSize.height + 40, host.bounds.height + 1,
                                         "The whole caption plus vertical padding must fit the native host")
                var captured: NSBitmapImageRep?
                var resolved: Color.Resolved?
                appearance.performAsCurrentDrawingAppearance {
                    host.layoutSubtreeIfNeeded()
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    captured = bitmap
                    resolved = surface.resolve(in: environment)
                }
                let bitmap = try XCTUnwrap(captured, "Native status screenshot unavailable")
                let image = try XCTUnwrap(bitmap.cgImage)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let label = name.rawValue + "-" + surfaceName
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = "Actual Mac translation status " + label
                attachment.lifetime = .keepAlways; add(attachment)
                let measurement = try MacTranslationStatusContrast.measure(image)
                let background = try XCTUnwrap(resolved)
                let expectedRGB = [background.red, background.green, background.blue].map { Int(($0 * 255).rounded()) }
                XCTAssertEqual(background.opacity, 1, accuracy: 0.001)
                for channel in 0..<3 {
                    XCTAssertEqual(Double(measurement.background[channel]), Double(expectedRGB[channel]), accuracy: 3,
                                   "Measured surface must be the actual resolved production surface")
                }
                let detail = "appearance=\(label), scheme=\(environment.colorScheme), contrast=\(environment.colorSchemeContrast)\n"
                    + "resolvedBackground linearRGBA=\(background.linearRed),\(background.linearGreen),\(background.linearBlue),\(background.opacity)\n"
                    + measurement.description
                let evidence = XCTAttachment(string: detail)
                evidence.name = "Mac translation status contrast " + label
                evidence.lifetime = .keepAlways; add(evidence)
                XCTAssertGreaterThanOrEqual(measurement.ratio, 4.5,
                    "Actual essential caption must meet the small-text benchmark: " + detail)
                XCTAssertFalse(worker.isTranslating)
                XCTAssertNil(worker.translator)
            }
        }
    }

    func testWindowTranslationSuspensionFencesBothWorkersAndResumesOnReturn() async {
        let live = MacTranslationControlDouble(); live.holdNext = true
        let summary = MacTranslationControlDouble(); summary.holdNext = true
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { fatalError("No capture") }, makeTranscriber: { fatalError("No capture") },
            makeProvider: { _ in fatalError("No AI") }, models: [:])
        session.liveTranslation.translator = live; session.summaryTranslation.worker.translator = summary
        let lines: [TranscriptSegment] = ["First phrase.", "Second phrase."].map {
            .init(source: .others, text: $0, isFinal: true, start: 0, end: 1, language: "en")
        }
        let record = SessionRecord(id: "closed", title: "Saved", date: Date(), transcript: "", summary: "Summary.\nNext.",
            segments: lines, languageOptions: .init(translateTranscript: true, translationTarget: "fr",
                                                     summaryTranslationTarget: "fr"))
        XCTAssertTrue(session.restoreConversation(record)); session.summaryTranslation.request()
        for _ in 0..<300 { await Task.yield() }
        XCTAssertEqual(live.targets.count, 1); XCTAssertEqual(summary.targets.count, 1)
        session.setTranslationSuspended(true); live.release(); summary.release()
        for _ in 0..<300 { await Task.yield() }
        XCTAssertEqual(live.targets.count, 1); XCTAssertEqual(summary.targets.count, 1)
        XCTAssertNil(session.liveTranslation.text(for: lines[0])); XCTAssertNil(session.summaryTranslation.translatedText)
        session.setTranslationSuspended(false)
        for _ in 0..<300 { await Task.yield() }
        XCTAssertEqual(session.liveTranslation.text(for: lines[1]), "La réunion commence demain.")
        XCTAssertNotNil(session.summaryTranslation.translatedText)
        XCTAssertEqual(session.store.utterances, lines)
    }
    func testNativeControlsBindingTranslatesOriginalAndRendersNarrowOptions() async throws {
        let service = MacTranslationControlDouble()
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { fatalError("This text-only contract must not start capture") },
            makeTranscriber: { fatalError("This text-only contract must not start recognition") },
            makeProvider: { _ in fatalError("Translation must not use an AI provider") }, models: [:])
        session.liveTranslation.translator = service
        let original = TranscriptSegment(source: .others, text: "The meeting starts tomorrow.",
                                         isFinal: true, start: 0, end: 2, language: "en")
        session.store.apply(original)
        session.languageOptions = .init(translationTarget: "fr", summaryTranslationTarget: "ja")
        let controls = ConversationLanguageControls(options: Binding(get: { session.languageOptions },
            set: { session.languageOptions = $0 }), translation: session.liveTranslation, conversationID: "native-contract")
        let renderer = ImageRenderer(content: controls.padding(12).frame(width: 220, alignment: .topLeading)
            .background(Color.white).environment(\.colorScheme, .light))
        renderer.scale = 2
        let snapshot = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        image.name = "Mac narrow language controls SwiftUI render"; image.lifetime = .keepAlways; add(image)
        // SwiftUI's unhosted AX tree is unavailable in the locked test runner. Exercise the
        // control's real Binding and retain a SwiftUI render; the iOS UI suite presses the same
        // shared SwiftUI switch. This is not an installed Mac GUI acceptance claim.
        controls.options.translateTranscript = true
        for _ in 0..<200 { await Task.yield() }
        XCTAssertTrue(session.languageOptions.translateTranscript)
        XCTAssertEqual(session.languageOptions.summaryTranslationTarget, "ja")
        XCTAssertEqual(session.liveTranslation.text(for: original), "La réunion commence demain.")
        XCTAssertEqual(session.store.utterances, [original])
        XCTAssertEqual(service.targets, ["fr"])

    }

}

@MainActor private final class MacTranslationControlDouble: TranscriptTranslating {
    var targets: [String] = []
    var holdNext = false
    private var held: CheckedContinuation<Void, Never>?
    func release() { held?.resume(); held = nil }
    func sourceLanguage(for text: String, hint: String?) -> String? { hint ?? "en" }
    func availability(source: String, target: String) async -> FeatureAvailability { .ready }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        targets.append(target)
        if holdNext { holdNext = false; await withCheckedContinuation { held = $0 } }
        return "La réunion commence demain."
    }
    func cancel() {}
}

/// Test-only host: renders the production status and production surface; no replacement Text.
@MainActor private final class MacTranslationRenderEnvironment {
    var value: EnvironmentValues?
    var contentSize: CGSize?
}
@MainActor private struct MacTranslationStatusRenderHost: View {
    let worker: LiveTranslationCoordinator
    let surface: Color
    let observed: MacTranslationRenderEnvironment
    @Environment(\.self) private var environment
    var body: some View {
        OnDeviceTranslationStatus(worker: worker, target: "fr", context: "mac-contrast-contract")
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { observed.contentSize = geometry.size }
                        .onChange(of: geometry.size) { _, size in observed.contentSize = size }
                }.allowsHitTesting(false)
            }
            .padding(20).frame(width: 380, height: 90, alignment: .topLeading)
            .background(surface)
            .onAppear { observed.value = environment }
            .onChange(of: environment.colorScheme) { _, _ in observed.value = environment }
            .onChange(of: environment.colorSchemeContrast) { _, _ in observed.value = environment }
    }
}

/// Opaque sRGB raster measurement of this single-caption native host. No palette-only pass.
@MainActor private enum MacTranslationStatusContrast {
    struct Measurement {
        let ratio: Double
        let foreground: [Int]
        let background: [Int]
        let foregroundCount: Int
        let backgroundCount: Int
        var description: String {
            "native sRGB foreground=\(foreground), background=\(background), contrast=\(ratio), "
                + "inkPixels=\(foregroundCount), backgroundPixels=\(backgroundCount)"
        }
    }
    enum Invalid: Error { case bitmap, transparent, ambiguousBackground, ambiguousInk }
    static func ratio(_ a: [Int], _ b: [Int]) -> Double {
        func luminance(_ rgb: [Int]) -> Double {
            let c = rgb.map { Double($0) / 255 }.map {
                $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    static func measure(_ image: CGImage) throws -> Measurement {
        let width = image.width, height = image.height, count = width * height
        guard count > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw Invalid.bitmap }
        var bytes = [UInt8](repeating: 0, count: count * 4)
        let rendered = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw Invalid.bitmap }
        var histogram: [Int: Int] = [:]
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            guard bytes[offset + 3] == 255 else { throw Invalid.transparent }
            let key = Int(bytes[offset]) << 16 | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2])
            histogram[key, default: 0] += 1
        }
        func rgb(_ key: Int) -> [Int] { [(key >> 16) & 255, (key >> 8) & 255, key & 255] }
        let sorted = histogram.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let backdrop = sorted.first, backdrop.value >= count * 35 / 100 else { throw Invalid.ambiguousBackground }
        let background = rgb(backdrop.key)
        let candidates = sorted.dropFirst().filter {
            let color = rgb($0.key)
            return ratio(color, background) >= 1.3 && color.max()! - color.min()! <= 32
        }
        // This bounded host contains one short caption, unlike the larger iOS text crop.
        // Require a real repeated glyph plateau: a blank render or isolated dark pixel cannot pass.
        guard let ink = candidates.first, ink.value >= 24 else { throw Invalid.ambiguousInk }
        let foreground = rgb(ink.key)
        if candidates.dropFirst().contains(where: {
            $0.value >= ink.value / 2 && abs(ratio(rgb($0.key), background) - ratio(foreground, background)) > 0.75
        }) { throw Invalid.ambiguousInk }
        return Measurement(ratio: ratio(foreground, background), foreground: foreground, background: background,
                           foregroundCount: ink.value, backgroundCount: backdrop.value)
    }
}
