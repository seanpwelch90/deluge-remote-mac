import Foundation
import DelugeRemoteCore

@MainActor
@Observable
final class AppModel {
    var servers: [ServerConfig] = []
    var selectedServerID: UUID?
    var torrents: [Torrent] = []
    var session: SessionSnapshot?
    var filter: TorrentFilter = .all
    var selectedHashes: Set<String> = [] {
        didSet {
            guard selectedHashes != oldValue else { return }
            detailTask?.cancel()
            detailTask = Task { await loadDetail() }
        }
    }
    var detail: TorrentDetail?
    var status: ConnectionStatus = .empty
    var banner: String?
    var refreshInterval: Int
    var isPresentingServerEditor = false
    var serverEditorID: UUID?
    var isPresentingAddTorrent = false
    var isPresentingRemove = false

    private var directory: ClientDirectory
    private var pendingImports: [TorrentPayload] = []
    private var api: DelugeClient?
    private var generation = 0
    private var connectTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var didStart = false
    private var authRetries = 0

    init(directory: ClientDirectory = .live()) {
        self.directory = directory
        self.servers = directory.loadServers()
        self.refreshInterval = directory.refreshInterval
        if let stored = directory.selectedServerID, servers.contains(where: { $0.id == stored }) {
            selectedServerID = stored
        } else {
            selectedServerID = servers.first?.id
        }
    }

    var selectedServer: ServerConfig? {
        servers.first { $0.id == selectedServerID }
    }

    var labels: [String] {
        Array(Set(torrents.map(\.label).filter { !$0.isEmpty })).sorted()
    }

    var selectedTorrents: [Torrent] {
        torrents.filter { selectedHashes.contains($0.id) }
    }

    func password(for id: UUID) -> String {
        directory.password(for: id)
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        await connect()
    }

    func selectServer(_ id: UUID, force: Bool = false) {
        let changed = id != selectedServerID
        selectedServerID = id
        directory.selectedServerID = id
        if force || changed || status != .connected {
            beginConnect()
        }
    }

    func retry() {
        beginConnect()
    }

    func presentAddServer() {
        serverEditorID = nil
        isPresentingServerEditor = true
    }

    func presentEditServer(_ id: UUID) {
        serverEditorID = id
        isPresentingServerEditor = true
    }

    func presentAddTorrent() {
        guard status == .connected else { return }
        isPresentingAddTorrent = true
    }

    func saveServer(_ server: ServerConfig, password: String) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        directory.saveServers(servers)
        directory.setPassword(password, for: server.id)
        selectServer(server.id, force: true)
    }

    func deleteServer(_ id: UUID) {
        servers.removeAll { $0.id == id }
        directory.saveServers(servers)
        directory.deletePassword(for: id)
        if selectedServerID == id {
            if let next = servers.first?.id {
                selectServer(next)
            } else {
                selectedServerID = nil
                directory.selectedServerID = nil
                beginConnect()
            }
        }
    }

    func updateRefreshInterval(_ seconds: Int) {
        let clamped = min(60, max(1, seconds))
        refreshInterval = clamped
        directory.refreshInterval = clamped
        if status == .connected {
            startPolling(token: generation)
        }
    }

    func refreshNow() {
        let token = generation
        Task { await refresh(token: token) }
    }

    func pauseSelected() async {
        await runAction { api, hashes in
            if hashes.count == torrents.count {
                try await api.pauseAll()
            } else {
                try await api.pause(hashes: hashes)
            }
        }
    }

    func resumeSelected() async {
        await runAction { api, hashes in
            if hashes.count == torrents.count {
                try await api.resumeAll()
            } else {
                try await api.resume(hashes: hashes)
            }
        }
    }

    func pauseAll() async {
        await runBulk { try await $0.pauseAll() }
    }

    func resumeAll() async {
        await runBulk { try await $0.resumeAll() }
    }

    func removeSelected(deleteData: Bool) async {
        let hashes = Array(selectedHashes)
        await runBulk { api in
            for hash in hashes {
                try await api.remove(hash: hash, deleteData: deleteData)
            }
        }
        selectedHashes = []
    }

    func recheckSelected() async {
        await runAction { api, hashes in
            for hash in hashes {
                try await api.recheck(hash: hash)
            }
        }
    }

    func moveSelected(path: String) async {
        guard let hash = selectedHashes.first else { return }
        await runBulk { try await $0.moveStorage(hash: hash, path: path) }
    }

    func setLimits(downloadKiB: Int, uploadKiB: Int, connections: Int) async {
        guard let hash = selectedHashes.first else { return }
        await runBulk { try await $0.setLimits(hash: hash, downloadKiB: downloadKiB, uploadKiB: uploadKiB, connections: connections) }
    }

    func setFilePriority(index: Int, priority: Int) async {
        guard var current = detail, selectedHashes == [current.hash], index >= 0, index < current.filePriorities.count else { return }
        current.filePriorities[index] = priority
        if let fileIndex = current.files.firstIndex(where: { $0.index == index }) {
            current.files[fileIndex].priority = priority
        }
        detail = current
        let priorities = current.filePriorities
        let hash = current.hash
        await runBulk { try await $0.setFilePriorities(hash: hash, priorities: priorities) }
    }

    func addMagnet(_ magnet: String, options: AddTorrentOptions) async throws {
        guard let api else { throw DelugeClientError.transport("Not connected.") }
        try await api.addMagnet(magnet, options: options)
        await refresh(token: generation)
    }

    func addURL(_ url: String, options: AddTorrentOptions) async throws {
        guard let api else { throw DelugeClientError.transport("Not connected.") }
        try await api.addURL(url, options: options)
        await refresh(token: generation)
    }

    func addFile(name: String, data: Data, options: AddTorrentOptions) async throws {
        guard let api else { throw DelugeClientError.transport("Not connected.") }
        try await api.addFile(name: name, data: data, options: options)
        await refresh(token: generation)
    }

    func loadDefaultOptions() async -> AddTorrentOptions {
        guard let api else { return .fallback }
        return (try? await api.defaultOptions()) ?? .fallback
    }

    func receive(_ url: URL) async {
        if url.isFileURL {
            let accessing = url.startAccessingSecurityScopedResource()
            let payload = TorrentPayload.file(at: url)
            if accessing { url.stopAccessingSecurityScopedResource() }
            if let payload {
                await receive([payload])
            } else if TorrentImport.parse(url: url) != nil {
                banner = "Couldn’t read \(url.lastPathComponent)."
            } else {
                banner = "Drop a .torrent file or a magnet link."
            }
            return
        }
        guard case .magnet(let magnet) = TorrentImport.parse(url: url) else {
            banner = "Drop a .torrent file or a magnet link."
            return
        }
        await receive([.magnet(magnet)])
    }

    func receive(_ items: [TorrentPayload]) async {
        guard !items.isEmpty else {
            banner = "Drop a .torrent file or a magnet link."
            return
        }
        if status == .connected, api != nil {
            await performImports(items)
        } else {
            pendingImports.append(contentsOf: items)
            banner = waitingToAddMessage
        }
    }

    private func beginConnect() {
        connectTask?.cancel()
        connectTask = Task { await connect() }
    }

    private func connect() async {
        generation += 1
        let token = generation
        pollTask?.cancel()
        detailTask?.cancel()
        api?.shutdown()
        api = nil
        session = nil
        detail = nil
        banner = nil
        torrents = []
        selectedHashes = []
        authRetries = 0

        guard let server = selectedServer else {
            status = .empty
            return
        }

        let password = directory.password(for: server.id)
        guard !password.isEmpty else {
            status = .failed("Enter the password for \(server.nickname).")
            return
        }

        status = .connecting
        let client = DelugeClient(server: server, password: password)
        do {
            try await client.ensureConnected()
            guard token == generation, !Task.isCancelled else {
                client.shutdown()
                return
            }
            api = client
            status = .connected
            await refresh(token: token)
            guard token == generation else { return }
            await flushPendingImports(token: token)
            guard token == generation else { return }
            startPolling(token: token)
        } catch is CancellationError {
            client.shutdown()
        } catch {
            client.shutdown()
            guard token == generation, !Task.isCancelled else { return }
            status = .failed(errorText(error))
        }
    }

    private func startPolling(token: Int) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled, token == generation {
                try? await Task.sleep(nanoseconds: UInt64(refreshInterval) * 1_000_000_000)
                guard !Task.isCancelled, token == generation else { return }
                await refresh(token: token)
            }
        }
    }

    private func refresh(token: Int) async {
        guard let api, token == generation else { return }
        do {
            let list = try await api.torrents()
            guard token == generation, !Task.isCancelled else { return }
            let snapshot = try await api.sessionSnapshot()
            guard token == generation, !Task.isCancelled else { return }
            torrents = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            session = snapshot
            banner = nil
            status = .connected
            authRetries = 0
            if case .label(let name) = filter, !labels.contains(name) {
                filter = .all
            }
            let valid = Set(list.map(\.id))
            let pruned = selectedHashes.intersection(valid)
            if pruned != selectedHashes {
                selectedHashes = pruned
            } else if pruned.count == 1, let hash = pruned.first {
                if let loaded = try? await api.detail(hash: hash), token == generation, selectedHashes == [hash] {
                    detail = loaded
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            let message = errorText(error)
            if isAuthError(message), authRetries < 1 {
                authRetries += 1
                beginConnect()
                return
            }
            if torrents.isEmpty {
                status = .failed(message)
            } else {
                banner = message
            }
        }
    }

    private func loadDetail() async {
        guard selectedHashes.count == 1, let hash = selectedHashes.first, let api else {
            detail = nil
            return
        }
        do {
            let loaded = try await api.detail(hash: hash)
            guard !Task.isCancelled, selectedHashes == [hash] else { return }
            detail = loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
        }
    }

    private func runAction(_ body: (DelugeClient, [String]) async throws -> Void) async {
        let hashes = Array(selectedHashes)
        guard let api, !hashes.isEmpty else { return }
        do {
            try await body(api, hashes)
            banner = nil
            await refresh(token: generation)
        } catch is CancellationError {
            return
        } catch {
            banner = errorText(error)
        }
    }

    private func runBulk(_ body: (DelugeClient) async throws -> Void) async {
        guard let api else { return }
        do {
            try await body(api)
            banner = nil
            await refresh(token: generation)
        } catch is CancellationError {
            return
        } catch {
            banner = errorText(error)
        }
    }

    private func isAuthError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("not authenticated") || lowered.contains("session")
    }

    private var waitingToAddMessage: String {
        switch status {
        case .empty:
            return "Add a server. The torrent will be added after it connects."
        case .connecting:
            return "The torrent will be added when the server connects."
        case .connected, .failed:
            return "Connect to a server to add this torrent."
        }
    }

    private func flushPendingImports(token: Int) async {
        let items = pendingImports
        pendingImports.removeAll()
        guard !items.isEmpty, token == generation else { return }
        await performImports(items)
    }

    private func performImports(_ items: [TorrentPayload]) async {
        guard let api else {
            pendingImports.append(contentsOf: items)
            banner = waitingToAddMessage
            return
        }
        let options = await loadDefaultOptions()
        guard !Task.isCancelled else { return }
        var failures: [String] = []
        for item in items {
            do {
                switch item {
                case .magnet(let magnet):
                    try await api.addMagnet(magnet, options: options)
                case .file(let name, let data):
                    try await api.addFile(name: name, data: data, options: options)
                }
            } catch is CancellationError {
                return
            } catch {
                failures.append(errorText(error))
            }
        }
        await refresh(token: generation)
        if failures.isEmpty {
            banner = nil
        } else if failures.count == 1 {
            banner = failures[0]
        } else {
            banner = "\(failures.count) torrents couldn’t be added. \(failures[0])"
        }
    }
}

enum TorrentPayload: Equatable {
    case magnet(String)
    case file(name: String, data: Data)

    static func file(at url: URL) -> TorrentPayload? {
        guard case .torrentFile = TorrentImport.parse(url: url) else { return nil }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return .file(name: url.lastPathComponent, data: data)
    }
}

enum ConnectionStatus: Equatable {
    case empty
    case connecting
    case connected
    case failed(String)
}

func errorText(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}
