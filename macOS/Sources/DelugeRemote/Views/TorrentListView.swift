import AppKit
import SwiftUI
import DelugeRemoteCore

struct TorrentListView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("DelugeRemote.torrentColumns") private var columnCustomization = TableColumnCustomization<Torrent>()
    @State private var query = ""
    @State private var sortOrder = [KeyPathComparator(\Torrent.timeAdded, order: .reverse)]

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let banner = model.banner {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(banner)
                        .lineLimit(2)
                    Spacer()
                    Button("Retry") { model.refreshNow() }
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.yellow.opacity(0.15))
            }

            Group {
                switch model.status {
                case .empty:
                    ContentUnavailableView {
                        Label("Add a Deluge Server", systemImage: "server.rack")
                    } description: {
                        Text("Use the host, port, and password from Deluge WebUI. The usual address is http://your-server:8112.")
                    } actions: {
                        Button("Add Server…") { model.presentAddServer() }
                            .buttonStyle(.borderedProminent)
                    }
                case .connecting:
                    ProgressView("Connecting to \(model.selectedServer?.nickname ?? "Deluge")…")
                        .controlSize(.large)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t Connect", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { model.retry() }
                            .buttonStyle(.borderedProminent)
                        Button("Edit Server") {
                            if let id = model.selectedServerID { model.presentEditServer(id) }
                        }
                    }
                case .connected:
                    torrentTable
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.status == .connected {
                statusBar
            }
        }
        .searchable(text: $query, prompt: "Name, hash, or tracker")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.presentAddTorrent()
                } label: {
                    Label("Add Torrent", systemImage: "plus")
                }
                .disabled(model.status != .connected)
                .help("Add Torrent")

                Button {
                    Task { await model.pauseSelected() }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(model.selectedHashes.isEmpty)

                Button {
                    Task { await model.resumeSelected() }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .disabled(model.selectedHashes.isEmpty)

                Button {
                    model.isPresentingRemove = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(model.selectedHashes.isEmpty)

                Menu {
                    ForEach(TorrentTableColumn.allCases) { column in
                        Toggle(column.title, isOn: columnVisibility(column))
                            .disabled(!column.canHide)
                    }
                    Divider()
                    Button("Reset Columns") {
                        columnCustomization = TableColumnCustomization<Torrent>()
                    }
                } label: {
                    Label("Columns", systemImage: "tablecells")
                }
                .help("Show or hide columns. Drag a column header to change the order.")

                Menu {
                    Button("Pause All") { Task { await model.pauseAll() } }
                    Button("Resume All") { Task { await model.resumeAll() } }
                    Divider()
                    Button("Force Recheck") { Task { await model.recheckSelected() } }
                        .disabled(model.selectedHashes.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(model.status != .connected)

                Button {
                    model.refreshNow()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.status != .connected)
            }
        }
        .inspector(isPresented: inspectorPresented) {
            TorrentDetailView()
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { model.selectedHashes.count == 1 && model.status == .connected },
            set: { if !$0 { model.selectedHashes = [] } }
        )
    }

    private var torrentTable: some View {
        @Bindable var model = model
        let rows = visibleTorrents
        return Table(rows, selection: $model.selectedHashes, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("Name", value: \.name) { torrent in
                HStack(spacing: 8) {
                    Image(systemName: stateSymbol(torrent))
                        .foregroundStyle(stateColor(torrent))
                        .frame(width: 16)
                    Text(torrent.name)
                        .lineLimit(1)
                    if !torrent.label.isEmpty {
                        Text(torrent.label)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            .width(min: 220, ideal: 360)
            .customizationID(TorrentTableColumn.name.id)
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Progress", value: \.progress) { torrent in
                HStack(spacing: 8) {
                    ProgressView(value: min(max(torrent.progress, 0), 100), total: 100)
                    Text(percentString(torrent.progress))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
            .width(min: 140, ideal: 170)
            .customizationID(TorrentTableColumn.progress.id)

            TableColumn("Size", value: \.totalSize) { torrent in
                Text(torrent.totalSize.byteString)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            .customizationID(TorrentTableColumn.size.id)

            TableColumn("Down", value: \.downloadRate) { torrent in
                Text(torrent.downloadRate.byteRateString)
                    .monospacedDigit()
                    .foregroundStyle(torrent.downloadRate > 0 ? Color.blue : .secondary)
            }
            .width(min: 80, ideal: 100)
            .customizationID(TorrentTableColumn.down.id)

            TableColumn("Up", value: \.uploadRate) { torrent in
                Text(torrent.uploadRate.byteRateString)
                    .monospacedDigit()
                    .foregroundStyle(torrent.uploadRate > 0 ? Color.green : .secondary)
            }
            .width(min: 80, ideal: 100)
            .customizationID(TorrentTableColumn.up.id)

            TableColumn("Ratio", value: \.ratio) { torrent in
                Text(ratioString(torrent.ratio))
                    .monospacedDigit()
            }
            .width(min: 52, ideal: 64)
            .customizationID(TorrentTableColumn.ratio.id)

            TableColumn("ETA", value: \.eta) { torrent in
                Text(etaString(seconds: torrent.eta, paused: torrent.paused, progress: torrent.progress))
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            .customizationID(TorrentTableColumn.eta.id)

            TableColumn("Added", value: \.timeAdded) { torrent in
                Text(torrent.timeAdded.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            .customizationID(TorrentTableColumn.added.id)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Torrent.ID.self) { ids in
            Button("Pause") {
                model.selectedHashes = ids
                Task { await model.pauseSelected() }
            }
            Button("Resume") {
                model.selectedHashes = ids
                Task { await model.resumeSelected() }
            }
            Button("Force Recheck") {
                model.selectedHashes = ids
                Task { await model.recheckSelected() }
            }
            Divider()
            Button("Copy Hash") { copy(ids.sorted().joined(separator: "\n")) }
            Divider()
            Button("Remove…", role: .destructive) {
                model.selectedHashes = ids
                model.isPresentingRemove = true
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Torrents" : "No Matches",
                    systemImage: query.isEmpty ? "arrow.down.circle" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Drop a torrent file or magnet link, or use Add Torrent." : "Try a different name, hash, or tracker.")
                )
            }
        }
    }

    private var visibleTorrents: [Torrent] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.torrents.filter { torrent in
            guard model.filter.matches(torrent) else { return false }
            guard !needle.isEmpty else { return true }
            return [torrent.name, torrent.hash, torrent.trackerHost, torrent.label]
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(needle)
        }
        .sorted(using: sortOrder)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text(summary)
            Spacer()
            if let session = model.session {
                Label(session.downloadRate.byteRateString, systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Label(session.uploadRate.byteRateString, systemImage: "arrow.up")
                    .foregroundStyle(.green)
                Text("\(session.peers) peers")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var summary: String {
        let visible = visibleTorrents.count
        let downloading = model.torrents.filter { TorrentFilter.downloading.matches($0) }.count
        if visible == model.torrents.count {
            return "\(model.torrents.count) torrents · \(downloading) downloading"
        }
        return "\(visible) shown · \(model.torrents.count) torrents · \(downloading) downloading"
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func columnVisibility(_ column: TorrentTableColumn) -> Binding<Bool> {
        Binding(
            get: { columnCustomization[visibility: column.id] != .hidden },
            set: { shown in
                columnCustomization[visibility: column.id] = shown ? .visible : .hidden
            }
        )
    }
}

enum TorrentTableColumn: String, CaseIterable, Identifiable {
    case name
    case progress
    case size
    case down
    case up
    case ratio
    case eta
    case added

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .progress: return "Progress"
        case .size: return "Size"
        case .down: return "Down"
        case .up: return "Up"
        case .ratio: return "Ratio"
        case .eta: return "ETA"
        case .added: return "Added"
        }
    }

    var canHide: Bool { self != .name }
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
