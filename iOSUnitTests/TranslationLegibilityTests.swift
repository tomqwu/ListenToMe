import SwiftUI
import UIKit
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class TranslationLegibilityTests: XCTestCase {
    func testActualStatusRenderAndNativeEnvironmentContrastMatrix() async throws {
        for dark in [false, true] {
            for increased in [false, true] {
                for accessibility in [false, true] {
                    try await check(dark: dark, increased: increased, accessibility: accessibility)
                }
            }
        }
    }
    private func check(dark: Bool, increased: Bool, accessibility: Bool) async throws {
        let worker = LiveTranslationCoordinator()
        // Actual production initial availability reason; no fake drawn status, inference or model.
        XCTAssertEqual(worker.availability.reason, "Record speech to translate.")
        let observed = TranslationEnvironmentObservation()
        let content = OnDeviceTranslationStatus(worker: worker, target: "fr", context: "contrast-fixture")
            .fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(width: 320, alignment: .leading).background(MobileStyle.surface)
            .background(TranslationEnvironmentProbe(observation: observed))
        let host = UIHostingController(rootView: content)
        host.traitOverrides.userInterfaceStyle = dark ? .dark : .light
        host.traitOverrides.accessibilityContrast = increased ? .high : .normal
        host.traitOverrides.preferredContentSizeCategory = accessibility ? .accessibilityExtraExtraExtraLarge : .large
        let width: CGFloat = 320
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 220))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.backgroundColor = .clear
        // Readiness failures are harness diagnostics, never the expected contrast regression.
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var fitted = CGSize.zero
        var ready = false
        while ContinuousClock.now < deadline {
            fitted = host.sizeThatFits(in: CGSize(width: width, height: 2_048))
            if fitted.width.isFinite, fitted.height.isFinite, fitted.width > 0, fitted.height > 0,
               fitted.width <= width + 0.5, fitted.height < 2_048 {
                window.frame = CGRect(x: 0, y: 0, width: width, height: ceil(fitted.height))
                host.view.frame = window.bounds
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                if let env = observed.values,
                   env.colorScheme == (dark ? .dark : .light),
                   env.colorSchemeContrast == (increased ? .increased : .standard),
                   env.dynamicTypeSize == (accessibility ? .accessibility5 : .large),
                   let content = observed.contentBounds,
                   content.width > 0, content.height > 0,
                   host.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(content) {
                    ready = true; break
                }
            }
            // Yield the main actor for actual UIKit/SwiftUI run-loop layout work, with a wall limit.
            try await Task.sleep(for: .milliseconds(20))
        }
        guard ready, let env = observed.values, let content = observed.contentBounds else {
            let detail = XCTAttachment(string: "Layout/environment readiness failed; fitted=\(fitted), host=\(host.view.bounds), "
                + "content=\(String(describing: observed.contentBounds)), env=\(String(describing: observed.values))")
            detail.lifetime = .keepAlways; add(detail)
            XCTFail("Native layout/environment readiness failed before contrast measurement")
            return
        }
        XCTAssertTrue(host.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(content))
        let surface = MobileStyle.surface.resolve(in: env)
        let primary = Color.primary.resolve(in: env), secondary = Color.secondary.resolve(in: env)
        func rgba(_ c: Color.Resolved) -> String {
            "sRGB=(\(c.red),\(c.green),\(c.blue)) alpha=\(c.opacity); linear=(\(c.linearRed),\(c.linearGreen),\(c.linearBlue))"
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 3
        format.opaque = true; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            UIColor(red: CGFloat(surface.red), green: CGFloat(surface.green), blue: CGFloat(surface.blue),
                    alpha: CGFloat(surface.opacity)).setFill()
            context.fill(window.bounds)
            host.view.layer.render(in: context.cgContext)
        }
        let name = "Actual status dark=\(dark) increased=\(increased) accessibility=\(accessibility)"
        TranslationContrastPixels.keep(image, name: name, in: self)
        let measurement = try TranslationContrastPixels.measure(try XCTUnwrap(image.cgImage))
        let notes = XCTAttachment(string: "Actual environment: \(env.colorScheme), \(env.colorSchemeContrast), \(env.dynamicTypeSize)\n"
            + "Surface \(rgba(surface))\nPrimary \(rgba(primary))\nSecondary \(rgba(secondary))\n" + measurement.description
            + "\nResolved roles are supplementary; pass/fail uses actual production Text render, not expected-token equality.")
        notes.name = name + " resolved native RGBA and rendered measurement"; notes.lifetime = .keepAlways; add(notes)
        let resolvedBackground = [surface.red, surface.green, surface.blue].map { Int(($0 * 255).rounded()) }
        for index in 0..<3 { XCTAssertEqual(Double(measurement.background[index]), Double(resolvedBackground[index]), accuracy: 2) }
        XCTAssertEqual(surface.opacity, 1, "This bounded matrix uses the actual opaque card surface")
        XCTAssertGreaterThanOrEqual(measurement.ratio, 4.5, measurement.description)
    }
}

@MainActor private final class TranslationEnvironmentObservation {
    var values: EnvironmentValues?
    var contentBounds: CGRect?
}
@MainActor private struct TranslationEnvironmentProbe: View {
    @Environment(\.self) private var values
    let observation: TranslationEnvironmentObservation
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { record(geometry.size) }
                .onChange(of: geometry.size) { _, size in record(size) }
                .onChange(of: values.colorScheme) { _, _ in record(geometry.size) }
                .onChange(of: values.colorSchemeContrast) { _, _ in record(geometry.size) }
                .onChange(of: values.dynamicTypeSize) { _, _ in record(geometry.size) }
        }
    }
    private func record(_ size: CGSize) {
        observation.values = values
        observation.contentBounds = CGRect(origin: .zero, size: size)
    }
}
