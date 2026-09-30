import XCTest

@testable import D4NSocial

final class SettingsTests: XCTestCase {
    private var suites: [String] = []

    private func freshStore() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    }

    func testDefaultsComeFromTheCatalogue() {
        let settings = Settings(store: freshStore())
        XCTAssertTrue(settings.isOn("followingOnly"))
        XCTAssertTrue(settings.isOn("igHideReels"))
        XCTAssertFalse(settings.isOn("igHideStories"))
        XCTAssertFalse(settings.isOn("betaMuteWords"))
        XCTAssertFalse(settings.isOn("noSuchKey"))
    }

    func testChangesPersistAndNotifyOnce() {
        let store = freshStore()
        let settings = Settings(store: store)
        var pings = 0
        settings.listeners.append { _ in pings += 1 }
        settings.set("hideAds", false)
        settings.set("hideAds", false) // no change, no ping
        settings.setMuteWords("crypto")
        XCTAssertEqual(pings, 2)
        let again = Settings(store: store)
        XCTAssertFalse(again.isOn("hideAds"))
        XCTAssertEqual(again.muteWordsList, "crypto")
    }

    func testSnapshotCarriesOnlyThePlatformAndSharedKeys() {
        let settings = Settings(store: freshStore())
        let instagram = settings.snapshot(for: .instagram)
        XCTAssertEqual(instagram["igHideReels"] as? Bool, true)
        XCTAssertEqual(instagram["auditMode"] as? Bool, false)
        XCTAssertNil(instagram["hideAds"])
        XCTAssertNil(instagram["muteWordsList"])
        let x = settings.snapshot(for: .x)
        XCTAssertEqual(x["followingOnly"] as? Bool, true)
        XCTAssertEqual(x["muteWordsList"] as? String, "")
        XCTAssertNil(x["igHideReels"])
    }

    func testExportRoundTripsThroughReplace() throws {
        let settings = Settings(store: freshStore())
        settings.set("igHideStories", true)
        settings.set("hideAds", false)
        settings.setMuteWords("crypto\nnft")
        let other = Settings(store: freshStore())
        try other.importJSON(Data(settings.exportJSON().utf8), mode: .replace)
        for spec in Filters.all {
            XCTAssertEqual(other.isOn(spec.key), settings.isOn(spec.key), spec.key)
        }
        XCTAssertEqual(other.muteWordsList, "crypto\nnft")
    }

    func testMergeKeepsWhatTheFileDoesNotMentionAndReplaceDoesNot() throws {
        let settings = Settings(store: freshStore())
        settings.set("igHideStories", true)
        let file = Data(#"{"settings":{"hideAds":false}}"#.utf8)
        XCTAssertEqual(try settings.importJSON(file, mode: .merge), 1)
        XCTAssertTrue(settings.isOn("igHideStories"))
        XCTAssertFalse(settings.isOn("hideAds"))
        try settings.importJSON(file, mode: .replace)
        XCTAssertFalse(settings.isOn("igHideStories")) // back to its default
        XCTAssertFalse(settings.isOn("hideAds"))
    }

    func testATwitterCleanserExportImports() throws {
        let settings = Settings(store: freshStore())
        let file = Data("""
        {"twittercleanser": 1, "version": "1.0.0", "exported": "2026-09-30T20:00:00Z",
         "settings": {"hideAds": false, "muteWordsList": "spam", "betaBlockLog": true, "hideGrok": "yes"}}
        """.utf8)
        // betaBlockLog is extension-only and hideGrok has the wrong type: both ignored.
        XCTAssertEqual(try settings.importJSON(file, mode: .merge), 2)
        XCTAssertFalse(settings.isOn("hideAds"))
        XCTAssertTrue(settings.isOn("hideGrok"))
        XCTAssertEqual(settings.muteWordsList, "spam")
    }

    func testForeignFilesAreRejected() {
        let settings = Settings(store: freshStore())
        XCTAssertThrowsError(try settings.importJSON(Data("[1, 2]".utf8), mode: .merge))
        XCTAssertThrowsError(try settings.importJSON(Data(#"{"foo": 1}"#.utf8), mode: .merge))
        XCTAssertThrowsError(try settings.importJSON(Data("not json".utf8), mode: .replace))
    }

    func testBlockLogDedupesNewestFirstAndPersists() {
        let store = freshStore()
        let settings = Settings(store: store)
        settings.recordBlock("spammer")
        settings.recordBlock("bot")
        settings.recordBlock("spammer")
        XCTAssertEqual(settings.blockLog.map(\.handle), ["bot", "spammer"])
        settings.removeBlock("bot")
        XCTAssertEqual(Settings(store: store).blockLog.map(\.handle), ["spammer"])
    }

    /// The DEFAULTS block of each content.js must list exactly the catalogue's
    /// keys for that platform (plus the shared ones) with the same values.
    func testRuleDefaultsMatchTheCatalogue() throws {
        let rules = RulesStore(cacheDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        for platform in Platform.allCases {
            let script = rules.script(for: platform)
            let block = try XCTUnwrap(script.range(of: "const DEFAULTS = {").map { script[$0.upperBound...] })
            let body = block[..<(block.range(of: "\n  };")?.lowerBound ?? block.endIndex)]
            var found: [String: Bool] = [:]
            for line in body.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let colon = trimmed.firstIndex(of: ":"), !trimmed.hasPrefix("//") else { continue }
                let key = String(trimmed[..<colon])
                let rest = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("true") { found[key] = true } else if rest.hasPrefix("false") { found[key] = false }
            }
            let expected = Dictionary(uniqueKeysWithValues: Filters.keys(for: platform).map { ($0, Filters.defaultValue($0)) })
            XCTAssertEqual(found, expected, "\(platform) DEFAULTS drifted from FilterSpec.swift")
        }
    }
}
