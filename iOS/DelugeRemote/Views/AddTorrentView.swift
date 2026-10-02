import SwiftUI
import UniformTypeIdentifiers
import DelugeRemoteCore

struct AddTorrentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var source: Source = .magnet
    @State private var magnet = ""
    @State private var remoteURL = ""
    @State private var fileName = ""
    @State private var fileData: Data?
    @State private var isImporting = false
    @State private var downloadLocation = ""
    @State private var addPaused = false
    @State private var baseOptions = AddTorrentOptions.fallback
    @State private var message: String?
    @State private var failed = false
    @State private var isSubmitting = false

    private var torrentType: UTType { UTType(filenameExtension: "torrent") ?? .data }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source", selection: $source) {
                    Text("Magnet").tag(Source.magnet)
                    Text("File").tag(Source.file)
                    Text("URL").tag(Source.url)
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                switch source {
                case .magnet:
                    TextField("Magnet link", text: $magnet, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                case .file:
                    Button {
                        isImporting = true
                    } label: {
                        HStack {
                            Text(fileName.isEmpty ? "Choose Torrent File" : fileName)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "doc")
                        }
                    }
                case .url:
                    TextField("Torrent URL", text: $remoteURL, prompt: Text("https://example.com/file.torrent"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                TextField("Download location", text: $downloadLocation, prompt: Text("Server default"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Add paused", isOn: $addPaused)

                if let message {
                    Text(message)
                        .foregroundStyle(failed ? Color.red : Color.green)
                }
            }
            .navigationTitle("Add Torrent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await submit() } }
                        .disabled(isSubmitting || !canSubmit)
                }
            }
            .task { await loadDefaults() }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [torrentType]) { result in
                switch result {
                case .success(let url):
                    readFile(url)
                case .failure(let error):
                    failed = true
                    message = error.localizedDescription
                }
            }
        }
    }

    private var canSubmit: Bool {
        switch source {
        case .magnet:
            return magnet.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("magnet:")
        case .file:
            return fileData != nil
        case .url:
            return remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http")
        }
    }

    private func loadDefaults() async {
        let options = await model.loadDefaultOptions()
        baseOptions = options
        if downloadLocation.isEmpty { downloadLocation = options.downloadLocation }
        addPaused = options.addPaused
    }

    private func options() -> AddTorrentOptions {
        var options = baseOptions
        options.downloadLocation = downloadLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        options.addPaused = addPaused
        return options
    }

    private func submit() async {
        isSubmitting = true
        message = nil
        do {
            switch source {
            case .magnet:
                try await model.addMagnet(magnet.trimmingCharacters(in: .whitespacesAndNewlines), options: options())
            case .url:
                try await model.addURL(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines), options: options())
            case .file:
                guard let fileData else { return }
                let name = fileName.isEmpty ? "upload.torrent" : fileName
                try await model.addFile(name: name, data: fileData, options: options())
            }
            dismiss()
        } catch {
            failed = true
            message = errorText(error)
            isSubmitting = false
        }
    }

    private func readFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            fileData = try Data(contentsOf: url)
            fileName = url.lastPathComponent
            failed = false
            message = nil
        } catch {
            failed = true
            message = error.localizedDescription
        }
    }
}

private enum Source {
    case magnet
    case file
    case url
}
