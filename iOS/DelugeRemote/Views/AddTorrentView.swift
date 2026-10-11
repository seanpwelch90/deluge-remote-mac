import SwiftUI
import UniformTypeIdentifiers
import DelugeRemoteCore

struct AddTorrentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .choose
    @State private var source: Source = .magnet
    @State private var magnet = ""
    @State private var remoteURL = ""
    @State private var fileName = ""
    @State private var fileData: Data?
    @State private var isImporting = false
    @State private var options = AddTorrentOptions.fallback
    @State private var preview: TorrentPreview?
    @State private var message: String?
    @State private var failed = false
    @State private var isWorking = false

    private var torrentType: UTType { UTType(filenameExtension: "torrent") ?? .data }

    var body: some View {
        NavigationStack {
            Form {
                if step == .choose {
                    sourceSection
                } else {
                    reviewSections
                }
                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(failed ? Color.red : Color.green)
                    }
                }
            }
            .navigationTitle(step == .choose ? "Add Torrent" : "Torrent Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .review ? "Back" : "Cancel") { goBackOrCancel() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(step == .review ? "Add" : "Continue") {
                            Task { await primaryAction() }
                        }
                        .disabled(!canContinue)
                    }
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

    private var sourceSection: some View {
        Section("Source") {
            Picker("Source", selection: $source) {
                Text("Magnet").tag(Source.magnet)
                Text("File").tag(Source.file)
                Text("URL").tag(Source.url)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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
        }
    }

    @ViewBuilder
    private var reviewSections: some View {
        Section("Torrent Info") {
            if let preview {
                Text(preview.name)
                    .textSelection(.enabled)
                Text(preview.hash)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Reading torrent…")
            }
        }
        Section {
            TextField("Max download speed (KiB/s)", value: $options.maxDownloadSpeed, format: .number)
                .keyboardType(.numbersAndPunctuation)
            TextField("Max upload speed (KiB/s)", value: $options.maxUploadSpeed, format: .number)
                .keyboardType(.numbersAndPunctuation)
            TextField("Max connections", value: $options.maxConnections, format: .number)
                .keyboardType(.numbersAndPunctuation)
            TextField("Max upload slots", value: $options.maxUploadSlots, format: .number)
                .keyboardType(.numbersAndPunctuation)
        } header: {
            Text("Bandwidth")
        } footer: {
            Text("-1 means unlimited.")
        }
        Section("Queue") {
            TextField("Download location", text: $options.downloadLocation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Toggle("Move completed", isOn: $options.moveCompleted)
            if options.moveCompleted {
                TextField("Path", text: $options.moveCompletedPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Toggle("Add paused", isOn: $options.addPaused)
            Toggle("Compact allocation", isOn: $options.compactAllocation)
            Toggle("Prioritize first/last pieces", isOn: $options.prioritizeFirstLastPieces)
        }
    }

    private var canContinue: Bool {
        if step == .review {
            let location = options.downloadLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            let movePath = options.moveCompletedPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return preview != nil && !location.isEmpty && (!options.moveCompleted || !movePath.isEmpty)
        }
        return canChooseSource
    }

    private var canChooseSource: Bool {
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
        options = await model.loadDefaultOptions()
        if let payload = model.stagedAdds.first {
            apply(payload)
            await previewCurrent()
        }
    }

    private func apply(_ payload: TorrentPayload) {
        switch payload {
        case .magnet(let value):
            source = .magnet
            magnet = value
        case .file(let name, let data):
            source = .file
            fileName = name
            fileData = data
        }
    }

    private func primaryAction() async {
        if step == .choose {
            await previewCurrent()
        } else {
            await submit()
        }
    }

    private func previewCurrent() async {
        isWorking = true
        message = nil
        do {
            switch source {
            case .magnet:
                preview = try await model.previewMagnet(magnet.trimmingCharacters(in: .whitespacesAndNewlines))
            case .url:
                preview = try await model.previewURL(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines))
            case .file:
                guard let fileData else {
                    isWorking = false
                    return
                }
                let name = fileName.isEmpty ? "upload.torrent" : fileName
                preview = try await model.previewFile(name: name, data: fileData)
            }
            failed = false
            step = .review
            isWorking = false
        } catch {
            failed = true
            message = errorText(error)
            isWorking = false
        }
    }

    private func submit() async {
        isWorking = true
        message = nil
        var sending = options
        sending.downloadLocation = options.downloadLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        sending.moveCompletedPath = options.moveCompletedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch source {
            case .magnet:
                try await model.addMagnet(magnet.trimmingCharacters(in: .whitespacesAndNewlines), options: sending)
            case .url:
                try await model.addURL(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines), options: sending)
            case .file:
                guard let fileData else {
                    isWorking = false
                    return
                }
                let name = fileName.isEmpty ? "upload.torrent" : fileName
                try await model.addFile(name: name, data: fileData, options: sending)
            }
            model.completeAdd()
        } catch {
            failed = true
            message = errorText(error)
            isWorking = false
        }
    }

    private func goBackOrCancel() {
        if step == .review {
            step = .choose
            preview = nil
            message = nil
            return
        }
        model.cancelAdd()
        dismiss()
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

private enum Step {
    case choose
    case review
}

private enum Source {
    case magnet
    case file
    case url
}
