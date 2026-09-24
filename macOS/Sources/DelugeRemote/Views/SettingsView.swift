import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var handlesMagnets = MagnetLinkHandler.isCurrent

    var body: some View {
        Form {
            Stepper(value: Binding(
                get: { model.refreshInterval },
                set: { model.updateRefreshInterval($0) }
            ), in: 1...60) {
                Text("Refresh every \(model.refreshInterval) seconds")
            }
            LabeledContent("Magnet links") {
                if handlesMagnets {
                    Text("This app")
                } else {
                    Button("Use Deluge Remote") {
                        handlesMagnets = MagnetLinkHandler.claim()
                    }
                }
            }
            LabeledContent("Servers") {
                Text("Saved on this Mac")
            }
            Text("Server addresses and passwords are stored in Application Support on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear { handlesMagnets = MagnetLinkHandler.isCurrent }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}
