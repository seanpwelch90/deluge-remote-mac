import Foundation

public extension Double {
    var byteRateString: String {
        if self <= 0 { return "0 KB/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(self.rounded()), countStyle: .file) + "/s"
    }
}

public extension Int64 {
    var byteString: String {
        if self <= 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

public func etaString(seconds: Double, paused: Bool, progress: Double) -> String {
    if paused { return "Paused" }
    if progress >= 100 { return "Done" }
    if seconds <= 0 { return "—" }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: seconds) ?? "—"
}

public func ratioString(_ ratio: Double) -> String {
    String(format: "%.2f", ratio)
}

public func percentString(_ progress: Double) -> String {
    String(format: "%.1f%%", progress)
}
