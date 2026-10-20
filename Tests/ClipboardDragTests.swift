import AppKit
import UniformTypeIdentifiers

@main
struct ClipboardDragTests {
    static func main() throws {
        _ = NSApplication.shared
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("FalletClipboardDragTests-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let image = root.appendingPathComponent("copied-image.png")
        let destination = root.appendingPathComponent("saved-image.png")
        let bytes = Data("image contents".utf8)
        try bytes.write(to: image)
        var exportFinished = false
        let promise = ShelfImageFilePromise(sourceURL: image) { _ in exportFinished = true }
        let provider = promise.makeProvider()
        guard provider.fileType == (UTType.png.conforms(to: .data) ? UTType.png.identifier : UTType.data.identifier),
              promise.filePromiseProvider(provider, fileNameForType: provider.fileType) == image.lastPathComponent else {
            fatalError("Clipboard images must be offered to Finder as named PNG file promises")
        }
        var exportError: Error?
        promise.filePromiseProvider(provider, writePromiseTo: destination) { exportError = $0 }
        guard exportError == nil, try Data(contentsOf: destination) == bytes,
              try Data(contentsOf: image) == bytes else {
            fatalError("Export must copy the image without moving or deleting its shelf source")
        }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        guard exportFinished else { fatalError("Successful image export was not reported") }

        let store = ShelfStore(storageURL: root.appendingPathComponent("shelf.json"))
        let files = (0..<8).map { root.appendingPathComponent("file-\($0).txt") }
        for file in files { try Data("file".utf8).write(to: file) }
        store.add(files)
        store.addText("Earlier note")
        let shelf = ShelfView(store: store)
        store.onChange = { shelf.rebuild() }
        let initialScroll = shelf.subviews.compactMap { $0 as? NSScrollView }.first!
        guard initialScroll.contentView.bounds.origin.y > 0 else {
            fatalError("Fixture should start with a scrollable shelf positioned at its top")
        }
        store.addText("Newly pasted note")
        shelf.scrollToEntry(store.entries.last!.id)
        let finalScroll = shelf.subviews.compactMap { $0 as? NSScrollView }.first!
        guard finalScroll.contentView.bounds.origin.y == 0 else {
            fatalError("Pasting text should reveal the new item at the bottom of a grouped shelf")
        }
        print("Clipboard drag and reveal tests passed")
    }
}
