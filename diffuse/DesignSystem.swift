import SwiftUI
import AppKit

// MARK: - Design System Tokens

extension Color {
    // Dynamic Color helper for macOS
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return dark
            } else {
                return light
            }
        })
    }

    // Backgrounds
    static let bgCanvas = Color(.windowBackgroundColor)
    static let bgSubtle = Color(NSColor.controlBackgroundColor)
    static let bgInset = Color(NSColor.underPageBackgroundColor)
    static let bgSidebar = Color.dynamic(
        light: NSColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1.0),
        dark: NSColor(red: 0.075, green: 0.075, blue: 0.08, alpha: 1.0)
    )
    static let bgSidebarPanel = Color.dynamic(
        light: NSColor(red: 0.98, green: 0.985, blue: 0.995, alpha: 1.0),
        dark: NSColor(red: 0.13, green: 0.135, blue: 0.145, alpha: 1.0)
    )

    // Text
    static let textPrimary = Color(.labelColor)
    static let textSecondary = Color(.secondaryLabelColor)
    static let textTertiary = Color(.tertiaryLabelColor)

    // Borders
    static let borderDefault = Color(NSColor.separatorColor)
    static let borderMuted = Color(NSColor.separatorColor).opacity(0.5)

    // Accent
    static let accentBlue = Color(red: 0.18, green: 0.51, blue: 0.97)
    static let accentPurple = Color(red: 0.51, green: 0.31, blue: 0.87)

    // Status Colors (Dynamic)
    static let successColor = Color.dynamic(
        light: NSColor(red: 0.10, green: 0.50, blue: 0.22, alpha: 1.0),
        dark: NSColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1.0)
    )
    static let successBg = Color.dynamic(
        light: NSColor(red: 0.90, green: 0.98, blue: 0.92, alpha: 1.0),
        dark: NSColor(red: 0.06, green: 0.18, blue: 0.08, alpha: 1.0)
    )
    
    static let warningColor = Color.dynamic(
        light: NSColor(red: 0.60, green: 0.41, blue: 0.00, alpha: 1.0),
        dark: NSColor(red: 0.82, green: 0.60, blue: 0.13, alpha: 1.0)
    )
    static let warningBg = Color.dynamic(
        light: NSColor(red: 1.00, green: 0.97, blue: 0.77, alpha: 1.0),
        dark: NSColor(red: 0.18, green: 0.14, blue: 0.04, alpha: 1.0)
    )

    static let dangerColor = Color.dynamic(
        light: NSColor(red: 0.81, green: 0.13, blue: 0.18, alpha: 1.0),
        dark: NSColor(red: 0.97, green: 0.32, blue: 0.29, alpha: 1.0)
    )
    static let dangerBg = Color.dynamic(
        light: NSColor(red: 1.00, green: 0.92, blue: 0.91, alpha: 1.0),
        dark: NSColor(red: 0.18, green: 0.06, blue: 0.06, alpha: 1.0)
    )

    static let infoColor = Color.dynamic(
        light: NSColor(red: 0.04, green: 0.41, blue: 0.85, alpha: 1.0),
        dark: NSColor(red: 0.35, green: 0.65, blue: 1.00, alpha: 1.0)
    )
    static let infoBg = Color.dynamic(
        light: NSColor(red: 0.87, green: 0.96, blue: 1.00, alpha: 1.0),
        dark: NSColor(red: 0.05, green: 0.13, blue: 0.25, alpha: 1.0)
    )

    // Diff Colors (Dynamic)
    static let diffAddedBg = Color.dynamic(
        light: NSColor(red: 0.90, green: 0.98, blue: 0.92, alpha: 1.0),
        dark: NSColor(red: 0.06, green: 0.18, blue: 0.08, alpha: 1.0)
    )
    static let diffDeletedBg = Color.dynamic(
        light: NSColor(red: 1.00, green: 0.92, blue: 0.91, alpha: 1.0),
        dark: NSColor(red: 0.18, green: 0.06, blue: 0.06, alpha: 1.0)
    )
    static let diffAddedFg = Color.dynamic(
        light: NSColor(red: 0.10, green: 0.50, blue: 0.22, alpha: 1.0),
        dark: NSColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1.0)
    )
    static let diffDeletedFg = Color.dynamic(
        light: NSColor(red: 0.81, green: 0.13, blue: 0.18, alpha: 1.0),
        dark: NSColor(red: 0.97, green: 0.32, blue: 0.29, alpha: 1.0)
    )
}


// MARK: - Badge View

struct BadgeView: View {
    let text: String
    let variant: BadgeVariant

    var bgColor: Color {
        switch variant {
        case .danger: .dangerBg
        case .warning: .warningBg
        case .info: .infoBg
        case .success: .successBg
        case .neutral: Color(NSColor.controlColor)
        }
    }

    var fgColor: Color {
        switch variant {
        case .danger: .dangerColor
        case .warning: .warningColor
        case .info: .infoColor
        case .success: .successColor
        case .neutral: .textSecondary
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(fgColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(bgColor)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(fgColor.opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Panel View

struct Panel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderDefault, lineWidth: 0.5))
    }
}

// MARK: - Severity badge helper

extension Severity {
    var displayName: String { rawValue.capitalized }

    var badgeView: some View {
        BadgeView(text: displayName, variant: badgeColor)
    }
}

// MARK: - Loading Spinner

struct LoadingSpinner: View {
    var size: CGFloat = 16
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(Color.accentBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

// MARK: - Section Heading

struct SectionHeading: View {
    let icon: String
    let title: String
    let meta: String?

    init(_ title: String, icon: String, meta: String? = nil) {
        self.title = title
        self.icon = icon
        self.meta = meta
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.accentBlue)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
            if let meta {
                Spacer()
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(.bottom, 8)
    }
}
