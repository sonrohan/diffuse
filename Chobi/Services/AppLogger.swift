import Foundation
import SwiftUI

struct LogEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let tag: String
    let message: String

    nonisolated init(
        id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel = .info, tag: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.tag = tag
        self.message = message
    }
}

enum LogLevel: String, Codable, CaseIterable, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    var color: Color {
        switch self {
        case .info: .textPrimary
        case .warning: .warning
        case .error: .danger
        }
    }
}

@Observable
class AppLogger {
    nonisolated static let shared = AppLogger()

    @MainActor var entries: [LogEntry] = []

    nonisolated func log(_ message: String, level: LogLevel = .info, tag: String = "General") {
        let entry = LogEntry(level: level, tag: tag, message: message)

        // Print immediately to standard console
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeStr = formatter.string(from: entry.timestamp)
        print("[\(timeStr)] [\(level.rawValue)] [\(tag)] \(message)")

        Task { @MainActor in
            AppLogger.shared.entries.append(entry)
            if AppLogger.shared.entries.count > 1000 {
                AppLogger.shared.entries.removeFirst(AppLogger.shared.entries.count - 1000)
            }
        }
    }

    @MainActor func clear() {
        entries.removeAll()
    }
}
