import SwiftUI

enum RootTab: String, Hashable {
    case instagram, x, filters

    var platform: Platform? {
        switch self {
        case .instagram: .instagram
        case .x: .x
        case .filters: nil
        }
    }
}

/// Three tabs: the two sites and the Filters screen. Tapping the current
/// site's tab again goes home (or to the top of the home feed).
struct RootView: View {
    private let shell = Shell.shared
    // `-startTab filters` on launch opens that tab, for simulator screenshots.
    @State private var selected = RootTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .instagram

    var body: some View {
        TabView(selection: selection) {
            Tab(Platform.instagram.title, systemImage: Platform.instagram.symbol, value: RootTab.instagram) {
                WebTabView(tab: shell.tab(.instagram))
            }
            Tab(Platform.x.title, systemImage: Platform.x.symbol, value: RootTab.x) {
                WebTabView(tab: shell.tab(.x))
            }
            Tab("Filters", systemImage: "line.3.horizontal.decrease", value: RootTab.filters) {
                FiltersView()
            }
        }
    }

    private var selection: Binding<RootTab> {
        Binding(
            get: { selected },
            set: { next in
                if next == selected, let platform = next.platform { shell.tab(platform).goHome() }
                selected = next
            })
    }
}
