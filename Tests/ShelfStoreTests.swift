import Foundation

@main
struct ShelfStoreTests {
    static func main() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("FalletShelfTests-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }

        let original = root.appendingPathComponent("original.txt")
        let renamed = root.appendingPathComponent("renamed.txt")
        let storage = root.appendingPathComponent("shelf.json")
        try Data("example".utf8).write(to: original)

        let first = ShelfStore(storageURL: storage)
        first.add([original])
        guard first.entries.count == 1, first.entries[0].bookmarkData != nil else {
            fatalError("Adding a file did not save a bookmark")
        }
        try files.moveItem(at: original, to: renamed)

        let reopened = ShelfStore(storageURL: storage)
        guard reopened.entries.count == 1, reopened.entries[0].path == renamed.path,
              reopened.status(for: reopened.entries[0]) == .ready else {
            fatalError("A renamed file was not found after relaunch")
        }

        let otherFolder = root.appendingPathComponent("Other Folder")
        try files.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        let moved = otherFolder.appendingPathComponent("renamed.txt")
        try files.moveItem(at: renamed, to: moved)
        let movedReopened = ShelfStore(storageURL: storage)
        guard movedReopened.entries.count == 1, movedReopened.entries[0].path == moved.path,
              movedReopened.status(for: movedReopened.entries[0]) == .ready else {
            fatalError("A file moved to another folder was not found after relaunch")
        }

        try files.removeItem(at: moved)
        let missing = ShelfStore(storageURL: storage)
        guard missing.entries.count == 1, missing.status(for: missing.entries[0]) == .missing else {
            fatalError("A missing source should remain on the shelf")
        }

        let replacement = root.appendingPathComponent("replacement.txt")
        try Data("replacement".utf8).write(to: replacement)
        guard missing.relink(missing.entries[0].id, to: replacement),
              missing.status(for: missing.entries[0]) == .ready else {
            fatalError("Locate did not restore the saved entry")
        }
        let relinked = ShelfStore(storageURL: storage)
        guard relinked.entries[0].path == replacement.path else {
            fatalError("Relink did not survive relaunch")
        }

        var offlineEntry = ShelfEntry(url: replacement)
        offlineEntry.path = "/Volumes/Fallet-Test-Not-Mounted/example.txt"
        offlineEntry.bookmarkData = nil
        offlineEntry.volumeUUID = nil
        offlineEntry.volumePath = "/Volumes/Fallet-Test-Not-Mounted"
        try JSONEncoder().encode([offlineEntry]).write(to: storage)
        let offline = ShelfStore(storageURL: storage)
        guard offline.entries.count == 1,
              offline.status(for: offline.entries[0]) == .volumeUnavailable else {
            fatalError("An unmounted drive should be distinct from a deleted file")
        }

        let legacy = "[{\"id\":\"\(UUID().uuidString)\",\"path\":\"\(original.path)\"}]"
        try Data(legacy.utf8).write(to: storage)
        let imported = ShelfStore(storageURL: storage)
        guard imported.entries.count == 1, imported.status(for: imported.entries[0]) == .missing else {
            fatalError("Old path-only shelf entries should remain recoverable")
        }
        print("Shelf persistence tests passed")
    }
}
