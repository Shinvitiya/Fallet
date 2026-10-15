import AppKit

// Renders the real shelf view from isolated file-system fixtures.
// Run from the repository root with -D FALLET_CAPTURE and all app view sources.
@main
struct PersistenceDemoCapture {
    static func main() throws {
        _ = NSApplication.shared
        let files = FileManager.default
        if let resources = Bundle.main.resourceURL {
            let icon = resources.appendingPathComponent("FalletIcon.png")
            if !files.fileExists(atPath: icon.path) {
                try? files.copyItem(at: URL(fileURLWithPath: "Resources/FalletIcon.png"), to: icon)
            }
        }
        let root = files.temporaryDirectory.appendingPathComponent("FalletDemo-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let output = URL(fileURLWithPath: "docs/demo")
        let storage = root.appendingPathComponent("shelf.json")
        let original = root.appendingPathComponent("report.txt")
        try Data("Demo file".utf8).write(to: original)

        do {
            let store = ShelfStore(storageURL: storage)
            store.add([original])
            try capture(store, to: output.appendingPathComponent("04-source-ready.png"))
        }

        let movedFolder = root.appendingPathComponent("Renamed folder")
        try files.createDirectory(at: movedFolder, withIntermediateDirectories: true)
        let moved = movedFolder.appendingPathComponent("renamed-report.txt")
        try files.moveItem(at: original, to: moved)
        do {
            let reopened = ShelfStore(storageURL: storage)
            guard reopened.entries.first?.path == moved.path else {
                fatalError("Bookmark did not follow the moved file")
            }
            try capture(reopened, to: output.appendingPathComponent("05-source-renamed.png"))
        }

        try files.removeItem(at: moved)
        do {
            let missing = ShelfStore(storageURL: storage)
            try capture(missing, to: output.appendingPathComponent("06-source-missing.png"))
        }

        var external = ShelfEntry(url: root)
        external.path = "/Volumes/Fallet-Demo-Disconnected/report.txt"
        external.bookmarkData = nil
        external.volumeUUID = nil
        external.volumePath = "/Volumes/Fallet-Demo-Disconnected"
        try JSONEncoder().encode([external]).write(to: storage)
        let offline = ShelfStore(storageURL: storage)
        try capture(offline, to: output.appendingPathComponent("07-drive-disconnected.png"))
        print("Captured isolated shelf states in \(output.path)")
    }

    private static func capture(_ store: ShelfStore, to url: URL) throws {
        let view = ShelfView(store: store)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = view
        window.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.17, alpha: 1)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fatalError("Could not allocate screenshot")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not encode screenshot")
        }
        try png.write(to: url)
    }
}
