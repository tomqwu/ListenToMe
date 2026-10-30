import AppKit
import SwiftUI
import ListenToMeCore
import XCTest

private struct MissingAppleHistory: HistoryEmbedder {
    let signature = NaturalLanguageEmbedder().signature
    func embed(_ text: String) -> HistoryVector? { nil }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
}

private actor HostedRefreshEmbedder: HistoryEmbedder {
    nonisolated let signature = "hosted-refresh-v1"
    let available: Bool
    private var held = false
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    init(_ available: Bool) { self.available = available }
    func hold() { held = true }
    func isWaiting() -> Bool { waiter != nil }
    func release() { held = false; let old = waiter; waiter = nil; old?.resume() }
    func embed(_ text: String) async -> HistoryVector? {
        calls += 1
        if held { await withCheckedContinuation { waiter = $0 } }
        return available ? HistoryVector(model: signature, values: [1, 0]) : nil
    }
    func embedQuery(_ query: String, models: Set<String>) async -> [HistoryVector] {
        available && models.contains(signature) ? [HistoryVector(model: signature, values: [1, 0])] : []
    }
}

@MainActor private final class HistoryRefreshRenderState {
    var appeared = false
    var accessibilityEnabled = false
    var size: CGSize?
    var contentFrame: CGRect?
    var buttonFrame: CGRect?
    var refreshing = false
}

@MainActor private struct HistoryRefreshRenderHost: View {
    let search: HistorySearchModel
    let reload: () -> Void
    let observed: HistoryRefreshRenderState
    let size: CGSize
    @Environment(\.accessibilityEnabled) private var accessibilityEnabled

    var body: some View {
        HistoryRefreshControl(search: search, reload: reload)
            .background {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .named("refresh-native-host"))
                    Color.clear
                        .onAppear { recordControl(frame) }
                        .onChange(of: frame) { _, value in recordControl(value) }
                }.allowsHitTesting(false)
            }
            .padding(16).frame(width: size.width, height: size.height, alignment: .topLeading)
            .coordinateSpace(name: "refresh-native-host")
            .background(Theme.cardBackground)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { observed.size = geometry.size }
                        .onChange(of: geometry.size) { _, value in observed.size = value }
                }.allowsHitTesting(false)
            }
            .onAppear {
                observed.appeared = true
                observed.accessibilityEnabled = accessibilityEnabled
                observed.refreshing = search.isRefreshing
            }
            .onChange(of: accessibilityEnabled) { _, value in observed.accessibilityEnabled = value }
            .onChange(of: search.isRefreshing) { _, value in observed.refreshing = value }
    }
    private func recordControl(_ frame: CGRect) {
        observed.contentFrame = frame
        // With no issue the production VStack consists of exactly its one Button.
        // Retain that observed button rectangle when failure guidance appears below it.
        if search.refreshIssue == nil { observed.buttonFrame = frame }
    }

}

@MainActor
final class MacHistoryRefreshControlsTests: XCTestCase {
    func testActualSharedControlRefreshesLocalAppleAndPreservesLiteralSearch() throws {
        try runNative { try await self.exerciseActualSharedControlRefreshesLocalAppleAndPreservesLiteralSearch() }
    }

    func testActualControlDisablesHeldRefreshAndShowsFailureWithUsableRetry() throws {
        try runNative { try await self.exerciseActualControlDisablesHeldRefreshAndShowsFailureWithUsableRetry() }
    }

    private func runNative(_ exercise: @escaping @MainActor () async throws -> Void) throws {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        XCTAssertTrue(NSApp.setActivationPolicy(.accessory))
        defer { NSApp.setActivationPolicy(previousPolicy) }
        var finished = false
        var failure: Error?
        var worker: Task<Void, Never>?
        func finish() {
            guard !finished else { return }
            finished = true
            NSApp.stop(nil)
            if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(wake, atStart: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            worker = Task { @MainActor in
                do { try await exercise() } catch { failure = error }
                // Exercise defers close only its owned windows; held failures release/drain
                // before returning here, so stop cannot strand its maintenance operation.
                finish()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            guard !finished else { return }
            XCTFail("Native History Refresh exercise exceeded its bounded deadline")
            worker?.cancel() // Its catch releases/drains before finish; outer supervisor hard-bounds uncooperative work.
        }
        NSApp.run() // Synchronous XCTest entry, exactly the established transcript host lifecycle.
        XCTAssertTrue(finished, "Native loop returned before exercise completed")
        if let failure { throw failure }
    }

    private func exerciseActualSharedControlRefreshesLocalAppleAndPreservesLiteralSearch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Search Index")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(directory: root.appendingPathComponent("Conversations"))
        let row = SessionRecord(id: "one", title: "Owned fixture", date: Date(timeIntervalSince1970: 0),
                                transcript: "The airline delayed the aircraft at the airport terminal.", summary: "")
        try archive.save(row)
        let archiveURLs = try FileManager.default.contentsOfDirectory(at: archive.directoryURL,
                                                                      includingPropertiesForKeys: nil)
        let archiveBytes = try Dictionary(uniqueKeysWithValues: archiveURLs.map {
            ($0.lastPathComponent, try Data(contentsOf: $0))
        })
        let index = HistoryIndex(directory: folder, embedder: MissingAppleHistory())
        try await index.sync([row]); let file = folder.appendingPathComponent("one.vectors")
        let before = try Data(contentsOf: file)
        let model = HistorySearchModel(index: index, syncDelay: .zero, searchDelay: .zero)
        model.records = { [row] }
        var reloads = 0
        let rendered = HistoryRefreshRenderState()
        let host = NSHostingView(rootView: HistoryRefreshRenderHost(search: model, reload: { reloads += 1 },
            observed: rendered, size: CGSize(width: 360, height: 160)).environment(\.accessibilityEnabled, true))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.title = "ListenToMe History Refresh — synthetic native contract"
        NSApp.activate(); window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 160)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        try await waitForRender(host, observed: rendered, size: CGSize(width: 360, height: 160))
        try capture(host, name: "History local Refresh idle control")
        try await clickRefresh(host, window: window, observed: rendered)
        try await waitForAction { reloads == 1 }
        XCTAssertEqual(reloads, 1)
        await model.waitForMaintenance(); XCTAssertFalse(model.isRefreshing); XCTAssertNil(model.refreshIssue)
        let apple = await NaturalLanguageEmbedder().embed(row.transcript, transcribedIn: "en")
        if apple != nil {
            XCTAssertGreaterThan(try Data(contentsOf: file).count, before.count,
                                 "A formerly nil cached record must receive actual installed Apple vectors")
            print("HISTORY_REFRESH_APPLE_BRANCH=installed")
        } else {
            print("HISTORY_REFRESH_APPLE_BRANCH=unavailable; no installed-language quality claim")
        }
        model.search("aircraft"); await model.waitForSearch()
        XCTAssertEqual(model.results(for: "aircraft")?.map(\.id), [row.id])
        XCTAssertTrue(model.results(for: "aircraft")?.first?.matchesWords == true)
        let afterURLs = try FileManager.default.contentsOfDirectory(at: archive.directoryURL,
                                                                    includingPropertiesForKeys: nil)
        let afterBytes = try Dictionary(uniqueKeysWithValues: afterURLs.map {
            ($0.lastPathComponent, try Data(contentsOf: $0))
        })
        XCTAssertEqual(afterBytes, archiveBytes, "Refresh must preserve every actual archive file byte")
        try capture(host, name: "History local Refresh returned to idle")
    }
    private func exerciseActualControlDisablesHeldRefreshAndShowsFailureWithUsableRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let row = SessionRecord(id: "one", title: "Owned fixture", date: Date(timeIntervalSince1970: 0),
                                transcript: "private local fixture words", summary: "")
        let fresh = HostedRefreshEmbedder(true)
        let index = HistoryIndex(directory: root.appendingPathComponent("busy"), embedder: HostedRefreshEmbedder(false))
        try await index.sync([row]); await fresh.hold()
        let model = HistorySearchModel(index: index, syncDelay: .zero, searchDelay: .zero,
                                      makeFreshEmbedder: { fresh })
        model.records = { [row] }
        var reloads = 0
        let rendered = HistoryRefreshRenderState()
        let host = NSHostingView(rootView: HistoryRefreshRenderHost(search: model, reload: { reloads += 1 },
            observed: rendered, size: CGSize(width: 420, height: 180)).environment(\.accessibilityEnabled, true))
        let window = hostedWindow(host); defer { window.orderOut(nil); window.close() }
        do {
            try await waitForRender(host, observed: rendered, size: CGSize(width: 420, height: 180))
            try await clickRefresh(host, window: window, observed: rendered)
            for _ in 0..<150 {
                if await fresh.isWaiting() { break }; try await Task.sleep(for: .milliseconds(20))
            }
            let waiting = await fresh.isWaiting()
            guard waiting else {
                await fresh.release(); await model.waitForMaintenance()
                XCTFail("Refresh not held"); return
            }
            XCTAssertTrue(model.isRefreshing)
            for _ in 0..<150 {
                if rendered.refreshing { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(rendered.refreshing, "The actual hosted view must observe its busy update")
            try capture(host, name: "Actual History refresh busy control disabled")
            try await clickRefresh(host, window: window, observed: rendered)
            XCTAssertEqual(reloads, 1, "Disabled native control cannot schedule another refresh")
        } catch {
            // Never leave held inference alive after a locator, capture or cancellation error.
            await fresh.release()
            await model.waitForMaintenance()
            throw error
        }
        await fresh.release(); await model.waitForMaintenance()
        let calls = await fresh.calls; XCTAssertEqual(calls, 1)

        let folder = root.appendingPathComponent("failure")
        let saved = root.appendingPathComponent("failure-saved")
        let retryEmbedder = HostedRefreshEmbedder(true)
        let failingIndex = HistoryIndex(directory: folder, embedder: HostedRefreshEmbedder(false))
        try await failingIndex.sync([row])
        let failing = HistorySearchModel(index: failingIndex, syncDelay: .zero, searchDelay: .zero,
                                        makeFreshEmbedder: { retryEmbedder })
        failing.records = { [row] }
        let failureRendered = HistoryRefreshRenderState()
        var failureReloads = 0
        let failureHost = NSHostingView(rootView: HistoryRefreshRenderHost(search: failing, reload: { failureReloads += 1 },
            observed: failureRendered, size: CGSize(width: 420, height: 180)).environment(\.accessibilityEnabled, true))
        let failureWindow = hostedWindow(failureHost)
        defer { failureWindow.orderOut(nil); failureWindow.close() }
        try await waitForRender(failureHost, observed: failureRendered, size: CGSize(width: 420, height: 180))
        try FileManager.default.moveItem(at: folder, to: saved)
        try Data("owned storage obstruction".utf8).write(to: folder)
        try await clickRefresh(failureHost, window: failureWindow, observed: failureRendered)
        try await waitForAction { failureReloads == 1 }
        await failing.waitForMaintenance()
        XCTAssertNotNil(failing.refreshIssue); XCTAssertFalse(failing.isRefreshing)
        for _ in 0..<150 {
            failureHost.layoutSubtreeIfNeeded()
            if let content = failureRendered.contentFrame, let button = failureRendered.buttonFrame,
               content.height > button.height { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let content = try XCTUnwrap(failureRendered.contentFrame)
        let button = try XCTUnwrap(failureRendered.buttonFrame)
        XCTAssertGreaterThan(content.height, button.height,
                             "Actual production failure guidance must occupy rendered space below the control")
        let failureImage = try capture(failureHost, name: "Actual History refresh failure guidance and usable retry")
        let caption = CGRect(x: content.minX, y: button.maxY, width: content.width,
                             height: content.maxY - button.maxY)
        let contrast = try HistoryRecoveryContrast.measure(failureImage, caption: caption, host: failureHost.bounds.size)
        let measurement = XCTAttachment(string: contrast.description)
        measurement.name = "Actual History recovery caption contrast"; measurement.lifetime = .keepAlways; add(measurement)
        XCTAssertGreaterThanOrEqual(contrast.ratio, 4.5, "Actual essential recovery caption must remain readable")
        try FileManager.default.removeItem(at: folder); try FileManager.default.moveItem(at: saved, to: folder)
        try await clickRefresh(failureHost, window: failureWindow, observed: failureRendered)
        try await waitForAction { failureReloads == 2 }
        await failing.waitForMaintenance()
        XCTAssertNil(failing.refreshIssue); XCTAssertFalse(failing.isRefreshing)
        let retries = await retryEmbedder.calls; XCTAssertEqual(retries, 1)
        failing.search("meaning"); await failing.waitForSearch()
        XCTAssertEqual(failing.results(for: "meaning")?.map(\.id), [row.id])
        try capture(failureHost, name: "Actual History refresh retry returns to idle")
    }

    private func waitForAction(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition(), clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        _ = try XCTUnwrap(condition() ? true : nil, "Actual native pointer action must reach its production reload")
    }

    private func waitForRender(_ host: NSView, observed: HistoryRefreshRenderState, size: CGSize) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if observed.appeared && observed.accessibilityEnabled && observed.size == size,
               host.window != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        print("HISTORY_REFRESH_NATIVE_WINDOW active=\(NSApp.isActive) key=\(host.window?.isKeyWindow == true)")
        XCTAssertTrue(observed.appeared, "The actual shared control must appear in its native host")
        XCTAssertTrue(observed.accessibilityEnabled, "The controlled native host must observe accessibility enabled")
        XCTAssertEqual(observed.size, size, "The native wrapper must preserve the intended viewport")
        XCTAssertEqual(host.bounds.size, size)
    }

    private func hostedWindow<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.title = "ListenToMe History Refresh — synthetic native contract"
        NSApp.activate(); window.makeKeyAndOrderFront(nil)
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        return window
    }
    private func clickRefresh(_ host: NSView, window: NSWindow, observed: HistoryRefreshRenderState) async throws {
        let frame = try XCTUnwrap(observed.buttonFrame, "Actual production control geometry must be observed")
        XCTAssertGreaterThan(frame.width, 0); XCTAssertGreaterThan(frame.height, 0)
        let local = NSPoint(x: frame.midX, y: host.isFlipped ? frame.midY : host.bounds.height - frame.midY)
        XCTAssertTrue(host.bounds.contains(local))
        let target = try XCTUnwrap(host.hitTest(local), "Observed production control must receive native pointer events")
        let point = host.convert(local, to: nil)
        let time = ProcessInfo.processInfo.systemUptime
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: time + 0.01, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0))
        // Reuse the established native transcript harness's owned-window event path.
        // Never call the model or production Button callback directly.
        NSApp.postEvent(up, atStart: true)
        print("HISTORY_REFRESH_NATIVE_HIT=\(type(of: target))")
        window.sendEvent(down)
        // A Button may return from mouseDown before consuming the posted release. Deliver
        // that exact owned release now if tracking did not already consume it.
        if let release = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) {
            if release.windowNumber == window.windowNumber { window.sendEvent(release) }
            else { NSApp.postEvent(release, atStart: true); XCTFail("Unexpected foreign window event in owned host") }
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    @discardableResult private func capture(_ host: NSView, name: String) throws -> CGImage {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        image.name = name; image.lifetime = .keepAlways; add(image)
        return try XCTUnwrap(bitmap.cgImage)
    }
}

/// Measures only the actual production caption below the observed Button rectangle.
/// No fake Text, token-color resolution or synthetic palette can satisfy this check.
private enum HistoryRecoveryContrast {
    enum Invalid: Error { case bounds, bitmap, transparent, flat }
    struct Measurement {
        let ratio: Double
        let foreground: Int
        let background: Int
        let inkPixels: Int
        var description: String {
            "actual caption foregroundRGB=\(foreground), backgroundRGB=\(background), "
                + "contrast=\(ratio), solidInkPixels=\(inkPixels)"
        }
    }
    static func measure(_ image: CGImage, caption: CGRect, host: CGSize) throws -> Measurement {
        guard host.width > 0, host.height > 0 else { throw Invalid.bounds }
        let rect = CGRect(x: caption.minX * CGFloat(image.width) / host.width,
                          y: caption.minY * CGFloat(image.height) / host.height,
                          width: caption.width * CGFloat(image.width) / host.width,
                          height: caption.height * CGFloat(image.height) / host.height).integral
        guard rect.width > 0, rect.height > 0,
              CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(rect),
              let crop = image.cropping(to: rect), let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw Invalid.bounds
        }
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height)); return true
        }
        guard rendered else { throw Invalid.bitmap }
        var histogram: [Int: Int] = [:]
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            guard bytes[offset + 3] == 255 else { throw Invalid.transparent }
            let key = Int(bytes[offset]) << 16 | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2])
            histogram[key, default: 0] += 1
        }
        let colors = histogram.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard colors.count >= 2, colors[1].value >= 20 else { throw Invalid.flat }
        func luminance(_ value: Int) -> Double {
            let channels = [(value >> 16) & 255, (value >> 8) & 255, value & 255].map { Double($0) / 255 }
            let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let a = luminance(colors[0].key), b = luminance(colors[1].key)
        return Measurement(ratio: (max(a, b) + 0.05) / (min(a, b) + 0.05), foreground: colors[1].key,
                           background: colors[0].key, inkPixels: colors[1].value)
    }
}
