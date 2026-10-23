import Foundation

/// One open-source package's notice from `App/ThirdPartyNotices.txt`: its pinned version and full
/// license text. Both apps bundle that file; the iOS Acknowledgements screen lists these (issue #202).
public struct ThirdPartyNotice: Equatable, Sendable, Identifiable {
    /// The SwiftPM identity, as `Config/Package.resolved` spells it (lowercase).
    public let identity: String
    public let version: String
    public let url: String
    public let revision: String
    /// Every license, NOTICE and bundled third-party license file the package ships, verbatim.
    public let text: String

    public var id: String { identity }

    /// The repository name as its authors spell it ("WhisperKit", "swift-collections"), falling back
    /// to the identity when the URL has no usable last component.
    public var displayName: String {
        var name = url.split(separator: "/").last.map(String.init) ?? ""
        if name.hasSuffix(".git") { name.removeLast(4) }
        return name.isEmpty ? identity : name
    }

    public init(identity: String, version: String, url: String, revision: String, text: String) {
        self.identity = identity
        self.version = version
        self.url = url
        self.revision = revision
        self.text = text
    }
}

/// A package pinned in `Package.resolved`.
public struct ResolvedPackagePin: Equatable, Sendable, Decodable {
    public let identity: String
    public let location: String
    public let version: String?
    public let revision: String

    public init(identity: String, location: String, version: String?, revision: String) {
        self.identity = identity
        self.location = location
        self.version = version
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey { case identity, location, state }
    private enum StateKeys: String, CodingKey { case version, revision }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identity = try container.decode(String.self, forKey: .identity)
        location = try container.decode(String.self, forKey: .location)
        let state = try container.nestedContainer(keyedBy: StateKeys.self, forKey: .state)
        version = try state.decodeIfPresent(String.self, forKey: .version)
        revision = try state.decode(String.self, forKey: .revision)
    }
}

public enum ThirdPartyNotices {
    /// The rule that separates packages in the notices file.
    static let separator = String(repeating: "=", count: 72)

    public typealias Pin = ResolvedPackagePin

    /// Splits the notices file into one entry per package. Each section is the separator, then
    /// `identity version`, the repository URL, `Revision: <sha>` and the license text. The preamble
    /// before the first separator and any malformed section are skipped.
    public static func parse(_ text: String) -> [ThirdPartyNotice] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var sections: [[String]] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == separator {
                sections.append([])
            } else if !sections.isEmpty {
                sections[sections.count - 1].append(line)
            }
        }
        return sections.compactMap(notice(from:))
    }

    private static func notice(from section: [String]) -> ThirdPartyNotice? {
        var lines = section[...].drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 3 else { return nil }
        let heading = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        let url = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        let revisionLine = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        guard heading.count == 2, revisionLine.hasPrefix("Revision: ") else { return nil }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return ThirdPartyNotice(identity: String(heading[0]), version: String(heading[1]), url: url,
                                revision: String(revisionLine.dropFirst("Revision: ".count)), text: body)
    }

    /// The pins in a `Package.resolved` file (format version 2 or 3).
    public static func pins(fromResolved data: Data) throws -> [Pin] {
        struct Resolved: Decodable { let pins: [Pin] }
        return try JSONDecoder().decode(Resolved.self, from: data).pins
    }

    /// Pins without a notice for the same package at the same revision, so a dependency added or
    /// bumped without regenerating the notices fails the check in `ThirdPartyNoticesTests`.
    public static func missing(_ pins: [Pin], in notices: [ThirdPartyNotice]) -> [Pin] {
        let covered = Set(notices.map { "\($0.identity)@\($0.revision)" })
        return pins.filter { !covered.contains("\($0.identity)@\($0.revision)") }
    }
}
