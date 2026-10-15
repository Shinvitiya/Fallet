import Foundation

enum ShelfEntryStatus: Equatable {
    case ready
    case missing
    case volumeUnavailable
}

struct ShelfEntry: Codable, Equatable {
    let id: UUID
    var path: String
    var bookmarkData: Data?
    var volumeUUID: String?
    var volumePath: String?

    init(url: URL) {
        id = UUID()
        path = url.standardizedFileURL.path
        updateReference(to: url)
    }

    var url: URL { URL(fileURLWithPath: path) }

    mutating func updateReference(to url: URL) {
        let standardized = url.standardizedFileURL
        path = standardized.path
        bookmarkData = try? standardized.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let values = try? standardized.resourceValues(forKeys: [.volumeUUIDStringKey])
        volumeUUID = values?.volumeUUIDString
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        volumePath = parts.count >= 2 && parts[0] == "Volumes" ? "/Volumes/\(parts[1])" : nil
    }
}

final class ShelfStore {
    private(set) var entries: [ShelfEntry] = []
    var onChange: (() -> Void)?

    private let storageURL: URL
    private var statusSnapshot: [UUID: ShelfEntryStatus] = [:]

    init(storageURL customStorageURL: URL? = nil, legacyURL customLegacyURL: URL? = nil) {
        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageURL = customStorageURL ?? supportRoot.appendingPathComponent("Fallet/shelf.json")
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        let legacyURL = customLegacyURL ?? (customStorageURL == nil
            ? supportRoot.appendingPathComponent("DropShelf/shelf.json") : nil)
        let currentData = try? Data(contentsOf: storageURL)
        let data = currentData ?? legacyURL.flatMap { try? Data(contentsOf: $0) }
        if let data, let saved = try? JSONDecoder().decode([ShelfEntry].self, from: data) {
            entries = saved
        }
        statusSnapshot = snapshot()
        refresh()
        if currentData == nil && data != nil { changed() }
    }

    func status(for entry: ShelfEntry) -> ShelfEntryStatus {
        if FileManager.default.fileExists(atPath: entry.path) { return .ready }
        let savedVolumePath = entry.volumePath ?? Self.inferredVolumePath(for: entry.path)
        guard let savedVolumePath, savedVolumePath != "/" else { return .missing }

        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []
        ) ?? []
        let mounted = volumes.contains { volume in
            if let uuid = entry.volumeUUID {
                return (try? volume.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString == uuid
            }
            return volume.standardizedFileURL.path == savedVolumePath
        }
        return mounted ? .missing : .volumeUnavailable
    }

    func refresh() {
        let previous = entries
        for index in entries.indices {
            var entry = entries[index]
            if let bookmarkData = entry.bookmarkData {
                var isStale = false
                if let resolved = try? URL(resolvingBookmarkData: bookmarkData,
                                           options: [.withoutUI, .withoutMounting],
                                           relativeTo: nil, bookmarkDataIsStale: &isStale),
                   FileManager.default.fileExists(atPath: resolved.path),
                   (resolved.standardizedFileURL.path != entry.path || isStale) {
                    entry.updateReference(to: resolved)
                }
            }
            if entry.bookmarkData == nil && FileManager.default.fileExists(atPath: entry.path) {
                entry.updateReference(to: entry.url)
            }
            entries[index] = entry
        }
        let currentStatuses = snapshot()
        if entries != previous { changed() }
        else if currentStatuses != statusSnapshot {
            statusSnapshot = currentStatuses
            onChange?()
        }
    }

    func add(_ urls: [URL]) {
        refresh()
        var seen = Set(entries.map(\.path))
        let additions = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
            .map { ShelfEntry(url: $0) }
            .filter { seen.insert($0.path).inserted }
        guard !additions.isEmpty else { return }
        entries.append(contentsOf: additions)
        changed()
    }

    @discardableResult
    func relink(_ id: UUID, to url: URL) -> Bool {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path),
              let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        let path = url.standardizedFileURL.path
        guard !entries.contains(where: { $0.id != id && $0.path == path }) else { return false }
        entries[index].updateReference(to: url)
        changed()
        return true
    }

    func remove(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        changed()
    }

    func removePaths(_ paths: Set<String>) {
        entries.removeAll { paths.contains($0.path) }
        changed()
    }

    func clear() {
        entries.removeAll()
        changed()
    }

    private func snapshot() -> [UUID: ShelfEntryStatus] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, status(for: $0)) })
    }

    private func changed() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: storageURL, options: .atomic)
        }
        statusSnapshot = snapshot()
        onChange?()
    }

    private static func inferredVolumePath(for path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        return "/Volumes/\(parts[1])"
    }
}
