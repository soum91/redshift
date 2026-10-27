import SwiftUI
import AppIntents

@main
struct RedshiftApp: App {
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


/// Assign the desired learned IR button once in Shortcuts, then pin its
/// Shortcut to Control Center for a real visible control.
struct RedshiftShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .red

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SendIRButtonIntent(), phrases: [
            "Send remote button with \(.applicationName)",
        ], shortTitle: "Remote Button", systemImageName: "av.remote.fill")
    }
}
