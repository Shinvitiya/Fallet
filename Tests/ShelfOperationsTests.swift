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
        let store = ShelfStore(storageURL: root.appendingPathComponent("shelf/shelf.json"))
        let archive = try store.makeTemporaryArchiveURL(for: [first, second])
        try ShelfOperations.createZIP(from: [first, second], at: archive)
        guard store.addTemporaryArchive(archive) != nil,
              store.entries.count == 1,
              store.entries[0].kind == .archive,
              store.status(for: store.entries[0]) == .ready else {
            fatalError("Create ZIP should add a ready temporary archive to the shelf")
        }
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
        let exported = root.appendingPathComponent("items.zip")
        try manager.moveItem(at: archive, to: exported)
        store.removePaths([archive.path])
        guard manager.fileExists(atPath: exported.path), store.entries.isEmpty else {
            fatalError("Moving the ZIP out of temporary storage should keep the export")
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
        let imageBytes = try Data(contentsOf: sourceImage)
        guard store.addImage(imageBytes), let collectedImage = store.entries.last, collectedImage.kind == .image else {
            fatalError("A dropped website image should become a shelf image")
        }
        let imageArchive = try store.makeTemporaryArchiveURL(for: [collectedImage.url])
        try ShelfOperations.createZIP(from: [collectedImage.url], at: imageArchive)
        guard store.addTemporaryArchive(imageArchive) != nil else {
            fatalError("Website images should be ZIP-ready from the shelf")
        }
        let imageExtracted = root.appendingPathComponent("image-extracted")
        let imageUnzip = Process()
        imageUnzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        imageUnzip.arguments = ["-x", "-k", imageArchive.path, imageExtracted.path]
        try imageUnzip.run()
        imageUnzip.waitUntilExit()
        guard imageUnzip.terminationStatus == 0,
              try Data(contentsOf: imageExtracted.appendingPathComponent(collectedImage.url.lastPathComponent)) == imageBytes else {
            fatalError("The ZIP should contain the full website image")
        }
        store.clear()
        guard !manager.fileExists(atPath: imageArchive.path),
              !manager.fileExists(atPath: collectedImage.path),
              manager.fileExists(atPath: sourceImage.path) else {
            fatalError("Clear should discard managed image and ZIP copies, not the original")
        }
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
