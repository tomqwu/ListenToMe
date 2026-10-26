import XCTest
import CoreML

final class TranscriptionComputeTests: XCTestCase {
    func testConfiguredUnitsAndRuntimeLabelsNeverClaimObservedHardware() {
        XCTAssertEqual(WhisperComputePolicy.label(.cpuOnly), "CPU")
        XCTAssertEqual(WhisperComputePolicy.label(.cpuAndGPU), "CPU + GPU")
        XCTAssertEqual(WhisperComputePolicy.label(.cpuAndNeuralEngine), "CPU + Neural Engine")
        XCTAssertEqual(WhisperComputePolicy.label(.all), "CPU + GPU + Neural Engine")
        for engine in ["whisperKit", "speechAnalyzer"] {
            XCTAssertEqual(TranscriptionComputeInfo(engine: engine, isRunning: false, isPreparing: false).runtime,
                           "Not running")
            XCTAssertEqual(TranscriptionComputeInfo(engine: engine, isRunning: true, isPreparing: true).runtime,
                           "Preparing · Not exposed")
            XCTAssertEqual(TranscriptionComputeInfo(engine: engine, isRunning: true, isPreparing: false).runtime,
                           "Not exposed")
        }
    }
}
