import SwiftUI
import DelugeRemoteCore

struct ClientEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let existingID: UUID?

    @State private var id = UUID()
    @State private var nickname = ""
    @State private var host = ""
    @State private var port = "8112"
    @State private var path = ""
    @State private var password = ""
    @State private var useTLS = false
    @State private var allowInvalidCertificate = true
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existingID == nil ? "Add Server" : "Edit Server")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 12)

            Form {
                TextField("Name", text: $nickname, prompt: Text("Home NAS"))
                TextField("Host", text: $host, prompt: Text("192.168.1.20 or https://host:8112"))
                    .autocorrectionDisabled()
                TextField("Port", text: $port)
                TextField("Web path", text: $path, prompt: Text("Leave empty for /json"))
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                Toggle("HTTPS", isOn: $useTLS)
                Toggle("Allow untrusted certificates", isOn: $allowInvalidCertificate)
            }
            .formStyle(.grouped)

            Text("Allow untrusted certificates when Deluge uses a self-signed certificate on your network.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            if let testMessage {
                Text(testMessage)
                    .font(.callout)
                    .foregroundStyle(testSucceeded ? Color.green : Color.red)
                    .padding(.top, 8)
            }

            HStack {
                Button("Test Connection") { Task { await test() } }
                    .disabled(isTesting || draftServer == nil)
                if isTesting { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(existingID == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftServer == nil)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: load)
    }

    private var draftServer: ServerConfig? {
        ServerConfig.make(
            id: id,
            nickname: nickname,
            host: host,
            port: Int(port) ?? 0,
            path: path,
            useTLS: useTLS,
            allowInvalidCertificate: allowInvalidCertificate
        )
    }

    private func load() {
        guard let existingID, let server = model.servers.first(where: { $0.id == existingID }) else { return }
        id = server.id
        nickname = server.nickname
        host = server.hostname
        port = String(server.port)
        path = server.path
        password = model.password(for: server.id)
        useTLS = server.useTLS
        allowInvalidCertificate = server.allowInvalidCertificate
    }

    private func test() async {
        guard let server = draftServer else { return }
        isTesting = true
        testMessage = nil
        let client = DelugeClient(server: server, password: password)
        defer {
            client.shutdown()
            isTesting = false
        }
        do {
            try await client.ensureConnected()
            testSucceeded = true
            testMessage = "Connected."
        } catch {
            testSucceeded = false
            testMessage = errorText(error)
        }
    }

    private func save() {
        guard let server = draftServer else { return }
        model.saveServer(server, password: password)
        dismiss()
    }
}
