import Foundation

/// Where a top-level navigation may go. Pure, so it is unit-tested; `WebTab`
/// applies the decisions. The rules' JS click guard mirrors the blocked paths.
enum NavigationPolicy {
    enum Decision: Equatable {
        case allow
        /// A blocked page: load this one instead.
        case load(URL)
        /// Not our site: open in a Safari sheet.
        case external(URL)
        /// App Store bounces, instagram://, unknown schemes: ignore.
        case deny
    }

    struct Options: Equatable {
        var hideReels = true
        var hideExplore = true
        var dmOnly = false
        var followingOnly = false
        var hideGrok = true

        init(hideReels: Bool = true, hideExplore: Bool = true, dmOnly: Bool = false,
             followingOnly: Bool = false, hideGrok: Bool = true) {
            self.hideReels = hideReels
            self.hideExplore = hideExplore
            self.dmOnly = dmOnly
            self.followingOnly = followingOnly
            self.hideGrok = hideGrok
        }

        init(settings: Settings) {
            self.init(
                hideReels: settings.isOn("igHideReels"),
                hideExplore: settings.isOn("igHideExplore"),
                dmOnly: settings.isOn("igDMOnly"),
                followingOnly: settings.isOn("igFollowingOnly"),
                hideGrok: settings.isOn("hideGrok"))
        }
    }

    /// "Open the app" buttons: never followed.
    static let deniedHosts = ["apps.apple.com", "itunes.apple.com", "play.google.com"]

    static func home(for platform: Platform, options: Options) -> URL {
        switch platform {
        case .x:
            return URL(string: "https://x.com/home")!
        case .instagram:
            if options.dmOnly { return URL(string: "https://www.instagram.com/direct/inbox/")! }
            if options.followingOnly { return URL(string: "https://www.instagram.com/?variant=following")! }
            return URL(string: "https://www.instagram.com/")!
        }
    }

    static func decide(_ url: URL, platform: Platform, options: Options) -> Decision {
        guard let scheme = url.scheme?.lowercased() else { return .deny }
        if ["about", "blob", "data"].contains(scheme) { return .allow }
        if ["mailto", "tel", "sms"].contains(scheme) { return .external(url) }
        guard scheme == "http" || scheme == "https", let host = url.host()?.lowercased() else { return .deny }
        if deniedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .deny }

        // Outbound Instagram links are wrapped as https://l.instagram.com/?u=<real link>.
        if host == "l.instagram.com" {
            guard let target = queryItem("u", in: url).flatMap(URL.init(string:)) else { return .deny }
            return decide(target, platform: platform, options: options)
        }
        guard platform.hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            return .external(url)
        }
        switch platform {
        case .instagram: return instagram(url, host: host, options: options)
        case .x: return x(url, options: options)
        }
    }

    private static func instagram(_ url: URL, host: String, options: Options) -> Decision {
        guard host.hasSuffix("instagram.com") else { return .allow } // Facebook login pages
        var path = url.path().lowercased()
        if !path.hasSuffix("/") { path += "/" }
        let home = home(for: .instagram, options: options)

        if path == "/" {
            if options.dmOnly { return .load(home) }
            if options.followingOnly {
                let variant = queryItem("variant", in: url) ?? ""
                return ["following", "favorites"].contains(variant) ? .allow : .load(home)
            }
            return .allow
        }
        if options.hideReels {
            if path.hasPrefix("/reels/") { return .load(home) }
            // /<user>/reels/ is the profile's Reels tab; single /reel/<id>/ posts stay allowed.
            let parts = path.split(separator: "/")
            if parts.count == 2, parts[1] == "reels" {
                return .load(URL(string: "https://www.instagram.com/\(parts[0])/")!)
            }
        }
        if options.hideExplore, path.hasPrefix("/explore/people") { return .load(home) }
        return .allow
    }

    private static func x(_ url: URL, options: Options) -> Decision {
        let path = url.path().lowercased()
        if options.hideGrok, path == "/i/grok" || path.hasPrefix("/i/grok/") {
            return .load(home(for: .x, options: options))
        }
        return .allow
    }

    private static func queryItem(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}
