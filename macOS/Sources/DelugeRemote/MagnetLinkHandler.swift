import AppKit
import CoreServices

enum MagnetLinkHandler {
    static var isCurrent: Bool {
        guard let sample = URL(string: "magnet:?xt=urn:btih:0"),
              let current = NSWorkspace.shared.urlForApplication(toOpen: sample) else {
            return false
        }
        return current.resolvingSymlinksInPath().path == Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    @discardableResult
    static func claim() -> Bool {
        guard !isCurrent, let bundleID = Bundle.main.bundleIdentifier else { return isCurrent }
        let status = LSSetDefaultHandlerForURLScheme("magnet" as CFString, bundleID as CFString)
        return status == 0 && isCurrent
    }
}
