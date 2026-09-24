import Foundation

public enum TorrentImport: Equatable, Sendable {
    case magnet(String)
    case torrentFile(URL)

    public static func parse(url: URL) -> TorrentImport? {
        if url.scheme?.caseInsensitiveCompare("magnet") == .orderedSame {
            let magnet = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard magnet.lowercased().hasPrefix("magnet:") else { return nil }
            return .magnet(magnet)
        }
        if url.isFileURL, url.pathExtension.caseInsensitiveCompare("torrent") == .orderedSame {
            return .torrentFile(url)
        }
        return nil
    }

    public static func parse(text: String) -> TorrentImport? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("magnet:") else { return nil }
        return .magnet(trimmed)
    }
}
