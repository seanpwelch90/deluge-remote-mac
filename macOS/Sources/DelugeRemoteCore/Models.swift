import Foundation

public enum TorrentFilter: Hashable, Sendable {
    case all
    case downloading
    case seeding
    case paused
    case queued
    case checking
    case error
    case label(String)

    public func matches(_ torrent: Torrent) -> Bool {
        switch self {
        case .all:
            return true
        case .downloading:
            return torrent.state == "Downloading" && !torrent.paused
        case .seeding:
            return torrent.state == "Seeding" && !torrent.paused
        case .paused:
            return torrent.paused || torrent.state == "Paused"
        case .queued:
            return torrent.state == "Queued" && !torrent.paused
        case .checking:
            return torrent.state.hasPrefix("Check") || torrent.state == "Allocating" || torrent.state == "Moving"
        case .error:
            return torrent.state == "Error"
        case .label(let label):
            return torrent.label == label
        }
    }
}

public struct Torrent: Identifiable, Hashable, Sendable {
    public var id: String { hash }
    public let hash: String
    public var name: String
    public var state: String
    public var paused: Bool
    public var progress: Double
    public var ratio: Double
    public var downloadRate: Double
    public var uploadRate: Double
    public var totalSize: Int64
    public var totalWanted: Int64
    public var downloaded: Int64
    public var uploaded: Int64
    public var eta: Double
    public var trackerHost: String
    public var label: String
    public var timeAdded: Date

    public var displayState: String {
        if paused && state != "Error" && state != "Paused" {
            return "Paused"
        }
        return state.isEmpty ? "Unknown" : state
    }

    public static func list(from result: JSONValue) -> [Torrent] {
        guard case .object(let torrents) = result else { return [] }
        return torrents.compactMap { key, value in
            Torrent(hash: value["hash"]?.string ?? key, json: value)
        }
    }

    init?(hash: String, json: JSONValue) {
        guard case .object = json else { return nil }
        let state = json["state"]?.string ?? ""
        self.hash = hash
        self.name = json["name"]?.string ?? "Unknown"
        self.state = state
        self.paused = json["paused"]?.bool ?? (state == "Paused")
        self.progress = json["progress"]?.double ?? 0
        self.ratio = json["ratio"]?.double ?? 0
        self.downloadRate = json["download_payload_rate"]?.double ?? 0
        self.uploadRate = json["upload_payload_rate"]?.double ?? 0
        self.totalSize = json["total_size"]?.int64 ?? 0
        self.totalWanted = json["total_wanted"]?.int64 ?? json["total_size"]?.int64 ?? 0
        self.downloaded = json["all_time_download"]?.int64 ?? json["total_done"]?.int64 ?? 0
        self.uploaded = json["total_uploaded"]?.int64 ?? 0
        self.eta = json["eta"]?.double ?? 0
        self.trackerHost = Self.trackerHost(from: json)
        self.label = json["label"]?.string ?? ""
        self.timeAdded = Date(timeIntervalSince1970: json["time_added"]?.double ?? 0)
    }

    static func trackerHost(from json: JSONValue) -> String {
        if let host = json["tracker_host"]?.string, !host.isEmpty { return host }
        if let tracker = json["tracker"]?.string, let host = URL(string: tracker)?.host { return host }
        return ""
    }
}

public struct TorrentFile: Identifiable, Hashable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let path: String
    public let size: Int64
    public var progress: Double
    public var priority: Int

    public var priorityName: String {
        switch priority {
        case 0: return "Skip"
        case 1: return "Normal"
        case 7: return "Highest"
        default: return priority > 1 ? "High" : "Normal"
        }
    }
}

public struct TorrentDetail: Equatable, Sendable {
    public var hash: String
    public var name: String
    public var state: String
    public var paused: Bool
    public var progress: Double
    public var ratio: Double
    public var downloadRate: Double
    public var uploadRate: Double
    public var totalSize: Int64
    public var downloaded: Int64
    public var uploaded: Int64
    public var eta: Double
    public var trackerHost: String
    public var trackerStatus: String
    public var savePath: String
    public var comment: String
    public var message: String
    public var label: String
    public var timeAdded: Date
    public var seeds: Int
    public var peers: Int
    public var maxDownloadSpeed: Int
    public var maxUploadSpeed: Int
    public var maxConnections: Int
    public var files: [TorrentFile]
    public var filePriorities: [Int]

    public var displayState: String {
        if paused && state != "Error" && state != "Paused" {
            return "Paused"
        }
        return state.isEmpty ? "Unknown" : state
    }

    public static func parse(hash: String, json: JSONValue) -> TorrentDetail? {
        guard let torrent = Torrent(hash: hash, json: json) else { return nil }
        let files = Self.files(from: json)
        var priorities: [Int] = []
        if case .array(let values) = json["file_priorities"] {
            priorities = values.compactMap(\.int)
        }
        if priorities.isEmpty {
            let count = (files.map(\.index).max() ?? -1) + 1
            priorities = Array(repeating: 1, count: count)
            for file in files where file.index >= 0 && file.index < priorities.count {
                priorities[file.index] = file.priority
            }
        }
        return TorrentDetail(
            hash: torrent.hash,
            name: torrent.name,
            state: torrent.state,
            paused: torrent.paused,
            progress: torrent.progress,
            ratio: torrent.ratio,
            downloadRate: torrent.downloadRate,
            uploadRate: torrent.uploadRate,
            totalSize: torrent.totalSize,
            downloaded: json["total_done"]?.int64 ?? torrent.downloaded,
            uploaded: torrent.uploaded,
            eta: torrent.eta,
            trackerHost: torrent.trackerHost,
            trackerStatus: json["tracker_status"]?.string ?? "",
            savePath: json["save_path"]?.string ?? "",
            comment: json["comment"]?.string ?? "",
            message: json["message"]?.string ?? "",
            label: torrent.label,
            timeAdded: torrent.timeAdded,
            seeds: json["num_seeds"]?.int ?? 0,
            peers: json["num_peers"]?.int ?? 0,
            maxDownloadSpeed: json["max_download_speed"]?.int ?? -1,
            maxUploadSpeed: json["max_upload_speed"]?.int ?? -1,
            maxConnections: json["max_connections"]?.int ?? -1,
            files: files,
            filePriorities: priorities
        )
    }

    private static func files(from json: JSONValue) -> [TorrentFile] {
        guard case .array(let values) = json["files"] else { return [] }
        let progresses = progressList(json["file_progress"])
        let scale = (progresses.max() ?? 0) <= 1 ? 100.0 : 1.0
        let priorities: [Int]
        if case .array(let raw) = json["file_priorities"] {
            priorities = raw.compactMap(\.int)
        } else {
            priorities = []
        }
        return values.enumerated().compactMap { offset, item in
            let index = item["index"]?.int ?? offset
            let progressSource = index < progresses.count ? progresses[index] : 0
            let priority = index < priorities.count ? priorities[index] : 1
            return TorrentFile(
                index: index,
                path: item["path"]?.string ?? "File \(index)",
                size: item["size"]?.int64 ?? 0,
                progress: progressSource * scale,
                priority: priority
            )
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func progressList(_ value: JSONValue?) -> [Double] {
        guard let value else { return [] }
        if case .array(let values) = value { return values.compactMap(\.double) }
        if let only = value.double { return [only] }
        return []
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public var downloadRate: Double
    public var uploadRate: Double
    public var peers: Int

    public static func parse(_ value: JSONValue) -> SessionSnapshot {
        SessionSnapshot(
            downloadRate: value["payload_download_rate"]?.double ?? value["download_rate"]?.double ?? 0,
            uploadRate: value["payload_upload_rate"]?.double ?? value["upload_rate"]?.double ?? 0,
            peers: value["num_peers"]?.int ?? 0
        )
    }
}

public struct AddTorrentOptions: Equatable, Sendable {
    public var addPaused: Bool
    public var downloadLocation: String
    public var moveCompleted: Bool
    public var moveCompletedPath: String
    public var maxDownloadSpeed: Int
    public var maxUploadSpeed: Int
    public var maxConnections: Int
    public var maxUploadSlots: Int
    public var prioritizeFirstLastPieces: Bool

    public static let fallback = AddTorrentOptions(
        addPaused: false,
        downloadLocation: "",
        moveCompleted: false,
        moveCompletedPath: "",
        maxDownloadSpeed: -1,
        maxUploadSpeed: -1,
        maxConnections: -1,
        maxUploadSlots: -1,
        prioritizeFirstLastPieces: false
    )

    public static func parse(_ value: JSONValue) -> AddTorrentOptions {
        AddTorrentOptions(
            addPaused: value["add_paused"]?.bool ?? false,
            downloadLocation: value["download_location"]?.string ?? "",
            moveCompleted: value["move_completed"]?.bool ?? false,
            moveCompletedPath: value["move_completed_path"]?.string ?? "",
            maxDownloadSpeed: value["max_download_speed_per_torrent"]?.int ?? -1,
            maxUploadSpeed: value["max_upload_speed_per_torrent"]?.int ?? -1,
            maxConnections: value["max_connections_per_torrent"]?.int ?? -1,
            maxUploadSlots: value["max_upload_slots_per_torrent"]?.int ?? -1,
            prioritizeFirstLastPieces: value["prioritize_first_last_pieces"]?.bool ?? false
        )
    }

    public func parameters() -> JSONValue {
        .object([
            "file_priorities": .array([]),
            "add_paused": .bool(addPaused),
            "move_completed": .bool(moveCompleted),
            "download_location": .string(downloadLocation),
            "move_completed_path": .string(moveCompletedPath),
            "max_connections": .int(maxConnections),
            "max_download_speed": .int(maxDownloadSpeed),
            "max_upload_slots": .int(maxUploadSlots),
            "max_upload_speed": .int(maxUploadSpeed),
            "prioritize_first_last_pieces": .bool(prioritizeFirstLastPieces)
        ])
    }
}
