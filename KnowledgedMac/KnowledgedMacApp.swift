import SwiftUI

@main
struct KnowledgedMacApp: App {
    @StateObject private var settings  = AppSettings()
    @StateObject private var client:   KnowledgedClient
    @StateObject private var navState  = NavigationState()

    init() {
        // Build settings first so the client can hold a reference to it.
        let s = AppSettings()
        _settings = StateObject(wrappedValue: s)
        _client   = StateObject(wrappedValue: KnowledgedClient(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(client)
                .environmentObject(navState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 680, idealWidth: 860, minHeight: 480, idealHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        // Suppress the default "New Window" menu item — single-window app.
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // System Preferences / Settings (⌘,)
        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(client)
                .preferredColorScheme(.dark)
        }
    }
}
