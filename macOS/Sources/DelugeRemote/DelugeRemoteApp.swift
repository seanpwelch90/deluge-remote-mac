import SwiftUI
import DelugeRemoteCore

@main
struct DelugeRemoteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Deluge Remote", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 540)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: [])
        .defaultSize(width: 1180, height: 760)
        .commands {
            TorrentCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct TorrentCommands: Commands {
    var model: AppModel
    @AppStorage("DelugeRemote.torrentColumns") private var columnCustomization = TableColumnCustomization<Torrent>()

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Torrent…") { model.presentAddTorrent() }
                .keyboardShortcut("n")
                .disabled(model.status != .connected)
            Button("Add Server…") { model.presentAddServer() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Torrents") {
            Button("Pause") { Task { await model.pauseSelected() } }
                .disabled(model.selectedHashes.isEmpty)
            Button("Resume") { Task { await model.resumeSelected() } }
                .disabled(model.selectedHashes.isEmpty)
            Divider()
            Button("Pause All") { Task { await model.pauseAll() } }
                .disabled(model.status != .connected)
            Button("Resume All") { Task { await model.resumeAll() } }
                .disabled(model.status != .connected)
            Divider()
            Button("Force Recheck") { Task { await model.recheckSelected() } }
                .disabled(model.selectedHashes.isEmpty)
            Button("Remove…") { model.isPresentingRemove = true }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(model.selectedHashes.isEmpty)
            Divider()
            Button("Refresh") { model.refreshNow() }
                .keyboardShortcut("r")
                .disabled(model.status != .connected)
        }

        CommandGroup(before: .toolbar) {
            Menu("Columns") {
                ForEach(TorrentTableColumn.allCases) { column in
                    Toggle(column.title, isOn: columnVisibility(column))
                        .disabled(!column.canHide)
                }
                Divider()
                Button("Reset Columns") {
                    columnCustomization = TableColumnCustomization<Torrent>()
                }
            }
        }
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
