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

    func testBinaryFileRenamedAsTextIsRejectedRatherThanIncludedAsMojibake() throws {
        // PNG header: NUL bytes and control characters, decodable by ISO Latin-1 into nonsense.
        let binary = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
                           0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x01, 0x00])
        XCTAssertNil(TextFileReader.decode(binary))
        XCTAssertThrowsError(try TextFileReader.text(at: try write(binary, "screenshot.txt")))
    }

    func testControlCharacterHeavyBytesAreRejectedButAccentedLatin1IsNot() throws {
        var controlHeavy = Data()
        for _ in 0..<100 { controlHeavy.append(contentsOf: [0x41, 0x01, 0x02, 0x03]) }
        XCTAssertNil(TextFileReader.decode(controlHeavy))
        // Tabs, newlines and returns are text, and so is a Latin-1 accented line.
        let mixed = TextFileReader.decode(Data([0x61, 0x09, 0x62, 0x0D, 0x0A, 0xE9]))
        XCTAssertNotNil(mixed)
        XCTAssertTrue(mixed?.hasPrefix("a\tb\r\n") == true, mixed ?? "nil")
    }

    func testMalformedRTFThrowsInsteadOfHandingOnControlWords() throws {
        let url = try write(Data("{\\rtf1\\ansi this is not".utf8), "broken.rtf")
        XCTAssertThrowsError(try TextFileReader.text(at: url))
    }

    func testUnreadableFileThrowsInsteadOfReturningEmpty() {
        XCTAssertThrowsError(try TextFileReader.text(at: root.appendingPathComponent("missing.txt")))
    }
}
