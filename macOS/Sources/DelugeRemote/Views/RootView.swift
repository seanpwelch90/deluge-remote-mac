import SwiftUI
import DelugeRemoteCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            TorrentListView()
        }
        .navigationTitle(model.selectedServer?.nickname ?? "Deluge Remote")
        .sheet(isPresented: $model.isPresentingServerEditor) {
            ClientEditorView(existingID: model.serverEditorID)
        }
        .sheet(isPresented: $model.isPresentingAddTorrent) {
            AddTorrentView()
        }
        .confirmationDialog(removeTitle, isPresented: $model.isPresentingRemove, titleVisibility: .visible) {
            Button("Remove Torrent", role: .destructive) {
                Task { await model.removeSelected(deleteData: false) }
            }
            Button("Remove and Delete Files", role: .destructive) {
                Task { await model.removeSelected(deleteData: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing a torrent drops it from Deluge. Deleting files also removes the downloaded data on the server.")
        }
        .task {
            MagnetLinkHandler.claim()
            await model.start()
        }
        .onOpenURL { url in
            Task { await model.receive(url) }
        }
        .onDrop(of: TorrentDrop.contentTypes, isTargeted: $isDropTargeted) { providers in
            guard TorrentDrop.canAccept(providers) else { return false }
            TorrentDrop.beginImport(providers, into: model)
            return true
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    Color.accentColor.opacity(0.12)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                        .padding(10)
                    Label("Drop to add", systemImage: "plus.circle.fill")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var removeTitle: String {
        let count = model.selectedHashes.count
        if count == 1, let name = model.selectedTorrents.first?.name {
            return "Remove \(name)?"
        }
        return "Remove \(count) torrents?"
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var serverPendingDelete: ServerConfig?

    var body: some View {
        @Bindable var model = model
        List {
            Section("Servers") {
                if model.servers.isEmpty {
                    Text("No servers yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.servers) { server in
                    serverRow(server)
                }
            }

            if model.status == .connected {
                Section("Show") {
                    ForEach(libraryFilters, id: \.self) { filter in
                        filterRow(filter)
                    }
                }

                if !model.labels.isEmpty {
                    Section("Labels") {
                        ForEach(model.labels, id: \.self) { label in
                            filterRow(.label(label), title: label, symbol: "tag")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                model.presentAddServer()
            } label: {
                Label("Add Server", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .confirmationDialog(
            "Remove \(serverPendingDelete?.nickname ?? "server")?",
            isPresented: Binding(
                get: { serverPendingDelete != nil },
                set: { if !$0 { serverPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Server", role: .destructive) {
                if let serverPendingDelete {
                    model.deleteServer(serverPendingDelete.id)
                }
                serverPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { serverPendingDelete = nil }
        } message: {
            Text("This forgets the server on this Mac. It does not change Deluge.")
        }
    }

    private var libraryFilters: [TorrentFilter] {
        [.all, .downloading, .seeding, .paused, .queued, .checking, .error]
    }

    private func serverRow(_ server: ServerConfig) -> some View {
        let selected = model.selectedServerID == server.id
        return Button {
            model.selectServer(server.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(server.nickname)
                        .fontWeight(selected ? .semibold : .regular)
                    Text(server.hostname)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") { model.presentEditServer(server.id) }
            Button("Remove", role: .destructive) { serverPendingDelete = server }
        }
    }

    private func filterRow(_ filter: TorrentFilter, title: String? = nil, symbol: String? = nil) -> some View {
        let selected = model.filter == filter
        return Button {
            model.filter = filter
        } label: {
            HStack {
                Label(title ?? filterTitle(filter), systemImage: symbol ?? filterSymbol(filter))
                Spacer()
                Text("\(model.torrents.filter { filter.matches($0) }.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : .primary)
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .empty: return .secondary
        }
    }

    private func filterTitle(_ filter: TorrentFilter) -> String {
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

    private func filterSymbol(_ filter: TorrentFilter) -> String {
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
}
