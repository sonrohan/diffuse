import SwiftUI

@main
enum DiffuseMain {
    static func main() {
        if CommandLine.arguments.contains("--mcp-server") {
            Task {
                await MCPStdioServerService.run()
                exit(0)
            }
            dispatchMain()
        } else {
            diffuseApp.main()
        }
    }
}

// swift-format-ignore: TypeNamesShouldBeCapitalized
struct diffuseApp: App {
    @State private var appState = AppState()
    @AppStorage("appTheme") private var appTheme = "System"
    @AppStorage("defaultLanguage") private var defaultLanguage = "Auto Detect"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .environment(\.locale, currentLocale)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Analyze Local Repo…") {
                    NotificationCenter.default.post(name: .openAnalyzeRepo, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsSheet()
                .environment(appState)
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .environment(\.locale, currentLocale)
        }
    }

    private var currentLocale: Locale {
        switch defaultLanguage {
        case "English":
            return Locale(identifier: "en")
        case "Spanish (Español)":
            return Locale(identifier: "es")
        case "French (Français)":
            return Locale(identifier: "fr")
        case "Russian (Русский)":
            return Locale(identifier: "ru")
        default:
            return .current
        }
    }
}

extension Notification.Name {
    static let openAnalyzeRepo = Notification.Name("openAnalyzeRepo")
}
