import XCTest
@testable import ListenToMeCore

final class SessionAttachmentTests: XCTestCase {
    func testStorePreservesBytesAndSanitizesImportedName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionAttachmentStore(directory: root)
        let data = Data("Meeting notes".utf8)
        let item = try store.add(data: data, name: "../meeting.txt")
        XCTAssertEqual(item.name, "meeting.txt")
        XCTAssertEqual(item.byteCount, data.count)
        XCTAssertTrue(item.storedName.hasSuffix(".txt"))
        XCTAssertEqual(try Data(contentsOf: store.url(for: item)), data)
        XCTAssertEqual(try JSONDecoder().decode(SessionAttachment.self, from: JSONEncoder().encode(item)), item)
        try store.remove(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try store.url(for: item).path))
        try store.remove(item)
        let untyped = try store.add(data: data, name: "README")
        XCTAssertEqual(untyped.storedName, untyped.id)
    }

    func testRejectsOversizeEmptyAndEscapingPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionAttachmentStore(directory: root)
        XCTAssertThrowsError(try store.add(data: Data(), name: "empty.txt"))
        XCTAssertThrowsError(try store.add(data: Data(count: SessionAttachmentStore.maximumBytes + 1), name: "large"))
        for path in ["", ".", "..", "../escape", "a/b", "a\\b"] {
            let item = SessionAttachment(id: "bad", name: "bad", storedName: path, byteCount: 1)
            XCTAssertThrowsError(try store.url(for: item))
        }
        try Data().write(to: root)
        XCTAssertThrowsError(try store.add(data: Data([1]), name: "blocked"))
    }
}
