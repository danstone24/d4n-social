import SafariServices
import SwiftUI
import WebKit

struct WebTabView: View {
    @Bindable var tab: WebTab

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            WebViewRepresentable(webView: tab.webView)
            if let failed = tab.failed {
                VStack(spacing: 12) {
                    Text("Can't reach \(tab.platform.title)").font(.headline)
                    Text(failed).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Try again") { tab.reload() }.buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        }
        .sheet(item: $tab.external) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Links that leave the site open here, so the feed stays where it was.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
