import Foundation

public struct ClientDirectory {
    public let fileURL: URL
    public let credentialsURL: URL
    public let defaults: UserDefaults

    public static let selectedServerKey = "DelugeRemote.selectedServerID"
    public static let refreshIntervalKey = "DelugeRemote.refreshInterval"

    public init(directory: URL, defaults: UserDefaults = .standard) {
        self.fileURL = directory.appendingPathComponent("servers.json")
        self.credentialsURL = directory.appendingPathComponent("credentials.json")
        self.defaults = defaults
    }

    public static func live() -> ClientDirectory {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("Deluge Remote", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ClientDirectory(directory: directory)
    }

    public func loadServers() -> [ServerConfig] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ServerConfig].self, from: data)) ?? []
    }

    public func saveServers(_ servers: [ServerConfig]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(servers) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func password(for id: UUID) -> String {
        passwords()[id.uuidString] ?? ""
    }

    public func setPassword(_ password: String, for id: UUID) {
        var stored = passwords()
        stored[id.uuidString] = password
        writePasswords(stored)
    }

    public func deletePassword(for id: UUID) {
        var stored = passwords()
        stored.removeValue(forKey: id.uuidString)
        writePasswords(stored)
    }

    public var selectedServerID: UUID? {
        get {
            guard let raw = defaults.string(forKey: Self.selectedServerKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Self.selectedServerKey)
            } else {
                defaults.removeObject(forKey: Self.selectedServerKey)
            }
        }
    }

    public var refreshInterval: Int {
        get {
            let stored = defaults.integer(forKey: Self.refreshIntervalKey)
            return stored == 0 ? 2 : min(60, max(1, stored))
        }
        set {
            defaults.set(min(60, max(1, newValue)), forKey: Self.refreshIntervalKey)
        }
    }

    private func passwords() -> [String: String] {
        guard let data = try? Data(contentsOf: credentialsURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func writePasswords(_ passwords: [String: String]) {
        guard let data = try? JSONEncoder().encode(passwords) else { return }
        try? data.write(to: credentialsURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsURL.path)
    }
}
