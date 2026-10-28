import AVFoundation
import CoreAudio
import ListenToMeCore
import Foundation

/// The microphone engine boundary; hardware-quality acceptance is separate from lifecycle tests.
protocol MacMicrophoneDriving: AnyObject, Sendable {
    var isRunning: Bool { get }
    var isHealthy: Bool { get }
    func enableEchoCancellation() throws
    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws
    func start() throws
    func tearDown()
}

struct MacMicrophoneRecoveryDeferred: Error {}

/// Serializes engine work, with a separate terminal cancellation flag visible during slow setup.
final class MacMicrophoneCapture: @unchecked Sendable {
    private let driver: any MacMicrophoneDriving
    private let receive: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    private let control = NSLock(), state = NSLock()
    private var stopped = false
    private let now: @Sendable () -> TimeInterval
    private var recovery = CaptureRecovery.Policy()
    var isStopped: Bool { state.withLock { stopped } }
    var needsRecovery: Bool { control.withLock { !isStopped && !driver.isHealthy } }

    init(driver: any MacMicrophoneDriving, now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
         receive: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        self.now = now
        self.driver = driver
        self.receive = receive
    }

    func start() throws { try control.withLock { try startLocked() } }

    private func startLocked() throws {
        guard !isStopped else { throw CancellationError() }
        do {
            try driver.enableEchoCancellation()
            guard !isStopped else { throw CancellationError() }
            try driver.installTap(receive)
            guard !isStopped else { throw CancellationError() }
            try driver.start()
            guard !isStopped else { throw CancellationError() }
            guard driver.isHealthy else {
                throw NSError(domain: "ListenToMe.Capture", code: 4, userInfo: [NSLocalizedDescriptionKey:
                    "The microphone route changed during setup. Select a supported input and output, then retry."])
            }
        } catch {
            driver.tearDown()
            throw error
        }
    }

    @discardableResult func recoverIfNeeded() throws -> Bool {
        try control.withLock {
            guard !isStopped, !driver.isHealthy else { return false }
            // A real unhealthy event within the cooldown must never silently keep raw input live.
            let decision = recovery.shouldAttemptRestart(for: .you, now: now())
            driver.tearDown()
            switch decision {
            case .suppressed: throw MacMicrophoneRecoveryDeferred()
            case .budgetSpent:
                throw NSError(domain: "ListenToMe.Capture", code: 5, userInfo: [NSLocalizedDescriptionKey:
                    "Microphone recovery failed. Select a supported input and output, then stop and retry."])
            case .attempt: break
            }
            try startLocked()
            recovery.restartSucceeded(for: .you, now: now())
            return true
        }
    }

    func stop() {
        state.withLock { stopped = true }
        control.withLock { driver.tearDown() }
    }
}

/// Native AVAudioEngine adapter. No microphone samples are sent back to the speakers.
final class MacMicrophoneEngine: MacMicrophoneDriving, @unchecked Sendable {
    let engine = AVAudioEngine()
    private var tapFormat: AVAudioFormat?
    private var route: [AudioDeviceID]?
    var isRunning: Bool { engine.isRunning }
    var isHealthy: Bool {
        let input = engine.inputNode
        let ducking = input.voiceProcessingOtherAudioDuckingConfiguration
        return engine.isRunning && input.isVoiceProcessingEnabled && !input.isVoiceProcessingBypassed
            && !input.isVoiceProcessingAGCEnabled && !ducking.enableAdvancedDucking.boolValue && ducking.duckingLevel == .min
            && tapFormat == input.outputFormat(forBus: 0) && route != nil && route == Self.defaultRoute()
    }

    func enableEchoCancellation() throws {
        guard !engine.isRunning else { throw unavailable("The microphone engine is already running.") }
        if case .blocked(let message, _) = CapturePreflight.decide(microphone: PermissionsModel.currentMicrophoneAuthorization()) {
            throw NSError(domain: "ListenToMe.Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let input = engine.inputNode
        do { try input.setVoiceProcessingEnabled(true) }
        catch { throw unavailable(error.localizedDescription) }
        input.isVoiceProcessingBypassed = false
        input.isVoiceProcessingAGCEnabled = false
        input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        let ducking = input.voiceProcessingOtherAudioDuckingConfiguration
        guard input.isVoiceProcessingEnabled, !input.isVoiceProcessingBypassed,
              !input.isVoiceProcessingAGCEnabled, !ducking.enableAdvancedDucking.boolValue, ducking.duckingLevel == .min else {
            throw unavailable("This audio route did not enable voice processing.")
        }
    }

    func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate.isFinite, format.sampleRate > 0 else {
            throw unavailable("No usable microphone format.")
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: receive)
        tapFormat = format
        route = Self.defaultRoute()
    }

    func start() throws { engine.prepare(); try engine.start() }

    func tearDown() {
        engine.stop()
        if tapFormat != nil { engine.inputNode.removeTap(onBus: 0) }
        tapFormat = nil; route = nil
    }

    private func unavailable(_ reason: String) -> NSError {
        NSError(domain: "ListenToMe.Capture", code: 3, userInfo: [NSLocalizedDescriptionKey:
            "Microphone echo control is unavailable. Select a supported input and output in Sound settings, then retry. " + reason])
    }

    /// AVAudioEngine's format can remain identical when the default physical device changes.
    private static func defaultRoute() -> [AudioDeviceID]? {
        var result: [AudioDeviceID] = []
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                             &size, &device) == noErr, device != 0 else { return nil }
            result.append(device)
        }
        return result
    }
}
