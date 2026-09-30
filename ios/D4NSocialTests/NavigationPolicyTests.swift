import XCTest

@testable import D4NSocial

final class NavigationPolicyTests: XCTestCase {
    private let defaults = NavigationPolicy.Options()
    private let igHome = URL(string: "https://www.instagram.com/")!

    private func ig(_ string: String, _ options: NavigationPolicy.Options? = nil) -> NavigationPolicy.Decision {
        NavigationPolicy.decide(URL(string: string)!, platform: .instagram, options: options ?? defaults)
    }

    private func x(_ string: String, _ options: NavigationPolicy.Options? = nil) -> NavigationPolicy.Decision {
        NavigationPolicy.decide(URL(string: string)!, platform: .x, options: options ?? defaults)
    }

    func testReelsFeedGoesHomeButASingleReelStays() {
        XCTAssertEqual(ig("https://www.instagram.com/reels/"), .load(igHome))
        XCTAssertEqual(ig("https://www.instagram.com/reels/C1234/"), .load(igHome))
        XCTAssertEqual(ig("https://www.instagram.com/reel/C1234/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/reels/", NavigationPolicy.Options(hideReels: false)), .allow)
    }

    func testProfileReelsTabGoesBackToTheProfile() {
        XCTAssertEqual(ig("https://www.instagram.com/lufc/reels/"), .load(URL(string: "https://www.instagram.com/lufc/")!))
        XCTAssertEqual(ig("https://www.instagram.com/lufc/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/lufc/tagged/"), .allow)
    }

    func testExploreAndSearchStayWhileSuggestedPeopleBounce() {
        // The grid is hidden by CSS; the page itself carries the search field.
        XCTAssertEqual(ig("https://www.instagram.com/explore/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/explore/search/keyword/?q=leeds"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/explore/people/"), .load(igHome))
    }

    func testHomeFollowsTheModeSettings() {
        let inbox = URL(string: "https://www.instagram.com/direct/inbox/")!
        let following = URL(string: "https://www.instagram.com/?variant=following")!
        XCTAssertEqual(ig("https://www.instagram.com/"), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/", NavigationPolicy.Options(dmOnly: true)), .load(inbox))
        XCTAssertEqual(NavigationPolicy.home(for: .instagram, options: NavigationPolicy.Options(dmOnly: true)), inbox)
        XCTAssertEqual(ig("https://www.instagram.com/", NavigationPolicy.Options(followingOnly: true)), .load(following))
        XCTAssertEqual(ig("https://www.instagram.com/?variant=following", NavigationPolicy.Options(followingOnly: true)), .allow)
        XCTAssertEqual(ig("https://www.instagram.com/?variant=favorites", NavigationPolicy.Options(followingOnly: true)), .allow)
        // A blocked Reels page bounces to whatever home currently is.
        XCTAssertEqual(ig("https://www.instagram.com/reels/", NavigationPolicy.Options(dmOnly: true)), .load(inbox))
    }

    func testLinkShimUnwrapsToASafariSheet() {
        let bbc = URL(string: "https://www.bbc.co.uk/news")!
        XCTAssertEqual(ig("https://l.instagram.com/?u=https%3A%2F%2Fwww.bbc.co.uk%2Fnews&e=AT0abc"), .external(bbc))
        XCTAssertEqual(ig("https://l.instagram.com/?e=AT0abc"), .deny)
    }

    func testAppStoreAndAppSchemeBouncesAreDropped() {
        XCTAssertEqual(ig("https://apps.apple.com/app/instagram/id389801252"), .deny)
        XCTAssertEqual(ig("instagram://user?username=lufc"), .deny)
        XCTAssertEqual(ig("https://l.instagram.com/?u=https%3A%2F%2Fapps.apple.com%2Fapp%2Fid1"), .deny)
    }

    func testLoginPagesAndBlobsStayInside() {
        XCTAssertEqual(ig("https://www.facebook.com/login.php"), .allow)
        XCTAssertEqual(ig("about:blank"), .allow)
        XCTAssertEqual(ig("blob:https://www.instagram.com/abc"), .allow)
    }

    func testOtherSitesOpenExternally() {
        XCTAssertEqual(ig("https://www.bbc.co.uk/"), .external(URL(string: "https://www.bbc.co.uk/")!))
        XCTAssertEqual(ig("mailto:dan@example.com"), .external(URL(string: "mailto:dan@example.com")!))
        XCTAssertEqual(x("https://travel.d4n.uk/"), .external(URL(string: "https://travel.d4n.uk/")!))
    }

    func testXGrokBouncesHomeAndTheRestFlows() {
        let home = URL(string: "https://x.com/home")!
        XCTAssertEqual(x("https://x.com/i/grok"), .load(home))
        XCTAssertEqual(x("https://x.com/i/grok/share/123"), .load(home))
        XCTAssertEqual(x("https://x.com/i/grok", NavigationPolicy.Options(hideGrok: false)), .allow)
        XCTAssertEqual(x("https://x.com/LUFC/status/1"), .allow)
        XCTAssertEqual(x("https://twitter.com/home"), .allow)
        // t.co is a redirector to somewhere else, so it belongs in the Safari sheet.
        XCTAssertEqual(x("https://t.co/abc"), .external(URL(string: "https://t.co/abc")!))
    }
}
