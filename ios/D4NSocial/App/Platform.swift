import Foundation

/// The sites the app wraps. Each has its own WebView, rule files and settings group.
enum Platform: String, CaseIterable, Identifiable, Codable {
    case instagram, x

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .x: "X"
        }
    }

    /// SF Symbol for the tab bar.
    var symbol: String {
        switch self {
        case .instagram: "camera"
        case .x: "xmark"
        }
    }

    /// Hosts that stay inside the WebView (the site plus its login and CDN
    /// domains). Anything else opens in a Safari sheet.
    var hosts: [String] {
        switch self {
        case .instagram: ["instagram.com", "facebook.com", "cdninstagram.com", "fbcdn.net"]
        case .x: ["x.com", "twitter.com", "twimg.com"]
        }
    }

    var origin: URL {
        switch self {
        case .instagram: URL(string: "https://www.instagram.com")!
        case .x: URL(string: "https://x.com")!
        }
    }
}
