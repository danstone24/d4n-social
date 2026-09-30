import XCTest

@testable import D4NSocial

final class RulesStoreTests: XCTestCase {
    private var cacheDir: URL!

    override func setUp() {
        cacheDir = FileManager.default.temporaryDirectory.appending(path: "rules-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDir)
    }

    private func writeCache(version: Int, files: [String] = RulesManifest.allFiles, body: String = "") throws {
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let manifest = RulesManifest(version: version, files: RulesManifest.allFiles)
        try JSONEncoder().encode(manifest).write(to: cacheDir.appending(path: RulesStore.manifestName))
        for name in files {
            let contents = "/* \(RulesStore.sentinel): cached \(name) */\n" + body + String(repeating: "/* pad */\n", count: 20)
            try contents.write(to: cacheDir.appending(path: name), atomically: true, encoding: .utf8)
        }
    }

    func testBundledRulesLoadAndCarryTheSentinel() {
        let store = RulesStore(cacheDir: cacheDir)
        XCTAssertEqual(store.source, .bundled)
        XCTAssertGreaterThan(store.version, 0)
        for platform in Platform.allCases {
            XCTAssertTrue(store.script(for: platform).hasPrefix("/* \(RulesStore.sentinel)"), "\(platform) script")
            XCTAssertTrue(store.style(for: platform).hasPrefix("/* \(RulesStore.sentinel)"), "\(platform) style")
        }
    }

    func testValidateRefusesForeignFiles() {
        XCTAssertFalse(RulesStore.validate(name: "x.content.js", contents: "<html><body>404: Not Found</body></html>"))
        XCTAssertFalse(RulesStore.validate(name: "x.content.js", contents: String(repeating: "a", count: 500)))
        XCTAssertFalse(RulesStore.validate(name: "x.content.js", contents: "/* d4n-social rules */"))
        XCTAssertTrue(RulesStore.validate(name: "x.content.js", contents: "/* d4n-social rules: x */\n" + String(repeating: "a", count: 200)))
        XCTAssertFalse(RulesStore.validate(name: "manifest.json", contents: "/* d4n-social rules */\n" + String(repeating: "a", count: 200)))
    }

    func testANewerCacheWinsOverTheBundle() throws {
        try writeCache(version: 999)
        let store = RulesStore(cacheDir: cacheDir)
        XCTAssertEqual(store.source, .remote)
        XCTAssertEqual(store.version, 999)
        XCTAssertTrue(store.script(for: .x).contains("cached x.content.js"))
    }

    func testAnOlderOrIncompleteCacheIsIgnored() throws {
        try writeCache(version: 0)
        XCTAssertEqual(RulesStore(cacheDir: cacheDir).source, .bundled)
        try FileManager.default.removeItem(at: cacheDir)
        try writeCache(version: 999, files: ["x.content.js"]) // three files missing
        XCTAssertEqual(RulesStore(cacheDir: cacheDir).source, .bundled)
    }
}

extension RulesManifest {
    static let allFiles = ["x.content.js", "x.cleanser.css", "instagram.content.js", "instagram.cleanser.css"]
}
