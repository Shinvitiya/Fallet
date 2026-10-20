import AppKit

@main
struct GuideSlideCapture {
    static func main() throws {
        _ = NSApplication.shared
        let window = GuideWindow()
        guard let view = window.contentView as? GuideView else { fatalError("Guide view missing") }
        let names = ["01-collect", "02-split-a-batch", "03-move-together", "04-stay-in-flow"]
        let directory = URL(fileURLWithPath: "docs/guide")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, name) in names.enumerated() {
            view.setPageForCapture(index)
            view.layoutSubtreeIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: Int(view.bounds.width * 2),
                                                pixelsHigh: Int(view.bounds.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0) else {
                fatalError("Could not allocate guide image")
            }
            bitmap.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Could not encode guide image")
            }
            try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        }
        print("Updated all four guide images")
    }
}
