import AppKit
import SwiftUI
import DelugeRemoteCore

struct TorrentDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var maxDownload = -1
    @State private var maxUpload = -1
    @State private var maxConnections = -1
    @State private var movePath = ""
    @State private var limitsHash: String?

    var body: some View {
        if let hash = model.selectedHashes.first,
           let torrent = model.torrents.first(where: { $0.id == hash }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(torrent)
                    stats(torrent)
                    if let detail = model.detail, detail.hash == hash {
                        notices(detail)
                        limits(detail)
                        storage(detail)
                        files(detail)
                    } else {
                        ProgressView("Loading details…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }
                }
                .padding(16)
                .onChange(of: model.detail?.hash) { _, _ in
                    syncLimits()
                }
                .onAppear { syncLimits() }
            }
        } else {
            ContentUnavailableView("Select a Torrent", systemImage: "arrow.down.circle")
        }
    }

    private func header(_ torrent: Torrent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: stateSymbol(torrent))
                    .foregroundStyle(stateColor(torrent))
                Text(torrent.displayState)
                    .font(.headline)
                    .foregroundStyle(stateColor(torrent))
                Spacer()
            }
            Text(torrent.name)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            ProgressView(value: min(max(torrent.progress, 0), 100), total: 100)
            HStack {
                Text(percentString(torrent.progress))
                Spacer()
                Text(etaString(seconds: torrent.eta, paused: torrent.paused, progress: torrent.progress))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack {
                Button(torrent.paused || torrent.state == "Paused" ? "Resume" : "Pause") {
                    Task {
                        if torrent.paused || torrent.state == "Paused" {
                            await model.resumeSelected()
                        } else {
                            await model.pauseSelected()
                        }
                    }
                }
                Button("Recheck") { Task { await model.recheckSelected() } }
                Button("Remove", role: .destructive) { model.isPresentingRemove = true }
            }
            .controlSize(.small)
        }
    }

    private func stats(_ torrent: Torrent) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            stat("Download", torrent.downloadRate.byteRateString)
            stat("Upload", torrent.uploadRate.byteRateString)
            stat("Size", torrent.totalSize.byteString)
            stat("Ratio", ratioString(torrent.ratio))
            stat("Downloaded", torrent.downloaded.byteString)
            stat("Uploaded", torrent.uploaded.byteString)
            if let detail = model.detail, detail.hash == torrent.hash {
                stat("Seeds", countText(detail.seeds))
                stat("Peers", countText(detail.peers))
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func notices(_ detail: TorrentDetail) -> some View {
        if !detail.message.isEmpty {
            Text(detail.message)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        if !detail.trackerStatus.isEmpty {
            labeledBlock("Tracker", detail.trackerStatus)
        }
        if !detail.trackerHost.isEmpty {
            labeledBlock("Tracker host", detail.trackerHost)
        }
        if !detail.label.isEmpty {
            labeledBlock("Label", detail.label)
        }
        if !detail.comment.isEmpty {
            labeledBlock("Comment", detail.comment)
        }
        labeledBlock("Hash", detail.hash)
        Button("Copy Hash") { copy(detail.hash) }
            .controlSize(.small)
    }

    private func labeledBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func limits(_ detail: TorrentDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Limits")
                .font(.headline)
            Text("-1 means unlimited. Speeds are KiB/s.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Max download", value: $maxDownload, format: .number)
            TextField("Max upload", value: $maxUpload, format: .number)
            TextField("Max connections", value: $maxConnections, format: .number)
            Button("Save Limits") {
                Task {
                    await model.setLimits(downloadKiB: maxDownload, uploadKiB: maxUpload, connections: maxConnections)
                }
            }
            .disabled(limitsHash != detail.hash)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func storage(_ detail: TorrentDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage")
                .font(.headline)
            Text(detail.savePath)
                .font(.callout)
                .textSelection(.enabled)
            TextField("New location", text: $movePath)
                .textFieldStyle(.roundedBorder)
            Button("Move Files") {
                Task { await model.moveSelected(path: movePath) }
            }
            .disabled(movePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func files(_ detail: TorrentDetail) -> some View {
        if !detail.files.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Files")
                    .font(.headline)
                ForEach(detail.files) { file in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(file.path)
                                .font(.callout)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Menu(file.priorityName) {
                                Button("Skip") { Task { await model.setFilePriority(index: file.index, priority: 0) } }
                                Button("Normal") { Task { await model.setFilePriority(index: file.index, priority: 1) } }
                                Button("High") { Task { await model.setFilePriority(index: file.index, priority: 5) } }
                                Button("Highest") { Task { await model.setFilePriority(index: file.index, priority: 7) } }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        ProgressView(value: min(max(file.progress, 0), 100), total: 100)
                        Text("\(file.size.byteString) · \(percentString(file.progress))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func syncLimits() {
        guard let detail = model.detail else { return }
        guard limitsHash != detail.hash else { return }
        limitsHash = detail.hash
        maxDownload = detail.maxDownloadSpeed
        maxUpload = detail.maxUploadSpeed
        maxConnections = detail.maxConnections
        movePath = detail.savePath
    }

    private func countText(_ value: Int) -> String {
        value < 0 ? "—" : String(value)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
