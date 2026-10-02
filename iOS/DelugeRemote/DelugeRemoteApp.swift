import SwiftUI
import DelugeRemoteCore

@main
struct DelugeRemoteiOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
