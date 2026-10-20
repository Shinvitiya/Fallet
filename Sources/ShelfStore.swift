import Foundation

enum ShelfEntryStatus: Equatable {
    case ready
    case missing
    case volumeUnavailable
}

enum ShelfEntryKind: String, Codable {
    case file
    case image
    case archive
    case link
    case text
}

struct ShelfEntry: Codable, Equatable {
    let id: UUID
    var path: String
    var bookmarkData: Data?
    var volumeUUID: String?
    var volumePath: String?
    var kind: ShelfEntryKind
    var content: String?

    init(url: URL, kind: ShelfEntryKind = .file) {
        id = UUID()
        path = url.standardizedFileURL.path
        self.kind = kind
        content = nil
        updateReference(to: url)
    }

    init(content: String, kind: ShelfEntryKind) {
        id = UUID()
        path = ""
        bookmarkData = nil
        volumeUUID = nil
        volumePath = nil
        self.kind = kind
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, bookmarkData, volumeUUID, volumePath, kind, content
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        path = try values.decode(String.self, forKey: .path)
        bookmarkData = try values.decodeIfPresent(Data.self, forKey: .bookmarkData)
        volumeUUID = try values.decodeIfPresent(String.self, forKey: .volumeUUID)
        volumePath = try values.decodeIfPresent(String.self, forKey: .volumePath)
        kind = try values.decodeIfPresent(ShelfEntryKind.self, forKey: .kind) ?? .file
        content = try values.decodeIfPresent(String.self, forKey: .content)
    }

    var url: URL { URL(fileURLWithPath: path) }
    var isFileLike: Bool { kind == .file || kind == .image || kind == .archive }
    var title: String {
        switch kind {
        case .file, .image, .archive: return url.lastPathComponent
        case .link: return URL(string: content ?? "")?.host ?? content ?? "Link"
        case .text: return content?.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Text"
        }
    }

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
    private let imageDirectory: URL
    private let archiveDirectory: URL
    private var statusSnapshot: [UUID: ShelfEntryStatus] = [:]

    init(storageURL customStorageURL: URL? = nil, legacyURL customLegacyURL: URL? = nil) {
        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageURL = customStorageURL ?? supportRoot.appendingPathComponent("Fallet/shelf.json")
        imageDirectory = storageURL.deletingLastPathComponent().appendingPathComponent("Images")
        archiveDirectory = storageURL.deletingLastPathComponent().appendingPathComponent("Temporary ZIPs")
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)

        let legacyURL = customLegacyURL ?? (customStorageURL == nil
            ? supportRoot.appendingPathComponent("DropShelf/shelf.json") : nil)
        let currentData = try? Data(contentsOf: storageURL)
        let data = currentData ?? legacyURL.flatMap { try? Data(contentsOf: $0) }
        if let data, let saved = try? JSONDecoder().decode([ShelfEntry].self, from: data) {
            entries = saved
        }
        let hadTemporaryArchives = entries.contains { $0.kind == .archive }
        entries.removeAll { $0.kind == .archive }
        discardOrphanedArchives()
        statusSnapshot = snapshot()
        refresh()
        if hadTemporaryArchives || (currentData == nil && data != nil) { changed() }
    }

    func status(for entry: ShelfEntry) -> ShelfEntryStatus {
        if !entry.isFileLike { return .ready }
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
            guard entry.isFileLike && entry.kind != .archive else { continue }
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

    func makeTemporaryArchiveURL(for sources: [URL]) throws -> URL {
        guard !sources.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        let folder = archiveDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = sources.count == 1
            ? sources[0].deletingPathExtension().lastPathComponent + ".zip" : "Fallet Files.zip"
        return folder.appendingPathComponent(name)
    }

    @discardableResult
    func addTemporaryArchive(_ url: URL) -> UUID? {
        guard managedArchiveFolder(for: url) != nil,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        let entry = ShelfEntry(url: url, kind: .archive)
        entries.append(entry)
        changed()
        return entry.id
    }

    func discardTemporaryArchive(at url: URL) {
        guard let folder = managedArchiveFolder(for: url) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    func removeTemporaryArchives() {
        let archiveIDs = Set(entries.filter { $0.kind == .archive }.map(\.id))
        if !archiveIDs.isEmpty { remove(archiveIDs) }
        discardOrphanedArchives()
    }

    func addText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.append(ShelfEntry(content: trimmed, kind: .text))
        changed()
    }

    func addLink(_ link: URL) {
        guard !link.isFileURL, let scheme = link.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return }
        entries.append(ShelfEntry(content: link.absoluteString, kind: .link))
        changed()
    }

    @discardableResult
    func addImage(_ pngData: Data) -> Bool {
        guard !pngData.isEmpty, pngData.count <= 32_000_000 else { return false }
        let name = "Image-\(UUID().uuidString).png"
        let url = imageDirectory.appendingPathComponent(name)
        do {
            try pngData.write(to: url, options: .atomic)
            entries.append(ShelfEntry(url: url, kind: .image))
            changed()
            return true
        } catch { return false }
    }

    @discardableResult
    func renameFile(_ id: UUID, to newName: String) throws -> URL {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.isFileLike }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let source = entries[index].url
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        guard destination != source else { return source }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        entries[index].updateReference(to: destination)
        changed()
        return destination
    }

    func moveEntry(_ id: UUID, by offset: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let peers = entries.indices.filter { entries[$0].isFileLike == entries[index].isFileLike }
        guard let position = peers.firstIndex(of: index),
              peers.indices.contains(position + offset) else { return }
        entries.swapAt(index, peers[position + offset])
        changed()
    }

    @discardableResult
    func relink(_ id: UUID, to url: URL) -> Bool {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path),
              let index = entries.firstIndex(where: { $0.id == id && $0.isFileLike && $0.kind != .archive }) else { return false }
        let path = url.standardizedFileURL.path
        guard !entries.contains(where: { $0.id != id && $0.path == path }) else { return false }
        entries[index].updateReference(to: url)
        changed()
        return true
    }

    func remove(_ ids: Set<UUID>) {
        for entry in entries where ids.contains(entry.id) && entry.kind == .image
            && entry.url.deletingLastPathComponent().standardizedFileURL == imageDirectory.standardizedFileURL {
            try? FileManager.default.removeItem(at: entry.url)
        }
        for entry in entries where ids.contains(entry.id) && entry.kind == .archive {
            discardTemporaryArchive(at: entry.url)
        }
        entries.removeAll { ids.contains($0.id) }
        changed()
    }

    func removePaths(_ paths: Set<String>) {
        remove(Set(entries.filter { $0.isFileLike && paths.contains($0.path) }.map(\.id)))
    }

    func clear() {
        remove(Set(entries.map(\.id)))
        discardOrphanedArchives()
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

    private func managedArchiveFolder(for url: URL) -> URL? {
        let folder = url.standardizedFileURL.deletingLastPathComponent()
        guard folder.deletingLastPathComponent() == archiveDirectory.standardizedFileURL,
              UUID(uuidString: folder.lastPathComponent) != nil else { return nil }
        return folder
    }

    private func discardOrphanedArchives() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: archiveDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private static func inferredVolumePath(for path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        return "/Volumes/\(parts[1])"
    }
}
