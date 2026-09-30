import SwiftUI

@main
struct D4NSocialApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Do not resume on a page the rules bounce away from.
            if phase == .active { Shell.shared.tabs.values.forEach { $0.checkCurrentURL() } }
        }
    }
}
