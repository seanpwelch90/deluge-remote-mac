import SwiftUI
import DelugeRemoteCore

enum SidebarPick: Hashable {
    case filter(TorrentFilter)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var pick: SidebarPick?
    @State private var openedHash: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var isDropTargeted = false
    @State private var isPresentingSettings = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(pick: $pick, showList: showList) {
                isPresentingSettings = true
            }
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } content: {
            TorrentListView(openedHash: $openedHash)
        } detail: {
            TorrentDetailView()
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $model.isPresentingServerEditor) {
            ClientEditorView(existingID: model.serverEditorID)
                .environment(model)
        }
        .sheet(isPresented: $model.isPresentingAddTorrent) {
            AddTorrentView()
                .environment(model)
        }
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView()
                .environment(model)
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
        .task { await model.start() }
        .onOpenURL { url in
            Task { await model.receive(url) }
        }
        .onChange(of: openedHash) { _, hash in
            model.selectedHashes = hash.map { [$0] } ?? []
        }
        .onChange(of: model.status) { _, status in
            guard status == .connected else { return }
            if pick == nil { pick = .filter(model.filter) }
            showList()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, model.status == .connected {
                model.refreshNow()
            }
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

    private func showList() {
        if horizontalSizeClass == .compact {
            columnVisibility = .doubleColumn
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
    @Binding var pick: SidebarPick?
    var showList: () -> Void
    var showSettings: () -> Void
    @State private var serverPendingDelete: ServerConfig?

    private let libraryFilters: [TorrentFilter] = [
        .all, .downloading, .seeding, .paused, .queued, .checking, .error
    ]

    var body: some View {
        @Bindable var model = model
        List(selection: $pick) {
            Section("Servers") {
                if model.servers.isEmpty {
                    ContentUnavailableView {
                        Label("Add a Deluge Server", systemImage: "server.rack")
                    } description: {
                        Text("Use the host, port, and password from Deluge WebUI. The usual address is http://your-server:8112.")
                    } actions: {
                        Button("Add Server") { model.presentAddServer() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(model.servers) { server in
                    serverRow(server)
                }
            }

            if model.status == .connecting {
                Section {
                    HStack {
                        ProgressView()
                        Text("Connecting to \(model.selectedServer?.nickname ?? "Deluge")…")
                    }
                }
            }

            if case .failed(let message) = model.status {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                    Button("Try Again") { model.retry() }
                    if let id = model.selectedServerID {
                        Button("Edit Server") { model.presentEditServer(id) }
                    }
                }
            }

            if model.status == .connected {
                Section("Show") {
                    ForEach(libraryFilters, id: \.self) { filter in
                        filterRow(filter)
                            .tag(SidebarPick.filter(filter))
                    }
                }
                if !model.labels.isEmpty {
                    Section("Labels") {
                        ForEach(model.labels, id: \.self) { label in
                            filterRow(.label(label), title: label, symbol: "tag")
                                .tag(SidebarPick.filter(.label(label)))
                        }
                    }
                }
            }
        }
        .navigationTitle("Deluge Remote")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.presentAddServer()
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: pick) { _, newValue in
            if case .filter(let filter) = newValue {
                model.filter = filter
                showList()
            }
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
            Text("This forgets the server on this device. It does not change Deluge.")
        }
    }

    private func serverRow(_ server: ServerConfig) -> some View {
        let selected = model.selectedServerID == server.id
        return Button {
            model.selectServer(server.id)
            pick = .filter(model.filter)
            showList()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Remove", role: .destructive) { serverPendingDelete = server }
            Button("Edit") { model.presentEditServer(server.id) }
                .tint(.indigo)
        }
        .contextMenu {
            Button("Edit") { model.presentEditServer(server.id) }
            Button("Remove", role: .destructive) { serverPendingDelete = server }
        }
    }

    private func filterRow(_ filter: TorrentFilter, title: String? = nil, symbol: String? = nil) -> some View {
        HStack {
            Label(title ?? filterTitle(filter), systemImage: symbol ?? filterSymbol(filter))
            Spacer()
            Text("\(model.torrents.filter { filter.matches($0) }.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .empty: return .secondary
        }
    }
}
