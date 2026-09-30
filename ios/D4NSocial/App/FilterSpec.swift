import Foundation

/// One toggle in the Filters screen. Keys match the DEFAULTS block of the
/// platform's content.js exactly; a unit test checks the two stay in sync.
/// X keys are the TwitterCleanser names so an extension export imports as is.
struct FilterSpec: Identifiable {
    let key: String
    /// nil applies to every platform (audit mode).
    let platform: Platform?
    let title: String
    let detail: String
    let defaultOn: Bool
    var beta = false

    var id: String { key }
}

enum Filters {
    static let all: [FilterSpec] = [
        // Instagram, on by default
        FilterSpec(key: "igHideReels", platform: .instagram, title: "Reels", detail: "Reels tab, the Reels feed and Reels carousels in the home feed", defaultOn: true),
        FilterSpec(key: "igHideExplore", platform: .instagram, title: "Explore grid", detail: "Search stays, the grid of suggested posts goes", defaultOn: true),
        FilterSpec(key: "igHideSuggestedPosts", platform: .instagram, title: "Suggested posts", detail: "Posts from accounts you do not follow", defaultOn: true),
        FilterSpec(key: "igHideAds", platform: .instagram, title: "Ads", detail: "Sponsored posts", defaultOn: true),
        FilterSpec(key: "igHideSuggestedAccounts", platform: .instagram, title: "Suggested accounts", detail: "Suggested for you carousels", defaultOn: true),
        FilterSpec(key: "igHideAppNags", platform: .instagram, title: "Open in app nags", detail: "Banners and dialogs pushing the app", defaultOn: true),
        FilterSpec(key: "igHidePromos", platform: .instagram, title: "Threads and Meta AI", detail: "Threads links and Meta AI entry points", defaultOn: true),
        FilterSpec(key: "igHideShopping", platform: .instagram, title: "Shopping", detail: "Shop tab and links", defaultOn: true),
        // Instagram, off by default
        FilterSpec(key: "igHideStories", platform: .instagram, title: "Stories row", detail: "The tray at the top of the home feed", defaultOn: false),
        FilterSpec(key: "igHideCounts", platform: .instagram, title: "Like and view counts", detail: "Numbers under posts", defaultOn: false),
        FilterSpec(key: "igHideNotifications", platform: .instagram, title: "Notifications tab", detail: "The heart in the top bar", defaultOn: false),
        FilterSpec(key: "igDMOnly", platform: .instagram, title: "DM-only mode", detail: "Home opens the inbox instead of the feed", defaultOn: false),
        FilterSpec(key: "igStopAtCaughtUp", platform: .instagram, title: "Stop at caught up", detail: "Nothing loads after You're all caught up", defaultOn: false),
        FilterSpec(key: "igFollowingOnly", platform: .instagram, title: "Following feed only", detail: "Opens the Following feed. Instagram shows no stories row there", defaultOn: false),

        // X, on by default (TwitterCleanser defaults, plus Following only)
        FilterSpec(key: "followingOnly", platform: .x, title: "Following only", detail: "Hides the For You tab and switches to Following", defaultOn: true),
        FilterSpec(key: "hideAds", platform: .x, title: "Ads and promoted", detail: "Promoted posts and promoted trends", defaultOn: true),
        FilterSpec(key: "hideTrending", platform: .x, title: "Trending", detail: "What's happening and Trends for you", defaultOn: true),
        FilterSpec(key: "hideWhoToFollow", platform: .x, title: "Who to follow", detail: "Follow suggestions in timelines and Explore", defaultOn: true),
        FilterSpec(key: "hidePremium", platform: .x, title: "Premium upsells", detail: "Subscribe boxes and menu links", defaultOn: true),
        FilterSpec(key: "hideGrok", platform: .x, title: "Grok", detail: "Grok tab and per-post Grok buttons", defaultOn: true),
        FilterSpec(key: "hideGrokMentions", platform: .x, title: "@grok mentions", detail: "Posts and replies that summon @grok", defaultOn: true),
        FilterSpec(key: "hideMentionOnlyReplies", platform: .x, title: "Mention-only replies", detail: "Replies that are just @handles", defaultOn: true),
        FilterSpec(key: "hideLinkOnlyPosts", platform: .x, title: "Link-only posts", detail: "A bare URL and no words", defaultOn: true),
        FilterSpec(key: "hideDiscoverMore", platform: .x, title: "Discover more", detail: "Suggested posts under conversations", defaultOn: true),
        FilterSpec(key: "blockButtons", platform: .x, title: "Block button", detail: "One-tap block on every post, with undo", defaultOn: true),
        // X beta, off by default
        FilterSpec(key: "betaMuteWords", platform: .x, title: "Mute words", detail: "Your own list, edited under Mute words", defaultOn: false, beta: true),
        FilterSpec(key: "betaLowEffort", platform: .x, title: "Low-effort replies", detail: "This, W, emoji-only", defaultOn: false, beta: true),
        FilterSpec(key: "betaEngagementBait", platform: .x, title: "Engagement bait", detail: "Repost if, tag a friend, giveaways", defaultOn: false, beta: true),
        FilterSpec(key: "betaHideReposts", platform: .x, title: "Reposts", detail: "Strip reposts from timelines", defaultOn: false, beta: true),
        FilterSpec(key: "betaHashtagSpam", platform: .x, title: "Hashtag spam", detail: "Five or more hashtags", defaultOn: false, beta: true),
        FilterSpec(key: "betaSlimNav", platform: .x, title: "Slim nav", detail: "Communities, Jobs, Ads, Verified Orgs, Business", defaultOn: false, beta: true),
        FilterSpec(key: "betaHideNags", platform: .x, title: "Timeline nags", detail: "Turn on notifications prompts", defaultOn: false, beta: true),
        FilterSpec(key: "betaHideViews", platform: .x, title: "View counts", detail: "The number in each action bar", defaultOn: false, beta: true),
        FilterSpec(key: "betaMuteButton", platform: .x, title: "Mute button", detail: "One-tap mute next to block", defaultOn: false, beta: true),
        FilterSpec(key: "betaHideAIPosts", platform: .x, title: "AI-made posts", detail: "Made with AI labels and tags", defaultOn: false, beta: true),
        FilterSpec(key: "betaHideParody", platform: .x, title: "Parody accounts", detail: "Parody, satire and fan account labels", defaultOn: false, beta: true),
        FilterSpec(key: "betaHideVerifiedReplies", platform: .x, title: "Blue-check replies", detail: "Verified replies in conversations", defaultOn: false, beta: true),

        // Shared
        FilterSpec(key: "auditMode", platform: nil, title: "Audit mode", detail: "Dim and label matches instead of hiding them", defaultOn: false),
    ]

    private static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    static func spec(_ key: String) -> FilterSpec? { byKey[key] }

    static func defaultValue(_ key: String) -> Bool { byKey[key]?.defaultOn ?? false }

    /// Everyday toggles for a platform's section of the Filters screen.
    static func core(for platform: Platform) -> [FilterSpec] {
        all.filter { $0.platform == platform && !$0.beta }
    }

    static func beta(for platform: Platform) -> [FilterSpec] {
        all.filter { $0.platform == platform && $0.beta }
    }

    /// Keys pushed to a platform's rules: its own plus the shared ones.
    static func keys(for platform: Platform) -> [String] {
        all.filter { $0.platform == platform || $0.platform == nil }.map(\.key)
    }
}
