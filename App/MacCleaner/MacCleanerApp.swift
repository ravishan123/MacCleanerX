import SwiftUI

@main
struct MacCleanerApp: App {
    @State private var navigation = NavigationModel()
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup("Mac Cleaner") {
            RootView()
                .environment(navigation)
                .environment(app)
                .frame(minWidth: 1000, minHeight: 660)
                .tint(Theme.primary)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 760)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Smart Care") { navigation.selection = .smartCare }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Cleanup") { navigation.selection = .cleanup }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Activity Log") { navigation.showActivityLog() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { navigation.selection = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
