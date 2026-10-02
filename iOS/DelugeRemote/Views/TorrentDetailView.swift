import SwiftUI
import UIKit
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
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: stateSymbol(torrent))
                                .foregroundStyle(stateColor(torrent))
                            Text(torrent.displayState)
                                .font(.headline)
                                .foregroundStyle(stateColor(torrent))
                            Spacer()
                            if torrent.queue >= 0 {
                                Text("Queue \(queueLabel(torrent.queue))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
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
                    }
                    .padding(.vertical, 4)
                    Button(torrent.paused || torrent.state == "Paused" ? "Resume" : "Pause") {
                        Task {
                            if torrent.paused || torrent.state == "Paused" {
                                await model.resumeSelected()
                            } else {
                                await model.pauseSelected()
                            }
                        }
                    }
                    Button("Force Recheck") { Task { await model.recheckSelected() } }
                    Button("Remove", role: .destructive) { model.isPresentingRemove = true }
                }

                Section {
                    LabeledContent("Download", value: torrent.downloadRate.byteRateString)
                    LabeledContent("Upload", value: torrent.uploadRate.byteRateString)
                    LabeledContent("Size", value: torrent.totalSize.byteString)
                    LabeledContent("Downloaded", value: torrent.downloaded.byteString)
                    LabeledContent("Uploaded", value: torrent.uploaded.byteString)
                    LabeledContent("Ratio", value: ratioString(torrent.ratio))
                    if let detail = model.detail, detail.hash == hash {
                        LabeledContent("Seeds", value: countText(detail.seeds))
                        LabeledContent("Peers", value: countText(detail.peers))
                    }
                }

                Section("Queue") {
                    ForEach(QueueMove.allCases) { move in
                        Button(move.title, systemImage: move.symbol) {
                            Task { await model.moveSelectedInQueue(move) }
                        }
                    }
                }

                if let detail = model.detail, detail.hash == hash {
                    notices(detail)
                    limits(detail)
                    storage(detail)
                    files(detail)
                } else {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading details…")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: model.detail?.hash) { _, _ in
                syncLimits()
            }
            .onAppear { syncLimits() }
        } else {
            ContentUnavailableView("Select a Torrent", systemImage: "arrow.down.circle")
        }
    }

    @ViewBuilder
    private func notices(_ detail: TorrentDetail) -> some View {
        Section("Info") {
            if !detail.message.isEmpty {
                Text(detail.message)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if !detail.trackerStatus.isEmpty {
                labeled("Tracker", detail.trackerStatus)
            }
            if !detail.trackerHost.isEmpty {
                labeled("Tracker host", detail.trackerHost)
            }
            if !detail.label.isEmpty {
                labeled("Label", detail.label)
            }
            if !detail.comment.isEmpty {
                labeled("Comment", detail.comment)
            }
            labeled("Hash", detail.hash)
            Button("Copy Hash") { UIPasteboard.general.string = detail.hash }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func limits(_ detail: TorrentDetail) -> some View {
        Section {
            TextField("Max download", value: $maxDownload, format: .number)
                .keyboardType(.numbersAndPunctuation)
            TextField("Max upload", value: $maxUpload, format: .number)
                .keyboardType(.numbersAndPunctuation)
            TextField("Max connections", value: $maxConnections, format: .number)
                .keyboardType(.numbersAndPunctuation)
            Button("Save Limits") {
                Task {
                    await model.setLimits(downloadKiB: maxDownload, uploadKiB: maxUpload, connections: maxConnections)
                }
            }
            .disabled(limitsHash != detail.hash)
        } header: {
            Text("Limits")
        } footer: {
            Text("-1 means unlimited. Speeds are KiB/s.")
        }
    }

    private func storage(_ detail: TorrentDetail) -> some View {
        Section("Storage") {
            Text(detail.savePath)
                .textSelection(.enabled)
            TextField("New location", text: $movePath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Move Files") {
                Task { await model.moveSelected(path: movePath) }
            }
            .disabled(movePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func files(_ detail: TorrentDetail) -> some View {
        if !detail.files.isEmpty {
            Section("Files") {
                ForEach(detail.files) { file in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(file.path)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Menu(file.priorityName) {
                                Button("Skip") { Task { await model.setFilePriority(index: file.index, priority: 0) } }
                                Button("Normal") { Task { await model.setFilePriority(index: file.index, priority: 1) } }
                                Button("High") { Task { await model.setFilePriority(index: file.index, priority: 5) } }
                                Button("Highest") { Task { await model.setFilePriority(index: file.index, priority: 7) } }
                            }
                        }
                        ProgressView(value: min(max(file.progress, 0), 100), total: 100)
                        Text("\(file.size.byteString) · \(percentString(file.progress))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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
}
