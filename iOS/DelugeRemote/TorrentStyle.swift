import SwiftUI
import DelugeRemoteCore

enum TorrentSort: String, CaseIterable, Identifiable {
    case queue
    case name
    case progress
    case size
    case download
    case upload
    case added

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queue: return "Queue"
        case .name: return "Name"
        case .progress: return "Progress"
        case .size: return "Size"
        case .download: return "Download Speed"
        case .upload: return "Upload Speed"
        case .added: return "Date Added"
        }
    }

    func apply(_ torrents: [Torrent]) -> [Torrent] {
        switch self {
        case .queue:
            return torrents.sorted { ($0.queueOrder, $0.name) < ($1.queueOrder, $1.name) }
        case .name:
            return torrents.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .progress:
            return torrents.sorted { ($0.progress, $0.name) > ($1.progress, $1.name) }
        case .size:
            return torrents.sorted { ($0.totalSize, $0.name) > ($1.totalSize, $1.name) }
        case .download:
            return torrents.sorted { ($0.downloadRate, $0.name) > ($1.downloadRate, $1.name) }
        case .upload:
            return torrents.sorted { ($0.uploadRate, $0.name) > ($1.uploadRate, $1.name) }
        case .added:
            return torrents.sorted { $0.timeAdded > $1.timeAdded }
        }
    }
}

func queueLabel(_ queue: Int) -> String {
    queue >= 0 ? String(queue + 1) : "—"
}

func stateSymbol(_ torrent: Torrent) -> String {
    if torrent.displayState == "Paused" { return "pause.circle.fill" }
    switch torrent.state {
    case "Downloading": return "arrow.down.circle.fill"
    case "Seeding": return "arrow.up.circle.fill"
    case "Error": return "exclamationmark.triangle.fill"
    case "Queued": return "clock.fill"
    default:
        if torrent.state.hasPrefix("Check") || torrent.state == "Allocating" || torrent.state == "Moving" {
            return "arrow.triangle.2.circlepath"
        }
        return "circle.fill"
    }
}

func stateColor(_ torrent: Torrent) -> Color {
    if torrent.displayState == "Paused" { return .secondary }
    switch torrent.state {
    case "Downloading": return .blue
    case "Seeding": return .green
    case "Error": return .red
    case "Queued": return .orange
    default:
        if torrent.state.hasPrefix("Check") || torrent.state == "Allocating" || torrent.state == "Moving" {
            return .orange
        }
        return .secondary
    }
}

func filterTitle(_ filter: TorrentFilter) -> String {
    switch filter {
    case .all: return "All"
    case .downloading: return "Downloading"
    case .seeding: return "Seeding"
    case .paused: return "Paused"
    case .queued: return "Queued"
    case .checking: return "Checking"
    case .error: return "Error"
    case .label(let name): return name
    }
}

func filterSymbol(_ filter: TorrentFilter) -> String {
    switch filter {
    case .all: return "tray.full"
    case .downloading: return "arrow.down.circle"
    case .seeding: return "arrow.up.circle"
    case .paused: return "pause.circle"
    case .queued: return "clock"
    case .checking: return "checkmark.circle"
    case .error: return "exclamationmark.triangle"
    case .label: return "tag"
    }
}
