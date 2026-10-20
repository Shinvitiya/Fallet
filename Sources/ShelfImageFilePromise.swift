import AppKit
import UniformTypeIdentifiers

/// Exports an image captured from the clipboard without moving its shelf backing file.
final class ShelfImageFilePromise: NSObject, NSFilePromiseProviderDelegate {
    private static var active: [UUID: ShelfImageFilePromise] = [:]

    let id = UUID()
    private let sourceURL: URL
    private let onWritten: (URL) -> Void
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Fallet image export"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(sourceURL: URL, onWritten: @escaping (URL) -> Void) {
        self.sourceURL = sourceURL
        self.onWritten = onWritten
    }

    func makeProvider() -> NSFilePromiseProvider {
        let fileType = UTType.png.conforms(to: .data) ? UTType.png.identifier : UTType.data.identifier
        let provider = NSFilePromiseProvider(fileType: fileType, delegate: self)
        Self.active[id] = self // NSFilePromiseProvider keeps only a weak delegate.
        return provider
    }

    static func cancel(_ ids: [UUID]) {
        for id in ids { active.removeValue(forKey: id) }
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        sourceURL.lastPathComponent
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        do {
            try FileManager.default.copyItem(at: sourceURL, to: url)
            completionHandler(nil)
            let finish = {
                self.onWritten(self.sourceURL)
                Self.active.removeValue(forKey: self.id)
            }
            if Thread.isMainThread { finish() }
            else { DispatchQueue.main.async(execute: finish) }
        } catch {
            completionHandler(error)
            DispatchQueue.main.async { Self.active.removeValue(forKey: self.id) }
        }
    }
}
