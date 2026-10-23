import Foundation

/// The address of an OpenAI-compatible server (LM Studio, vLLM, llama.cpp, OpenRouter, Ollama's
/// `/v1` API…) as the user typed it, validated and classified (issue #52).
///
/// Classification is about the *address*, never a claim about where inference happens: a server on
/// `localhost` can relay every request to a hosted API, and a name can be re-pointed. So the most
/// a loopback or LAN address earns is the label "your server"; anything else "may leave this
/// device". Nothing here ever calls a custom endpoint "local" or "on-device".
public enum OpenAICompatibleEndpoint {
    /// Where the typed address points.
    public enum Reach: Sendable, Equatable {
        /// `localhost`, `127.0.0.0/8` or `::1`: a server on this machine (which may still relay).
        case loopback
        /// A `.local` name, an RFC 1918, link-local or IPv6 unique-local address.
        case privateNetwork
        /// Anything else, including CGNAT/VPN ranges and ordinary host names.
        case internet

        /// True when the address is one the user plausibly runs: loopback or their own network.
        public var isUsersOwnServer: Bool { self != .internet }
    }

    public enum ValidationError: LocalizedError, Equatable {
        case empty
        case invalid
        case credentialsInURL
        case queryInURL
        case plainHTTP(host: String)

        public var errorDescription: String? {
            switch self {
            case .empty: return "Enter the server's base URL, for example http://your-mac.local:1234/v1."
            case .invalid:
                return "That is not a valid http:// or https:// server URL, for example https://openrouter.ai/api/v1."
            case .credentialsInURL:
                return "Remove the user name or password from the URL. Enter an API key in the key field instead."
            case .queryInURL:
                return "Remove the ?query or #fragment from the URL. Enter an API key in the key field instead."
            case .plainHTTP(let host):
                return "Plain http:// is only allowed for this device or a .local name on your network, not \(host). "
                    + "Use https://, or your computer's name, for example http://your-mac.local:1234/v1."
            }
        }
    }

    /// Parses user text into the API base URL that `chat/completions` and `models` hang off.
    ///
    /// A bare origin gets `/v1` (LM Studio, vLLM, llama.cpp, Ollama); an explicit path is kept
    /// (`https://openrouter.ai/api/v1`); a pasted `…/chat/completions` or `…/models` is trimmed back
    /// to its base. User info, queries and fragments are rejected rather than silently dropped, so a
    /// credential typed into the URL is never stored, shown or sent. Plain `http` is accepted only
    /// where App Transport Security's local-networking exemption applies (see `allowsPlainHTTP`).
    public static func normalize(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.empty }
        guard let parsed = URLComponents(string: trimmed),
              let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = parsed.host, !rawHost.isEmpty else { throw ValidationError.invalid }
        guard parsed.user == nil, parsed.password == nil else { throw ValidationError.credentialsInURL }
        guard parsed.query == nil, parsed.fragment == nil else { throw ValidationError.queryInURL }
        let host = rawHost.lowercased()
        if scheme == "http", !allowsPlainHTTP(host: host) { throw ValidationError.plainHTTP(host: host) }
        var path = parsed.path
        while path.hasSuffix("/") { path.removeLast() }
        for suffix in ["/chat/completions", "/models"] where path.lowercased().hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        if path.isEmpty { path = "/v1" }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = parsed.port
        components.path = path
        guard let url = components.url else { throw ValidationError.invalid }
        return url
    }

    /// `base/chat/completions`.
    public static func chatURL(_ base: URL) -> URL { base.appendingPathComponent("chat/completions") }
    /// `base/models`.
    public static func modelsURL(_ base: URL) -> URL { base.appendingPathComponent("models") }

    /// `scheme://host:port`. A saved API key is bound to this, so changing the server never sends
    /// the old key to a new host.
    public static func origin(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = bareHost(url)
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    /// `host` or `host:port`, for prose.
    public static func hostLabel(_ url: URL) -> String {
        let host = bareHost(url)
        let shown = host.contains(":") ? "[\(host)]" : host
        return url.port.map { "\(shown):\($0)" } ?? shown
    }

    /// Plain `http` that iOS App Transport Security (`NSAllowsLocalNetworking`) lets through and that
    /// stays on this device or the local link: `localhost`, loopback and link-local literals, and
    /// `.local` (Bonjour) names. Any other IP literal or host name needs `https`, so a typo can never
    /// send a transcript unencrypted across the internet (see issue #149 for the Ollama equivalent).
    public static func allowsPlainHTTP(host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if let octets = ipv4(host) { return octets[0] == 127 || (octets[0] == 169 && octets[1] == 254) }
        if host.contains(":") { return host == "::1" || host.hasPrefix("fe80:") }
        return false
    }

    public static func reach(of url: URL) -> Reach {
        let host = bareHost(url)
        if host == "localhost" || host == "::1" { return .loopback }
        if let octets = ipv4(host) {
            switch (octets[0], octets[1]) {
            case (127, _): return .loopback
            case (10, _), (192, 168), (169, 254): return .privateNetwork
            case (172, 16...31): return .privateNetwork
            default: return .internet
            }
        }
        if host.contains(":") {
            let lower = host.lowercased()
            if lower.hasPrefix("fe80:") || lower.hasPrefix("fc") || lower.hasPrefix("fd") { return .privateNetwork }
            return .internet
        }
        return host.hasSuffix(".local") ? .privateNetwork : .internet
    }

    /// One-line, prose-safe description of where requests go, shared by both apps.
    public static func destinationLabel(_ url: URL) -> String {
        reach(of: url).isUsersOwnServer
            ? "your server at \(hostLabel(url))"
            : "\(hostLabel(url)) (may leave this device)"
    }

    /// Why the label is honest about a custom server, shared by both apps' settings.
    public static func privacyNote(_ url: URL) -> String {
        reach(of: url).isUsersOwnServer
            ? "This address is on this device or your network, so it is shown as your server. ListenToMe "
                + "cannot verify where that server runs the model; a local server can relay requests "
                + "to a cloud service."
            : "This address is outside your network, so your transcript and notes may leave this device. "
                + "That service's own privacy terms apply."
    }

    private static func bareHost(_ url: URL) -> String {
        (url.host(percentEncoded: false) ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private static func ipv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { UInt8($0) }
        return octets.count == 4 ? octets : nil
    }
}
