import AppKit
import SwiftUI

// MARK: - Design System Tokens

extension Color {
    // Dynamic Color helper for macOS
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(
            NSColor(name: nil) { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return dark
                } else {
                    return light
                }
            })
    }

    // Backgrounds
    static let bgCanvas = Color.dynamic(
        light: NSColor(red: 0.985, green: 0.985, blue: 0.99, alpha: 1.0),
        dark: NSColor(red: 0.075, green: 0.075, blue: 0.08, alpha: 1.0)
    )
    static let bgSubtle = Color.dynamic(
        light: NSColor(red: 0.94, green: 0.945, blue: 0.955, alpha: 1.0),
        dark: NSColor(red: 0.095, green: 0.095, blue: 0.105, alpha: 1.0)
    )
    static let bgInset = Color(NSColor.underPageBackgroundColor)
    static let bgToolbar = Color.dynamic(
        light: NSColor(red: 0.965, green: 0.965, blue: 0.970, alpha: 1.0),
        dark: NSColor(red: 0.105, green: 0.105, blue: 0.112, alpha: 1.0)
    )
    static let bgSidebar = Color.dynamic(
        light: NSColor(red: 0.955, green: 0.955, blue: 0.960, alpha: 1.0),
        dark: NSColor(red: 0.115, green: 0.115, blue: 0.122, alpha: 1.0)
    )
    static let bgSidebarPanel = Color.dynamic(
        light: NSColor(red: 0.982, green: 0.982, blue: 0.986, alpha: 1.0),
        dark: NSColor(red: 0.155, green: 0.155, blue: 0.162, alpha: 1.0)
    )

    // Text
    static let textPrimary = Color(.labelColor)
    static let textSecondary = Color(.secondaryLabelColor)
    static let textTertiary = Color(.tertiaryLabelColor)

    // Borders
    static let borderDefault = Color(NSColor.separatorColor)
    static let borderMuted = Color(NSColor.separatorColor).opacity(0.5)

    // Accent
    static let accentBlue = Color.accentColor
    static let accentPurple = Color(red: 0.51, green: 0.31, blue: 0.87)

    // Status Colors (Dynamic)
    static let success = Color.dynamic(
        light: NSColor(red: 0.10, green: 0.50, blue: 0.22, alpha: 1.0),
        dark: NSColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1.0)
    )
    static let successBg = Color.dynamic(
        light: NSColor(red: 0.90, green: 0.98, blue: 0.92, alpha: 1.0),
        dark: NSColor(red: 0.06, green: 0.18, blue: 0.08, alpha: 1.0)
    )

    static let warning = Color.dynamic(
        light: NSColor(red: 0.60, green: 0.41, blue: 0.00, alpha: 1.0),
        dark: NSColor(red: 0.82, green: 0.60, blue: 0.13, alpha: 1.0)
    )
    static let warningBg = Color.dynamic(
        light: NSColor(red: 1.00, green: 0.97, blue: 0.77, alpha: 1.0),
        dark: NSColor(red: 0.18, green: 0.14, blue: 0.04, alpha: 1.0)
    )

    static let danger = Color.dynamic(
        light: NSColor(red: 0.81, green: 0.13, blue: 0.18, alpha: 1.0),
        dark: NSColor(red: 0.97, green: 0.32, blue: 0.29, alpha: 1.0)
    )
    static let dangerBg = Color.dynamic(
        light: NSColor(red: 1.00, green: 0.92, blue: 0.91, alpha: 1.0),
        dark: NSColor(red: 0.18, green: 0.06, blue: 0.06, alpha: 1.0)
    )

    static let info = Color.dynamic(
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
        case .danger: Color.danger
        case .warning: Color.warning
        case .info: Color.info
        case .success: Color.success
        case .neutral: .textSecondary
        }
    }

    var body: some View {
        Text(text)
            .font(.appBadge)
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
            .animation(
                .linear(duration: 0.8).repeatForever(autoreverses: false), value: isAnimating
            )
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
                .font(.appSubheadline)
                .foregroundColor(.accentBlue)
            Text(title)
                .font(.appHeading)
                .foregroundColor(.textPrimary)
            if let meta {
                Spacer()
                Text(meta)
                    .font(.appCaption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Semantic Typography Extensions

extension Font {
    /// Large title style for main headings
    public static let appLargeTitle = Font.title

    /// Standard section and panel headings
    public static let appHeading = Font.system(.body).weight(.semibold)

    /// Primary body text for content, tables, and lists
    public static let appBody = Font.body

    /// Highlighted or bold body text
    public static let appBodyBold = Font.body.weight(.semibold)

    /// Subtitles, descriptions, and secondary metadata text
    public static let appSubheadline = Font.subheadline

    /// Captions, help descriptions, and tertiary labels
    public static let appCaption = Font.caption

    /// Standard badges, tags, and chips typography
    public static let appBadge = Font.system(.caption2, design: .default).weight(.medium)

    /// Monospaced typography for SHAs, code snippets, and branch names
    public static func appMonospaced(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
