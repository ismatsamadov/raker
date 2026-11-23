// From the repository root:
// swiftc Packages/RakerKit/Sources/DesignSystem/RakerIcon.swift Scripts/render-icon.swift -o /tmp/raker-icon
// /tmp/raker-icon /tmp/Raker.iconset && iconutil -c icns /tmp/Raker.iconset -o Design/Raker.icns
import AppKit
import SwiftUI

@main
struct RenderIcon {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: raker-icon <folder>.iconset\n".utf8))
            exit(64)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let size = CGFloat(points * scale)
                // An app icon's body fills 824 points of macOS's 1024-point grid; the rest is
                // margin, and room for its shadow. RakerIcon's tile fills 90% of its frame, so
                // the frame shrinks to put the tile on that grid.
                let artwork = size * 824 / 1024 / 0.9
                let renderer = ImageRenderer(content: RakerIcon().frame(width: artwork, height: artwork).frame(width: size, height: size))
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let suffix = scale == 2 ? "@2x" : ""
                try png.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
    }
}
