import Foundation
import Observation

struct RulesManifest: Codable, Equatable {
    let version: Int
    let files: [String]
}

/// The rule files (content.js and cleanser.css per platform). Bundled copies
/// ship with the app; a newer set is fetched from the repo's main branch and
/// cached, so a selector fix is a git push rather than a TestFlight build.
/// A cached set is only used when its version beats the bundled one.
@Observable
final class RulesStore {
    static let shared = RulesStore()

    static let remoteBase = URL(string: "https://raw.githubusercontent.com/danstone24/d4n-social/main/ios/D4NSocial/Rules/")!
    /// Every rule file carries this in its first line; a fetch without it is refused.
    static let sentinel = "d4n-social rules"
    static let manifestName = "manifest.json"

    enum Source: String { case bundled, remote }

    private(set) var source: Source = .bundled
    private(set) var version = 0
    private(set) var lastChecked: Date?
    private(set) var lastError: String?
    private(set) var checking = false
    /// Called after a newer set is installed, so open WebViews reinstall their scripts.
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private let bundledDir: URL
    @ObservationIgnored private let cacheDir: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let bundledVersion: Int

    init(bundledDir: URL? = nil, cacheDir: URL? = nil, session: URLSession = .shared) {
        self.bundledDir = bundledDir ?? Bundle.main.resourceURL!.appending(path: "Rules")
        self.cacheDir = cacheDir ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Rules")
        self.session = session
        bundledVersion = Self.manifest(in: self.bundledDir)?.version ?? 0
        version = bundledVersion
        if let cached = Self.manifest(in: self.cacheDir), cached.version > bundledVersion,
           cached.files.allSatisfy({ FileManager.default.fileExists(atPath: self.cacheDir.appending(path: $0).path) }) {
            source = .remote
            version = cached.version
        }
    }

    static func fileNames(for platform: Platform) -> (script: String, style: String) {
        ("\(platform.rawValue).content.js", "\(platform.rawValue).cleanser.css")
    }

    func script(for platform: Platform) -> String { read(Self.fileNames(for: platform).script) }
    func style(for platform: Platform) -> String { read(Self.fileNames(for: platform).style) }

    private func read(_ name: String) -> String {
        let dir = source == .remote ? cacheDir : bundledDir
        return (try? String(contentsOf: dir.appending(path: name), encoding: .utf8)) ?? ""
    }

    private static func manifest(in dir: URL) -> RulesManifest? {
        guard let data = try? Data(contentsOf: dir.appending(path: manifestName)) else { return nil }
        return try? JSONDecoder().decode(RulesManifest.self, from: data)
    }

    /// A rule file is accepted only if it looks like ours.
    static func validate(name: String, contents: String) -> Bool {
        guard contents.count > 100 else { return false }
        let head = contents.prefix(200)
        return head.contains(sentinel) && (name.hasSuffix(".js") || name.hasSuffix(".css"))
    }

    /// Fetches the manifest and, if it is newer than what is in use, every
    /// file in it. All-or-nothing: the cache only changes once every file
    /// downloaded and validated.
    @MainActor
    func refresh() async {
        guard !checking else { return }
        checking = true
        defer { checking = false; lastChecked = Date() }
        do {
            let manifest = try JSONDecoder().decode(RulesManifest.self, from: try await fetch(Self.manifestName))
            guard manifest.version > version else { lastError = nil; return }
            let staging = FileManager.default.temporaryDirectory.appending(path: "rules-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for name in manifest.files {
                let contents = String(decoding: try await fetch(name), as: UTF8.self)
                guard Self.validate(name: name, contents: contents) else {
                    throw URLError(.cannotDecodeContentData, userInfo: [NSLocalizedDescriptionKey: "\(name) failed validation"])
                }
                try contents.write(to: staging.appending(path: name), atomically: true, encoding: .utf8)
            }
            try JSONEncoder().encode(manifest).write(to: staging.appending(path: Self.manifestName))
            try FileManager.default.createDirectory(at: cacheDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: cacheDir.path) {
                _ = try FileManager.default.replaceItemAt(cacheDir, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: cacheDir)
            }
            source = .remote
            version = manifest.version
            lastError = nil
            onUpdate?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetch(_ name: String) async throws -> Data {
        var request = URLRequest(url: Self.remoteBase.appending(path: name))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "\(name): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
        }
        return data
    }
}
