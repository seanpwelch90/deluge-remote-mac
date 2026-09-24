import Foundation

public struct ServerConfig: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var nickname: String
    public var hostname: String
    public var port: Int
    public var path: String
    public var useTLS: Bool
    public var allowInvalidCertificate: Bool

    public init(
        id: UUID = UUID(),
        nickname: String,
        hostname: String,
        port: Int,
        path: String,
        useTLS: Bool,
        allowInvalidCertificate: Bool
    ) {
        self.id = id
        self.nickname = nickname
        self.hostname = hostname
        self.port = port
        self.path = path
        self.useTLS = useTLS
        self.allowInvalidCertificate = allowInvalidCertificate
    }

    public var jsonURL: URL? { endpoint("json") }

    public func endpoint(_ leaf: String) -> URL? {
        var components = URLComponents()
        components.scheme = useTLS ? "https" : "http"
        components.host = hostname
        components.port = port
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmed.isEmpty ? "/\(leaf)" : "/\(trimmed)/\(leaf)"
        return components.url
    }

    public static func make(
        id: UUID = UUID(),
        nickname: String,
        host: String,
        port: Int,
        path: String,
        useTLS: Bool,
        allowInvalidCertificate: Bool
    ) -> ServerConfig? {
        let nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var port = port
        var path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        var useTLS = useTLS

        guard !nickname.isEmpty, !host.isEmpty, (1...65535).contains(port) else { return nil }

        if host.contains("://") {
            guard let url = URL(string: host), let parsedHost = url.host, !parsedHost.isEmpty else { return nil }
            host = parsedHost
            if let parsedPort = url.port { port = parsedPort }
            if url.scheme?.lowercased() == "https" { useTLS = true }
            if url.scheme?.lowercased() == "http" { useTLS = false }
            if url.path != "/" && !url.path.isEmpty { path = url.path }
        }

        guard !host.contains("/"), !host.contains(" ") else { return nil }

        return ServerConfig(
            id: id,
            nickname: nickname,
            hostname: host,
            port: port,
            path: path,
            useTLS: useTLS,
            allowInvalidCertificate: allowInvalidCertificate
        )
    }
}

public struct Host: Equatable, Sendable {
    public let id: String
    public let address: String?
    public let port: Int?

    public init(id: String, address: String?, port: Int?) {
        self.id = id
        self.address = address
        self.port = port
    }

    public static func list(from value: JSONValue) -> [Host] {
        guard case .array(let rows) = value else { return [] }
        return rows.compactMap { row in
            guard case .array(let columns) = row, let id = columns.first?.string, !id.isEmpty else { return nil }
            let address = columns.count > 1 ? columns[1].string : nil
            let port = columns.count > 2 ? columns[2].int : nil
            return Host(id: id, address: address, port: port)
        }
    }

    /// Deluge 1 returns `[id, ip, port, status, version]`. Deluge 2 returns `[id, status, version]`.
    public static func status(from value: JSONValue) -> String? {
        guard case .array(let columns) = value else { return nil }
        if columns.count >= 5, let status = columns[3].string { return status }
        if columns.count >= 2, let status = columns[1].string { return status }
        return nil
    }
}
