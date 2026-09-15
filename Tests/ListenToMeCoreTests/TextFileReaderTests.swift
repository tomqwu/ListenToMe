import XCTest
@testable import ListenToMeCore

final class TextFileReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func write(_ data: Data, _ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testUTF8IsReadVerbatim() throws {
        let url = try write(Data("agenda: ship the café release\n".utf8), "a.txt")
        XCTAssertEqual(try TextFileReader.text(at: url), "agenda: ship the café release\n")
    }

    func testWindowsLatin1FallbackInsteadOfSilentSkip() throws {
        // "café" in Windows-1252 / ISO Latin-1 is not valid UTF-8.
        let data = Data([0x63, 0x61, 0x66, 0xE9])
        let url = try write(data, "minutes.txt")
        XCTAssertEqual(try TextFileReader.text(at: url), "café")
    }

    func testUTF16FileWithBOMIsRead() throws {
        let url = try write("Q3 budget".data(using: .utf16)!, "export.csv")
        XCTAssertEqual(try TextFileReader.text(at: url), "Q3 budget")
    }

    func testRTFYieldsPlainTextNotControlWords() throws {
        let attributed = NSAttributedString(string: "Agenda\nBudget review")
        let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                       documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let url = try write(data, "agenda.rtf")
        let text = try TextFileReader.text(at: url)
        XCTAssertFalse(text.contains("\\rtf1"), text)
        XCTAssertTrue(text.contains("Agenda"), text)
        XCTAssertTrue(text.contains("Budget review"), text)
    }

    func testUnreadableFileThrowsInsteadOfReturningEmpty() {
        XCTAssertThrowsError(try TextFileReader.text(at: root.appendingPathComponent("missing.txt")))
    }
}
