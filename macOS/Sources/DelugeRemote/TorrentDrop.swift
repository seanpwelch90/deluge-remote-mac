import AppKit
import UniformTypeIdentifiers
import DelugeRemoteCore

enum TorrentDrop {
    static let contentTypes: [UTType] = [.fileURL, .url, .plainText, .text]

    static func canAccept(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { provider in
            contentTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
    }

    static func beginImport(_ providers: [NSItemProvider], into model: AppModel) {
        let matched = providers.filter { provider in
            contentTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
        guard !matched.isEmpty else { return }
        Task {
            var payloads: [TorrentPayload] = []
            for provider in matched {
                if let payload = await load(provider) {
                    payloads.append(payload)
                }
            }
            await model.receive(payloads)
        }
    }

    private static func load(_ provider: NSItemProvider) async -> TorrentPayload? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let payload = await loadFile(provider) {
            return payload
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let payload = await loadLink(provider, type: .url) {
            return payload
        }
        if let text = await loadText(provider), case .magnet(let magnet) = TorrentImport.parse(text: text) {
            return .magnet(magnet)
        }
        return nil
    }

    private static func loadFile(_ provider: NSItemProvider) async -> TorrentPayload? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = url(from: item) else {
                    continuation.resume(returning: nil)
                    return
                }
                let accessing = url.startAccessingSecurityScopedResource()
                let payload = TorrentPayload.file(at: url) ?? magnetPayload(url)
                if accessing { url.stopAccessingSecurityScopedResource() }
                continuation.resume(returning: payload)
            }
        }
    }

    private static func loadLink(_ provider: NSItemProvider, type: UTType) async -> TorrentPayload? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                guard let url = url(from: item) else {
                    continuation.resume(returning: nil)
                    return
                }
                if url.isFileURL {
                    let accessing = url.startAccessingSecurityScopedResource()
                    let payload = TorrentPayload.file(at: url)
                    if accessing { url.stopAccessingSecurityScopedResource() }
                    continuation.resume(returning: payload ?? magnetPayload(url))
                    return
                }
                continuation.resume(returning: magnetPayload(url))
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        let type = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ? UTType.plainText : UTType.text
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func magnetPayload(_ url: URL) -> TorrentPayload? {
        guard case .magnet(let magnet) = TorrentImport.parse(url: url) else { return nil }
        return .magnet(magnet)
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }
}
