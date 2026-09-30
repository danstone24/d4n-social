import Observation
import SafariServices
import SwiftUI
import WebKit

/// Owns one platform's WKWebView: user agent, injected rules, navigation
/// policy, the native bridge (settings down, hidden counts and block log up)
/// and the Safari sheet for links that leave the site.
@Observable
final class WebTab: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    struct ExternalLink: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    static let messageName = "d4n"

    let platform: Platform
    private(set) var failed: String?
    /// Set to open a link outside the site in a Safari sheet; the view clears it.
    var external: ExternalLink?

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let rules: RulesStore
    @ObservationIgnored private var urlObservation: NSKeyValueObservation?
    @ObservationIgnored private var recentBounces: [Date] = []
    /// True while a load the user started (a tap, a new window) is in flight,
    /// so a redirect it lands on may still open the Safari sheet.
    @ObservationIgnored private var userLoadPending = false

    init(platform: Platform, settings: Settings, rules: RulesStore) {
        self.platform = platform
        self.settings = settings
        self.rules = rules
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default() // persistent cookies: login survives relaunches
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        // Mobile Safari's suffix. Both sites otherwise treat the WebView as an
        // in-app browser and push their apps.
        let os = ProcessInfo.processInfo.operatingSystemVersion
        cfg.applicationNameForUserAgent = "Version/\(os.majorVersion).\(os.minorVersion) Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()

        webView.configuration.userContentController.add(WeakScriptHandler(self), name: Self.messageName)
        installScripts()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false // a long-press preview could show a blocked page
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.underPageBackgroundColor = .systemBackground
        #if DEBUG
        webView.isInspectable = true // Safari on the Mac > Develop > simulator > D4N Social
        #endif
        // Single-page route changes never reach the navigation delegate; the
        // URL does change, so police it here.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            self?.checkCurrentURL()
        }
        webView.load(URLRequest(url: home))
    }

    var home: URL { NavigationPolicy.home(for: platform, options: options) }

    private var options: NavigationPolicy.Options { NavigationPolicy.Options(settings: settings) }

    private func decide(_ url: URL) -> NavigationPolicy.Decision {
        NavigationPolicy.decide(url, platform: platform, options: options)
    }

    // MARK: Rules and settings bridge

    /// The rules run as one user script: a prelude with the platform, the
    /// current settings and the CSS, then the platform's content.js. Called
    /// again whenever settings or rule files change so the next page load
    /// starts from the latest values.
    func installScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let prelude: [String: Any] = [
            "platform": platform.rawValue,
            "settings": settings.snapshot(for: platform),
            "css": rules.style(for: platform),
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            "rulesVersion": rules.version,
        ]
        let source = "window.__d4n = \(Self.json(prelude));\n" + rules.script(for: platform)
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// Live update for the open page; `installScripts` covers the next load.
    func push(settings: Settings) {
        installScripts()
        let json = Self.json(settings.snapshot(for: platform))
        webView.evaluateJavaScript("window.__d4nApplySettings && window.__d4nApplySettings(\(json)); undefined;") { _, _ in }
    }

    private static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Undo a block from the block log, through the page's own API call.
    func unblock(_ handle: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.callAsyncJavaScript(
                "if (!window.__d4nUnblock) { throw new Error('X is not loaded'); } return await window.__d4nUnblock(handle);",
                arguments: ["handle": handle], in: nil, in: .page
            ) { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "stats":
            if let stats = body["stats"] as? [String: Int] { settings.stats[platform] = stats }
        case "blocklog":
            guard let handle = body["handle"] as? String else { return }
            if body["action"] as? String == "remove" { settings.removeBlock(handle) } else { settings.recordBlock(handle) }
        case "route":
            // The rules' click guard swallowed a tap on a blocked page.
            if let raw = body["url"] as? String, let url = URL(string: raw), case .load(let target) = decide(url) {
                bounce(to: target, limited: body["tap"] as? Bool != true)
            }
        default:
            break
        }
    }

    // MARK: Navigation

    func goHome() {
        if webView.url?.path() == home.path(), !webView.isLoading {
            webView.evaluateJavaScript("window.scrollTo({ top: 0, behavior: 'smooth' }); undefined;") { _, _ in }
        } else {
            webView.load(URLRequest(url: home))
        }
    }

    func reload() {
        failed = nil
        if webView.url == nil { webView.load(URLRequest(url: home)) } else { webView.reload() }
    }

    func checkCurrentURL() {
        if let url = webView.url, case .load(let target) = decide(url) {
            bounce(to: target, limited: true)
        }
    }

    /// `limited` bounces (not started by a tap) run at most three times in 20
    /// seconds so a redirect loop cannot reload forever.
    private func bounce(to target: URL, limited: Bool) {
        if limited {
            let now = Date()
            recentBounces = recentBounces.filter { now.timeIntervalSince($0) < 20 } + [now]
            guard recentBounces.count <= 3 else { return }
        }
        webView.load(URLRequest(url: target))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only top-level navigations are policed; frames and subresources load freely.
        guard action.targetFrame?.isMainFrame ?? true, let url = action.request.url else {
            return decisionHandler(.allow)
        }
        let tapped = action.navigationType == .linkActivated
        let newWindow = action.targetFrame == nil
        switch decide(url) {
        case .allow:
            if tapped && !newWindow {
                // Loading taps ourselves stops iOS handing instagram.com and
                // x.com links to the native apps as universal links.
                userLoadPending = true
                webView.load(action.request)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        case .load(let target):
            bounce(to: target, limited: !tapped)
            decisionHandler(.cancel)
        case .external(let link):
            if tapped || newWindow || userLoadPending { external = ExternalLink(url: link) }
            decisionHandler(.cancel)
        case .deny:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failed = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        userLoadPending = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { note(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { note(error) }

    private func note(_ error: Error) {
        userLoadPending = false
        let error = error as NSError
        // Our own cancels, and the sites' single-page navigation, are not connectivity problems.
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain" && error.code == 102 { return }
        failed = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.load(URLRequest(url: home)) // otherwise a blank screen
    }

    // MARK: WKUIDelegate

    /// target="_blank" and window.open: there is one view per site, so allowed pages load in it.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        switch decide(url) {
        case .allow:
            userLoadPending = true
            webView.load(action.request)
        case .load(let target):
            bounce(to: target, limited: false)
        case .external(let link):
            external = ExternalLink(url: link)
        case .deny:
            break
        }
        return nil
    }

    // WKWebView drops alert() and confirm() unless these exist; Instagram uses confirm().
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        present(message, cancellable: false) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        present(message, cancellable: true, completion: completionHandler)
    }

    private func present(_ message: String, cancellable: Bool, completion: @escaping (Bool) -> Void) {
        guard var top = webView.window?.rootViewController else { return completion(false) }
        while let next = top.presentedViewController { top = next }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        if cancellable {
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion(true) })
        top.present(alert, animated: true)
    }
}

/// WebKit retains its message handlers; this keeps the tab out of that cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// One tab per platform, created once and kept warm so switching is instant.
@Observable
final class Shell {
    static let shared = Shell()

    let tabs: [Platform: WebTab]

    init(settings: Settings = .shared, rules: RulesStore = .shared) {
        var tabs: [Platform: WebTab] = [:]
        for platform in Platform.allCases {
            tabs[platform] = WebTab(platform: platform, settings: settings, rules: rules)
        }
        self.tabs = tabs
        settings.listeners.append { [weak self] settings in
            self?.tabs.values.forEach { $0.push(settings: settings) }
        }
        rules.onUpdate = { [weak self] in
            self?.tabs.values.forEach { $0.installScripts() }
        }
        Task { await rules.refresh() }
    }

    func tab(_ platform: Platform) -> WebTab { tabs[platform]! }
}
