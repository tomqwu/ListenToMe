import XCTest
@testable import ListenToMeCore

final class PresetCatalogTests: XCTestCase {
    func testNoneIsDefaultAndEmpty() {
        XCTAssertEqual(PresetCatalog.none.id, "none")
        XCTAssertTrue(PresetCatalog.none.notesTemplate.isEmpty)
        XCTAssertTrue(PresetCatalog.none.personaGuidance.isEmpty)
    }

    func testAllStartsWithNoneAndHasUniqueIDs() {
        XCTAssertEqual(PresetCatalog.all.first, PresetCatalog.none)
        XCTAssertEqual(Set(PresetCatalog.all.map(\.id)).count, PresetCatalog.all.count)
    }

    func testLookupByIDFallsBackToNone() {
        XCTAssertEqual(PresetCatalog.preset(id: "interview-candidate").id, "interview-candidate")
        XCTAssertEqual(PresetCatalog.preset(id: "nonexistent"), PresetCatalog.none)
    }

    func testRealPresetsHaveGuidanceAndNotes() {
        for preset in PresetCatalog.all where preset.id != "none" {
            XCTAssertFalse(preset.name.isEmpty, "\(preset.id) needs a name")
            XCTAssertFalse(preset.personaGuidance.isEmpty, "\(preset.id) needs guidance")
            XCTAssertFalse(preset.notesTemplate.isEmpty, "\(preset.id) needs a notes template")
        }
    }
}
