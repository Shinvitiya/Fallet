import Foundation

struct SavedScriptAction: Codable, Equatable {
    let id: UUID
    var title: String
    var path: String
    var bookmarkData: Data?

    init(url: URL, title: String) {
        id = UUID()
        self.title = title
        path = url.standardizedFileURL.path
        bookmarkData = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    var url: URL {
        if let bookmarkData {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI, .withoutMounting],
                                       relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: resolved.path) { return resolved }
        }
        return URL(fileURLWithPath: path)
    }
}

final class ScriptActionStore {
    private(set) var actions: [SavedScriptAction] = []
    private let storageURL: URL

    init(storageURL customURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageURL = customURL ?? support.appendingPathComponent("Fallet/scripts.json")
        if let data = try? Data(contentsOf: storageURL),
           let saved = try? JSONDecoder().decode([SavedScriptAction].self, from: data) { actions = saved }
    }

    func add(_ url: URL, title: String) {
        actions.append(SavedScriptAction(url: url, title: title))
        save()
    }

    func remove(_ id: UUID) {
        actions.removeAll { $0.id == id }
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(actions) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}
