import Foundation

struct FalletVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, (part.count == 1 || part.first != "0"),
                  part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        components = numbers
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func == (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<3 {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return false }
        }
        return true
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<3 {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct FalletRelease: Equatable {
    let version: FalletVersion
    let url: URL
}

struct AvailableUpdate: Equatable {
    let installedVersion: FalletVersion
    let release: FalletRelease
}

enum ReleaseCheckError: Error {
    case invalidResponse
    case httpStatus(Int)
}

final class GitHubReleaseClient {
    static let endpoint = URL(string: "https://api.github.com/repos/Shinvitiya/Fallet/releases/latest")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetchLatest(_ completion: @escaping (Result<FalletRelease?, Error>) -> Void) {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Fallet-update-checker", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            do {
                completion(.success(try Self.parse(data: data, response: response)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    static func parse(data: Data?, response: URLResponse?) throws -> FalletRelease? {
        guard let response = response as? HTTPURLResponse else { throw ReleaseCheckError.invalidResponse }
        guard response.statusCode == 200 else { throw ReleaseCheckError.httpStatus(response.statusCode) }
        guard let data, data.count <= 128_000 else { throw ReleaseCheckError.invalidResponse }
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool
            let prerelease: Bool
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        if payload.draft || payload.prerelease { return nil }
        guard payload.tag_name.hasPrefix("v"),
              let version = FalletVersion(String(payload.tag_name.dropFirst())),
              let url = URL(string: payload.html_url), url.scheme == "https",
              url.host == "github.com",
              url.path.lowercased() == "/shinvitiya/fallet/releases/tag/\(payload.tag_name)" else {
            throw ReleaseCheckError.invalidResponse
        }
        return FalletRelease(version: version, url: url)
    }
}

final class UpdateChecker {
    typealias Fetch = (@escaping (Result<FalletRelease?, Error>) -> Void) -> Void

    private enum Key {
        static let version = "UpdateChecker.releaseVersion"
        static let url = "UpdateChecker.releaseURL"
        static let successfulCheck = "UpdateChecker.successfulCheck"
        static let attemptedCheck = "UpdateChecker.attemptedCheck"
    }

    private let installedVersion: FalletVersion?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetch: Fetch
    private(set) var isChecking = false

    init(installedVersion: String, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init, fetch: @escaping Fetch = GitHubReleaseClient().fetchLatest) {
        self.installedVersion = FalletVersion(installedVersion)
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
    }

    var cachedUpdate: AvailableUpdate? {
        guard let installedVersion,
              let versionText = defaults.string(forKey: Key.version),
              let version = FalletVersion(versionText), version > installedVersion,
              let urlText = defaults.string(forKey: Key.url),
              let url = URL(string: urlText), url.scheme == "https", url.host == "github.com",
              url.path.lowercased() == "/shinvitiya/fallet/releases/tag/v\(versionText)" else { return nil }
        return AvailableUpdate(installedVersion: installedVersion,
                               release: FalletRelease(version: version, url: url))
    }

    @discardableResult
    func refreshIfDue(onChange: @escaping (AvailableUpdate?) -> Void) -> Bool {
        precondition(Thread.isMainThread)
        guard installedVersion != nil, !isChecking else { return false }
        let current = now()
        if let last = defaults.object(forKey: Key.successfulCheck) as? Date,
           (0..<86_400).contains(current.timeIntervalSince(last)) { return false }
        if let last = defaults.object(forKey: Key.attemptedCheck) as? Date,
           (0..<3_600).contains(current.timeIntervalSince(last)) { return false }

        isChecking = true
        defaults.set(current, forKey: Key.attemptedCheck)
        fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                guard case let .success(release) = result else { return }
                self.defaults.set(self.now(), forKey: Key.successfulCheck)
                if let release {
                    self.defaults.set(release.version.description, forKey: Key.version)
                    self.defaults.set(release.url.absoluteString, forKey: Key.url)
                } else {
                    self.defaults.removeObject(forKey: Key.version)
                    self.defaults.removeObject(forKey: Key.url)
                }
                onChange(self.cachedUpdate)
            }
        }
        return true
    }
}
