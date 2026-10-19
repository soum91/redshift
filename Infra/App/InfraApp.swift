import SwiftUI

@main
struct InfraApp: App {
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: phase) { _, p in
                    switch p {
                    case .active: store.connect()
                    case .background: store.disconnect()
                    default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if store.config.isReady {
                MainView()
            } else {
                SetupView()
            }
        }
        .animation(.easeInOut, value: store.config.isReady)
    }
}
