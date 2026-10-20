import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct ShelfOperationsTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("FalletOperationsTests-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let first = root.appendingPathComponent("first.txt")
        let secondFolder = root.appendingPathComponent("other")
        try manager.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let second = secondFolder.appendingPathComponent("first.txt")
        try Data("alpha".utf8).write(to: first)
        try Data("beta".utf8).write(to: second)
        let archive = root.appendingPathComponent("items.zip")
        try ShelfOperations.createZIP(from: [first, second], at: archive)
        let extracted = root.appendingPathComponent("extracted")
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", archive.path, extracted.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0,
              try String(contentsOf: extracted.appendingPathComponent("first.txt"), encoding: .utf8) == "alpha",
              try String(contentsOf: extracted.appendingPathComponent("first 2.txt"), encoding: .utf8) == "beta" else {
            fatalError("ZIP must retain both files with distinct names and contents")
        }

        let sourceImage = root.appendingPathComponent("source.png")
        let bitmap = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8,
                               bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let sourceWriter = CGImageDestinationCreateWithURL(sourceImage as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(sourceWriter, bitmap.makeImage()!, nil)
        guard CGImageDestinationFinalize(sourceWriter) else { fatalError("Could not create image fixture") }
        let resized = root.appendingPathComponent("resized.png")
        try ShelfOperations.resizeImage(at: sourceImage, toWidth: 80, saveTo: resized)
        let resizedSource = CGImageSourceCreateWithURL(resized as CFURL, nil)!
        let dimensions = CGImageSourceCopyPropertiesAtIndex(resizedSource, 0, nil)! as NSDictionary
        guard dimensions[kCGImagePropertyPixelWidth] as? Int == 80,
              dimensions[kCGImagePropertyPixelHeight] as? Int == 40 else {
            fatalError("Image resize should keep aspect ratio")
        }

        print("Shelf operations tests passed")
    }
}
