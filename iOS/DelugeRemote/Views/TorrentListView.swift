import SwiftUI
import DelugeRemoteCore

struct TorrentListView: View {
    @Environment(AppModel.self) private var model
    @Binding var openedHash: String?
    @AppStorage("DelugeRemote.iosSort") private var sort = TorrentSort.queue
    @State private var query = ""
    @State private var isSelecting = false
    @State private var bulk = Set<String>()
    @State private var pendingRemoval: [String] = []

    var body: some View {
        Group {
            switch model.status {
            case .empty:
                ContentUnavailableView {
                    Label("Add a Deluge Server", systemImage: "server.rack")
                } description: {
                    Text("Use the host, port, and password from Deluge WebUI.")
                } actions: {
                    Button("Add Server") { model.presentAddServer() }
                        .buttonStyle(.borderedProminent)
                }
            case .connecting:
                ProgressView("Connecting to \(model.selectedServer?.nickname ?? "Deluge")…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t Connect", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { model.retry() }
                        .buttonStyle(.borderedProminent)
                    if let id = model.selectedServerID {
                        Button("Edit Server") { model.presentEditServer(id) }
                    }
                }
            case .connected:
                torrentList
            }
        }
        .navigationTitle(filterTitle(model.filter))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Name, hash, or tracker")
        .toolbar { toolbar }
        .confirmationDialog(removalTitle, isPresented: removalPresented, titleVisibility: .visible) {
            Button("Remove Torrent", role: .destructive) {
                let hashes = pendingRemoval
                pendingRemoval = []
                Task { await model.remove(hashes, deleteData: false) }
            }
            Button("Remove and Delete Files", role: .destructive) {
                let hashes = pendingRemoval
                pendingRemoval = []
                Task { await model.remove(hashes, deleteData: true) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = [] }
        } message: {
            Text("Removing a torrent drops it from Deluge. Deleting files also removes the downloaded data on the server.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.presentAddTorrent()
            } label: {
                Label("Add Torrent", systemImage: "plus")
            }
            .disabled(model.status != .connected)
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button(isSelecting ? "Done" : "Select") {
                isSelecting.toggle()
                if !isSelecting { bulk = [] }
            }
            .disabled(model.status != .connected)
            Menu {
                ForEach(TorrentSort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if option == sort {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            Menu {
                Button("Pause All") { Task { await model.pauseAll() } }
                Button("Resume All") { Task { await model.resumeAll() } }
                Divider()
                Button("Refresh") { model.refreshNow() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(model.status != .connected)
        }
    }

    private var torrentList: some View {
        let rows = visibleTorrents
        return Group {
            if isSelecting {
                List(rows, selection: $bulk) { torrent in
                    row(torrent).tag(torrent.id)
                }
                .environment(\.editMode, .constant(.active))
            } else {
                List(rows, selection: $openedHash) { torrent in
                    row(torrent)
                        .tag(torrent.id)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(torrent.paused || torrent.state == "Paused" ? "Resume" : "Pause") {
                                let hash = torrent.hash
                                Task {
                                    if torrent.paused || torrent.state == "Paused" {
                                        await model.resume([hash])
                                    } else {
                                        await model.pause([hash])
                                    }
                                }
                            }
                            .tint(torrent.paused || torrent.state == "Paused" ? .green : .orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Remove", role: .destructive) {
                                pendingRemoval = [torrent.hash]
                            }
                        }
                        .contextMenu {
                            Button(torrent.paused || torrent.state == "Paused" ? "Resume" : "Pause") {
                                let hash = torrent.hash
                                Task {
                                    if torrent.paused || torrent.state == "Paused" {
                                        await model.resume([hash])
                                    } else {
                                        await model.pause([hash])
                                    }
                                }
                            }
                            Button("Force Recheck") {
                                Task { await model.recheck([torrent.hash]) }
                            }
                            Divider()
                            ForEach(QueueMove.allCases) { move in
                                Button(move.title, systemImage: move.symbol) {
                                    Task { await model.moveInQueue(move, hashes: [torrent.hash]) }
                                }
                            }
                            Divider()
                            Button("Remove", role: .destructive) {
                                pendingRemoval = [torrent.hash]
                            }
                        }
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No Torrents" : "No Matches",
                    systemImage: query.isEmpty ? "arrow.down.circle" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Add a torrent file, magnet link, or URL." : "Try a different name, hash, or tracker.")
                )
            }
        }
        .refreshable { await model.reload() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if isSelecting, !bulk.isEmpty {
                    bulkBar
                    Divider()
                }
                statusBar
            }
        }
    }

    private var bulkBar: some View {
        HStack {
            Button("Pause") { Task { await model.pause(Array(bulk)) } }
            Button("Resume") { Task { await model.resume(Array(bulk)) } }
            Menu("Queue") {
                ForEach(QueueMove.allCases) { move in
                    Button(move.title, systemImage: move.symbol) {
                        Task { await model.moveInQueue(move, hashes: Array(bulk)) }
                    }
                }
            }
            Spacer()
            Button("Remove", role: .destructive) {
                pendingRemoval = Array(bulk)
            }
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(summary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let session = model.session {
                Label(session.downloadRate.byteRateString, systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Label(session.uploadRate.byteRateString, systemImage: "arrow.up")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func row(_ torrent: Torrent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(queueLabel(torrent.queue))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(torrent.queue >= 0 ? Color.secondary : Color.clear)
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: stateSymbol(torrent))
                        .foregroundStyle(stateColor(torrent))
                    Text(torrent.name)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    if !torrent.label.isEmpty {
                        Text(torrent.label)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                ProgressView(value: min(max(torrent.progress, 0), 100), total: 100)
                HStack {
                    Text(torrent.downloadRate.byteRateString)
                        .foregroundStyle(torrent.downloadRate > 0 ? Color.blue : .secondary)
                    Text(torrent.uploadRate.byteRateString)
                        .foregroundStyle(torrent.uploadRate > 0 ? Color.green : .secondary)
                    Spacer()
                    Text(etaString(seconds: torrent.eta, paused: torrent.paused, progress: torrent.progress))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.vertical, 4)
    }

    private var visibleTorrents: [Torrent] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = model.torrents.filter { torrent in
            guard model.filter.matches(torrent) else { return false }
            guard !needle.isEmpty else { return true }
            return [torrent.name, torrent.hash, torrent.trackerHost, torrent.label]
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(needle)
        }
        return sort.apply(filtered)
    }

    private var summary: String {
        let visible = visibleTorrents.count
        let downloading = model.torrents.filter { TorrentFilter.downloading.matches($0) }.count
        if let banner = model.banner, !banner.isEmpty {
            return banner
        }
        if visible == model.torrents.count {
            return "\(model.torrents.count) torrents · \(downloading) downloading"
        }
        return "\(visible) shown · \(model.torrents.count) torrents"
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { !pendingRemoval.isEmpty },
            set: { if !$0 { pendingRemoval = [] } }
        )
    }

    private var removalTitle: String {
        if pendingRemoval.count == 1,
           let name = model.torrents.first(where: { $0.hash == pendingRemoval[0] })?.name {
            return "Remove \(name)?"
        }
        return "Remove \(pendingRemoval.count) torrents?"
    }
}
