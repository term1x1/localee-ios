import SwiftUI

@main
struct LocaleeApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var gam = Gamification()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(gam)
                .task { await store.boot() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if store.booting {
                ProgressView().tint(Theme.accent)
            } else if store.user == nil {
                AuthView()
            } else {
                MainTabs()
            }
        }
    }
}
