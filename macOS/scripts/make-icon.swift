import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: make-icon.swift Icon.icon output.png\n", stderr)
    exit(1)
}

let iconURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let iconJSON = try JSONDecoder().decode(IconDocument.self, from: Data(contentsOf: iconURL.appendingPathComponent("icon.json")))
guard let imageName = iconJSON.groups.first?.layers.first?.imageName else {
    fputs("Icon document has no image layer.\n", stderr)
    exit(1)
}
let artworkURL = iconURL.appendingPathComponent("Assets").appendingPathComponent(imageName)
guard let artwork = NSImage(contentsOf: artworkURL) else {
    fputs("Could not read \(artworkURL.path)\n", stderr)
    exit(1)
}

let pixels = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create icon bitmap.\n", stderr)
    exit(1)
}
rep.size = NSSize(width: pixels, height: pixels)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
let fill = iconJSON.fill.color
NSGradient(colors: [fill.lighter(), fill])?.draw(in: bounds, angle: 90)

let scale = iconJSON.groups.first?.layers.first?.position.scale ?? 0.6
let side = CGFloat(pixels) * scale
let frame = NSRect(x: (CGFloat(pixels) - side) / 2, y: (CGFloat(pixels) - side) / 2, width: side, height: side)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
NSGraphicsContext.current?.saveGraphicsState()
shadow.set()
artwork.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.current?.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not encode icon.\n", stderr)
    exit(1)
}
try png.write(to: outputURL)

struct IconDocument: Decodable {
    var fill: Fill
    var groups: [Group]

    struct Fill: Decodable {
        var automaticGradient: String

        var color: NSColor {
            let parts = automaticGradient.split(separator: ":").last?.split(separator: ",") ?? []
            let values = parts.compactMap { Double($0) }
            guard values.count >= 3 else { return NSColor(srgbRed: 0, green: 0.53, blue: 1, alpha: 1) }
            return NSColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: values.count > 3 ? values[3] : 1)
        }

        enum CodingKeys: String, CodingKey {
            case automaticGradient = "automatic-gradient"
        }
    }

    struct Group: Decodable {
        var layers: [Layer]
    }

    struct Layer: Decodable {
        var imageName: String
        var position: Position

        enum CodingKeys: String, CodingKey {
            case imageName = "image-name"
            case position
        }
    }

    struct Position: Decodable {
        var scale: CGFloat
    }
}

extension NSColor {
    func lighter() -> NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return self }
        return NSColor(
            srgbRed: min(1, rgb.redComponent + 0.18),
            green: min(1, rgb.greenComponent + 0.12),
            blue: min(1, rgb.blueComponent),
            alpha: rgb.alphaComponent
        )
    }
}
