import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: Binding(
                    get: { model.refreshInterval },
                    set: { model.updateRefreshInterval($0) }
                ), in: 1...60) {
                    Text("Refresh every \(model.refreshInterval) seconds")
                }
                Section {
                    LabeledContent("Servers", value: "On this device")
                } footer: {
                    Text("Server addresses and passwords stay in this app’s private storage. Magnet links and .torrent files can be opened with Deluge Remote.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
