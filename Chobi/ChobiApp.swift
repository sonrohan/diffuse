import SwiftUI

@main
enum ChobiMain {
    static func main() {
        if CommandLine.arguments.contains("--mcp-server") {
            Task {
                await MCPStdioServerService.run()
                exit(0)
            }
            dispatchMain()
        } else {
            ChobiApp.main()
        }
    }
}

struct ChobiApp: App {
    @State private var appState = AppState()
    @AppStorage("appTheme") private var appTheme = "System"
    @AppStorage("defaultLanguage") private var defaultLanguage = "Auto Detect"
    @AppStorage("uiZoomScale") private var zoomScale = 1.0

    private let zoomLevels: [Double] = [
        0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.2, 1.25, 1.5, 1.75, 2.0,
    ]

    private func zoomIn() {
        if let next = zoomLevels.first(where: { $0 > zoomScale + 0.01 }) {
            zoomScale = next
        }
    }

    private func zoomOut() {
        if let prev = zoomLevels.last(where: { $0 < zoomScale - 0.01 }) {
            zoomScale = prev
        }
    }

    private func resetZoom() {
        zoomScale = 1.0
    }

    var body: some Scene {
        WindowGroup {
            ZoomContainer {
                ContentView()
                    .environment(appState)
                    .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                    .environment(\.locale, currentLocale)
            }
            .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Zoom In") {
                    zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Analyze Local Repo…") {
                    NotificationCenter.default.post(name: .openAnalyzeRepo, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Debug") {
                Button("Review Debug…") {
                    NotificationCenter.default.post(name: .openDebugMenu, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .disabled(appState.selectedRepo == nil || appState.analysisDetails == nil)
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
    static let openDebugMenu = Notification.Name("openDebugMenu")
}
