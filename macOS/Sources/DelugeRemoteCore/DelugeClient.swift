import Foundation

public enum DelugeClientError: LocalizedError, Equatable {
    case invalidURL
    case incorrectPassword
    case hostOffline
    case noHosts
    case api(String)
    case http(Int)
    case unreadableResponse
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server address is not a valid URL."
        case .incorrectPassword:
            return "Incorrect password."
        case .hostOffline:
            return "The Deluge daemon is offline. Start it from the WebUI, then try again."
        case .noHosts:
            return "No Deluge daemons are configured in the WebUI."
        case .api(let message):
            return message
        case .http(let code):
            return "The server returned HTTP \(code). Check the host, port, and web path."
        case .unreadableResponse:
            return "Deluge returned a response this app could not read. Check that the web path points at Deluge WebUI."
        case .transport(let message):
            return message
        }
    }
}

public final class DelugeClient: @unchecked Sendable {
    public let server: ServerConfig
    private let password: String
    private let session: URLSession
    private let trustDelegate: InsecureTrustDelegate
    private let mutex = AsyncMutex()
    private var nextID = 0
    private var includeLabel = true

    public init(server: ServerConfig, password: String) {
        self.server = server
        self.password = password
        let delegate = InsecureTrustDelegate(allowInvalidCertificate: server.allowInvalidCertificate)
        self.trustDelegate = delegate
        self.session = URLSession(configuration: DelugeHTTP.configuration(), delegate: delegate, delegateQueue: nil)
    }

    public func shutdown() {
        session.invalidateAndCancel()
    }

    public func ensureConnected() async throws {
        let loggedIn = try await rpc("auth.login", [.string(password)])
        guard loggedIn.bool == true else { throw DelugeClientError.incorrectPassword }
        if try await rpc("web.connected").bool == true { return }

        let hosts = Host.list(from: try await rpc("web.get_hosts"))
        guard let host = hosts.first else { throw DelugeClientError.noHosts }
        let status = Host.status(from: try await rpc("web.get_host_status", [.string(host.id)])) ?? ""
        if status == "Connected" { return }
        guard status == "Online" else { throw DelugeClientError.hostOffline }

        _ = try await rpc("web.connect", [.string(host.id)])
        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 250_000_000)
            if try await rpc("web.connected").bool == true { return }
        }
        throw DelugeClientError.hostOffline
    }

    public func torrents() async throws -> [Torrent] {
        do {
            return try await fetchTorrents(includeLabel: includeLabel)
        } catch DelugeClientError.api(let message) where message.localizedCaseInsensitiveContains("label") {
            includeLabel = false
            return try await fetchTorrents(includeLabel: false)
        }
    }

    public func sessionSnapshot() async throws -> SessionSnapshot {
        let result = try await rpc("core.get_session_status", [
            .array(["payload_download_rate", "payload_upload_rate", "num_peers"].map(JSONValue.string))
        ])
        return SessionSnapshot.parse(result)
    }

    public func detail(hash: String) async throws -> TorrentDetail {
        let result = try await rpc("core.get_torrent_status", [
            .string(hash),
            .array(Self.detailKeys(includeLabel: includeLabel).map(JSONValue.string))
        ])
        guard let detail = TorrentDetail.parse(hash: hash, json: result) else {
            throw DelugeClientError.unreadableResponse
        }
        return detail
    }

    public func defaultOptions() async throws -> AddTorrentOptions {
        let keys = [
            "add_paused",
            "download_location",
            "move_completed",
            "move_completed_path",
            "max_connections_per_torrent",
            "max_download_speed_per_torrent",
            "max_upload_slots_per_torrent",
            "max_upload_speed_per_torrent",
            "prioritize_first_last_pieces"
        ]
        let result = try await rpc("core.get_config_values", [.array(keys.map(JSONValue.string))])
        return AddTorrentOptions.parse(result)
    }

    public func pause(hashes: [String]) async throws {
        guard !hashes.isEmpty else { return }
        _ = try await rpc("core.pause_torrent", [.array(hashes.map(JSONValue.string))])
    }

    public func resume(hashes: [String]) async throws {
        guard !hashes.isEmpty else { return }
        _ = try await rpc("core.resume_torrent", [.array(hashes.map(JSONValue.string))])
    }

    public func pauseAll() async throws {
        _ = try await rpc("core.pause_all_torrents")
    }

    public func resumeAll() async throws {
        _ = try await rpc("core.resume_all_torrents")
    }

    public func remove(hash: String, deleteData: Bool) async throws {
        _ = try await rpc("core.remove_torrent", [.string(hash), .bool(deleteData)])
    }

    public func recheck(hash: String) async throws {
        _ = try await rpc("core.force_recheck", [.array([.string(hash)])])
    }

    public func moveStorage(hash: String, path: String) async throws {
        _ = try await rpc("core.move_storage", [.array([.string(hash)]), .string(path)])
    }

    public func setLimits(hash: String, downloadKiB: Int, uploadKiB: Int, connections: Int) async throws {
        _ = try await rpc("core.set_torrent_options", [
            .array([.string(hash)]),
            .object([
                "max_download_speed": .int(downloadKiB),
                "max_upload_speed": .int(uploadKiB),
                "max_connections": .int(connections)
            ])
        ])
    }

    public func setFilePriorities(hash: String, priorities: [Int]) async throws {
        _ = try await rpc("core.set_torrent_options", [
            .array([.string(hash)]),
            .object(["file_priorities": .array(priorities.map { .int($0) })])
        ])
    }

    public func addMagnet(_ magnet: String, options: AddTorrentOptions) async throws {
        _ = try await rpc("core.add_torrent_magnet", [.string(magnet), options.parameters()])
    }

    public func addURL(_ url: String, options: AddTorrentOptions) async throws {
        _ = try await rpc("core.add_torrent_url", [.string(url), options.parameters()])
    }

    public func addFile(name: String, data: Data, options: AddTorrentOptions) async throws {
        _ = try await rpc("core.add_torrent_file", [
            .string(name),
            .string(data.base64EncodedString()),
            options.parameters()
        ])
    }

    private func fetchTorrents(includeLabel: Bool) async throws -> [Torrent] {
        let result = try await rpc("core.get_torrents_status", [
            .object([:]),
            .array(Self.overviewKeys(includeLabel: includeLabel).map(JSONValue.string))
        ])
        return Torrent.list(from: result)
    }

    private static func overviewKeys(includeLabel: Bool) -> [String] {
        var keys = [
            "name", "hash", "upload_payload_rate", "download_payload_rate", "ratio",
            "progress", "total_wanted", "state", "tracker_host", "eta", "total_size",
            "all_time_download", "total_uploaded", "time_added", "paused"
        ]
        if includeLabel { keys.append("label") }
        return keys
    }

    private static func detailKeys(includeLabel: Bool) -> [String] {
        overviewKeys(includeLabel: includeLabel) + [
            "save_path", "comment", "tracker_status", "message", "tracker",
            "num_seeds", "num_peers", "total_done", "files", "file_progress",
            "file_priorities", "max_download_speed", "max_upload_speed", "max_connections"
        ]
    }

    private func rpc(_ method: String, _ params: [JSONValue] = []) async throws -> JSONValue {
        await mutex.acquire()
        do {
            let value = try await send(method, params)
            await mutex.release()
            return value
        } catch {
            await mutex.release()
            throw error
        }
    }

    private func send(_ method: String, _ params: [JSONValue]) async throws -> JSONValue {
        guard let url = server.jsonURL else { throw DelugeClientError.invalidURL }
        nextID += 1
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RPCRequest(id: nextID, method: method, params: params))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw DelugeClientError.transport(error.localizedDescription)
        } catch let error as DelugeClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DelugeClientError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DelugeClientError.http(http.statusCode)
        }
        if data.first == UInt8(ascii: "<") {
            throw DelugeClientError.unreadableResponse
        }

        let envelope: RPCResponse
        do {
            envelope = try JSONDecoder().decode(RPCResponse.self, from: data)
        } catch {
            throw DelugeClientError.unreadableResponse
        }
        if let error = envelope.error {
            throw DelugeClientError.api(error.message)
        }
        return envelope.result ?? .null
    }
}

private struct RPCRequest: Encodable {
    let id: Int
    let method: String
    let params: [JSONValue]
}

private struct RPCResponse: Decodable {
    let result: JSONValue?
    let error: RPCFailure?
}

private struct RPCFailure: Decodable {
    let message: String
    let code: Int
}

enum DelugeHTTP {
    /// Ephemeral sessions already have a private cookie store. Replacing it stops
    /// URLSession from keeping Deluge's `_session_id`, so the login succeeds and
    /// every later call is rejected as not authenticated.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        return configuration
    }
}

private final class InsecureTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let allowInvalidCertificate: Bool

    init(allowInvalidCertificate: Bool) {
        self.allowInvalidCertificate = allowInvalidCertificate
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler)
    }

    private func handle(
        _ challenge: URLAuthenticationChallenge,
        _ completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowInvalidCertificate,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

/// Serializes Deluge requests. Swift actors are reentrant, so this waits explicitly.
private actor AsyncMutex {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
