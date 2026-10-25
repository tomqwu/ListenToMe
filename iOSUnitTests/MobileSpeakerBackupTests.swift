import FluidAudio
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

final class MobileSpeakerBackupTests: XCTestCase {
    func testDiarizerFactoryExcludesTheActualDefaultModelDirectoryWithoutDownloading() throws {
        let directory = OfflineDiarizerModels.defaultModelsDirectory()
        let manager = FileManager.default
        let before = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        _ = SpeakerDiarizer.excludingModelsFromBackup()
        XCTAssertTrue(manager.fileExists(atPath: directory.path))
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(directory))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: directory.path).sorted(), before.sorted(),
                       "Constructing the diarizer must not start a model download")
    }
}
