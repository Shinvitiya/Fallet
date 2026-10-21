import AppKit
import Foundation

@main
struct UpdateCheckerTests {
    static func main() throws {
        _ = NSApplication.shared
        guard FalletVersion("1.10")! > FalletVersion("1.9")!,
              FalletVersion("1.10.1")! > FalletVersion("1.10")!,
              FalletVersion("1.10")! == FalletVersion("1.10.0")!,
              FalletVersion("1.9")! < FalletVersion("1.10.1")!,
              FalletVersion("1") == nil, FalletVersion("1.2.3.4") == nil,
              FalletVersion("1.02") == nil, FalletVersion("1.x") == nil,
              FalletVersion("1.2-beta") == nil else {
            fatalError("Versions must compare numerically and reject malformed values")
        }

        let stable = try parse(tag: "v1.10.1")!
        guard stable.version == FalletVersion("1.10.1"),
              try parse(tag: "v1.11", draft: true) == nil,
              try parse(tag: "v1.11", prerelease: true) == nil else {
            fatalError("Only stable GitHub releases are installable")
        }
        for tag in ["source-v1.11", "v1.11-beta", "vbad", "1.11"] {
            expectParseFailure { try parse(tag: tag) }
        }
        expectParseFailure { try parse(tag: "v1.11", releaseURL: "https://example.com/release") }
        expectParseFailure { try GitHubReleaseClient.parse(data: Data("{}".utf8), response: response(200)) }
        expectParseFailure { try GitHubReleaseClient.parse(data: Data("not json".utf8), response: response(200)) }
        expectParseFailure { try GitHubReleaseClient.parse(data: Data(), response: response(403)) }
        expectParseFailure { try GitHubReleaseClient.parse(data: Data(), response: response(500)) }
        expectParseFailure { try GitHubReleaseClient.parse(data: nil, response: nil) }
        let readyFormula = """
        class Fallet < Formula
          url "https://github.com/Shinvitiya/Fallet/archive/refs/tags/v1.10.1.tar.gz"
          sha256 "\(String(repeating: "a", count: 64))"
        end
        """
        try GitHubReleaseClient.verifyTap(data: Data(readyFormula.utf8),
                                          response: tapResponse(200), release: stable)
        expectParseFailure {
            try GitHubReleaseClient.verifyTap(data: Data(readyFormula.replacingOccurrences(
                of: "v1.10.1.tar.gz", with: "v1.10.tar.gz").utf8),
                response: tapResponse(200), release: stable)
        }
        expectParseFailure {
            try GitHubReleaseClient.verifyTap(data: Data(readyFormula.replacingOccurrences(
                of: String(repeating: "a", count: 64), with: "bad").utf8),
                response: tapResponse(200), release: stable)
        }
        expectParseFailure {
            try GitHubReleaseClient.verifyTap(data: Data(readyFormula.utf8),
                response: tapResponse(404), release: stable)
        }
        let releaseJSON = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v1.10.1", "html_url": stable.url.absoluteString,
            "draft": false, "prerelease": false
        ] as [String: Any])
        guard case .failure = fetchWithStub(release: releaseJSON,
                                             tap: Data(readyFormula.replacingOccurrences(
                                                of: "v1.10.1.tar.gz", with: "v1.10.tar.gz").utf8)),
              case .success(let fetched) = fetchWithStub(release: releaseJSON,
                                                          tap: Data(readyFormula.utf8)),
              fetched == stable else {
            fatalError("The update client must wait until the Homebrew tap advertises the release")
        }

        let suiteName = "FalletUpdateCheckerTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        var fetchCount = 0
        var completion: ((Result<FalletRelease?, Error>) -> Void)?
        let checker = UpdateChecker(installedVersion: "1.9", defaults: defaults, now: { time }) { callback in
            fetchCount += 1
            completion = callback
        }
        var observed: AvailableUpdate?
        guard checker.cachedUpdate == nil,
              checker.refreshIfDue(onChange: { observed = $0 }), fetchCount == 1 else {
            fatalError("A first launch should request the latest release")
        }
        completion?(.success(stable))
        pump { observed != nil }
        guard observed?.release == stable, checker.cachedUpdate == observed,
              !checker.refreshIfDue(onChange: { _ in }), fetchCount == 1 else {
            fatalError("Successful checks should cache the release and wait 24 hours")
        }
        let current = UpdateChecker(installedVersion: "1.10.1", defaults: defaults, now: { time }) { _ in }
        let ahead = UpdateChecker(installedVersion: "1.11", defaults: defaults, now: { time }) { _ in }
        guard current.cachedUpdate == nil, ahead.cachedUpdate == nil else {
            fatalError("Current and ahead installations must not show an update")
        }
        time.addTimeInterval(86_400)
        guard checker.refreshIfDue(onChange: { _ in }), fetchCount == 2 else {
            fatalError("A successful result must refresh after 24 hours")
        }
        completion?(.success(nil))
        pump { checker.cachedUpdate == nil }

        let offlineSuite = "FalletOfflineTests-\(UUID())"
        let offlineDefaults = UserDefaults(suiteName: offlineSuite)!
        defer { offlineDefaults.removePersistentDomain(forName: offlineSuite) }
        var offlineTime = Date(timeIntervalSince1970: 1_800_000_000)
        var offlineFetches = 0
        let offline = UpdateChecker(installedVersion: "1.9", defaults: offlineDefaults,
                                    now: { offlineTime }) { callback in
            offlineFetches += 1
            callback(.failure(URLError(.notConnectedToInternet)))
        }
        guard offline.refreshIfDue(onChange: { _ in }) else { fatalError("Offline check did not start") }
        pump { !offline.isChecking }
        guard offline.cachedUpdate == nil, offlineFetches == 1 else {
            fatalError("Network failure must not show an update or repeatedly retry")
        }
        offlineTime.addTimeInterval(3_600)
        guard offline.refreshIfDue(onChange: { _ in }), offlineFetches == 2 else {
            fatalError("A failed request should be eligible for retry after an hour")
        }
        let invalid = UpdateChecker(installedVersion: "", defaults: offlineDefaults, fetch: { _ in
            fatalError("Invalid installed version must not use the network")
        })
        guard !invalid.refreshIfDue(onChange: { _ in }), invalid.cachedUpdate == nil else {
            fatalError("Missing version metadata should disable checks safely")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FalletUpdateView-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let brewedBundle = root.appendingPathComponent("Cellar/fallet/1.10.1/Fallet.app")
        try FileManager.default.createDirectory(at: brewedBundle, withIntermediateDirectories: true)
        let linkedBundle = root.appendingPathComponent("Applications/Fallet.app")
        try FileManager.default.createDirectory(at: linkedBundle.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedBundle, withDestinationURL: brewedBundle)
        guard FalletInstallation.isHomebrewBundle(brewedBundle),
              FalletInstallation.isHomebrewBundle(linkedBundle),
              !FalletInstallation.isHomebrewBundle(root.appendingPathComponent("Other/Fallet.app")) else {
            fatalError("The update action must recognize only Homebrew-managed app bundles")
        }
        let file = root.appendingPathComponent("test.txt")
        try Data("drag test".utf8).write(to: file)
        let store = ShelfStore(storageURL: root.appendingPathComponent("shelf.json"))
        store.add([file])
        let shelf = ShelfView(store: store)
        guard let scroll = shelf.subviews.compactMap({ $0 as? NSScrollView }).first else {
            fatalError("Test shelf should contain a file list")
        }
        let baseHeight = shelf.frame.height
        let available = AvailableUpdate(installedVersion: FalletVersion("1.9")!, release: stable)
        shelf.availableUpdate = available
        guard shelf.frame.height == baseHeight,
              shelf.subviews.contains(where: { $0 === scroll }),
              shelf.subviews.flatMap(\.subviews).compactMap({ $0 as? NSButton }).contains(where: {
                  $0.accessibilityLabel()?.contains("Fallet update available") == true
              }) else {
            fatalError("An available update should add a compact header badge without resizing the shelf")
        }
        shelf.availableUpdate = nil
        guard shelf.subviews.contains(where: { $0 === scroll }),
              !shelf.subviews.flatMap(\.subviews).compactMap({ $0 as? NSButton }).contains(where: {
            $0.accessibilityLabel()?.contains("Fallet update available") == true
        }) else {
            fatalError("The update badge should disappear when availability changes")
        }
        print("Update checker and badge tests passed")
    }

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: GitHubReleaseClient.endpoint, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    private static func tapResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: GitHubReleaseClient.tapEndpoint, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    private static func fetchWithStub(release: Data, tap: Data) -> Result<FalletRelease?, Error> {
        StubReleaseProtocol.releaseData = release
        StubReleaseProtocol.tapData = tap
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubReleaseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let finished = DispatchSemaphore(value: 0)
        var received: Result<FalletRelease?, Error>?
        GitHubReleaseClient(session: session).fetchLatest { result in
            received = result
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 5) == .success, let received else {
            fatalError("Stubbed release request timed out")
        }
        return received
    }

    private static func parse(tag: String, draft: Bool = false, prerelease: Bool = false,
                              releaseURL: String? = nil) throws -> FalletRelease? {
        let url = releaseURL ?? "https://github.com/Shinvitiya/Fallet/releases/tag/\(tag)"
        let object: [String: Any] = ["tag_name": tag, "html_url": url,
                                     "draft": draft, "prerelease": prerelease]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try GitHubReleaseClient.parse(data: data, response: response(200))
    }

    private static func expectParseFailure(_ action: () throws -> Any?) {
        do { _ = try action(); fatalError("Malformed release response was accepted") }
        catch { }
    }

    private static func pump(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        guard condition() else { fatalError("Asynchronous update did not finish") }
    }
}

private final class StubReleaseProtocol: URLProtocol {
    static var releaseData = Data()
    static var tapData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url == GitHubReleaseClient.endpoint || request.url == GitHubReleaseClient.tapEndpoint
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = url == GitHubReleaseClient.endpoint ? Self.releaseData : Self.tapData
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
