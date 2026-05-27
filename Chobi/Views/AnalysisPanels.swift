import SwiftUI

// MARK: - Review Map Panel

struct AnalysisNavigationRail: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let details: AnalysisDetails

    var visibleTargets: [ReviewTarget] {
        Array(viewModel.bucketTargets.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailSectionHeader(
                title: "Review Scope",
                count: nil,
                help:
                    "Choose the set of files shown in the review. Areas are focused scopes; targets below are jumps inside the selected scope."
            )

            AllChangesNavRow(
                fileCount: details.files.count,
                isSelected: viewModel.selectedBucketId == nil
                    && !viewModel.isLowerSignalViewSelected
                    && !viewModel.isNeedsAttentionViewSelected
            ) {
                viewModel.selectAllChanges()
            }

            if !details.reviewTargets.isEmpty {
                NeedsAttentionNavRow(
                    fileCount: Set(details.reviewTargets.map(\.filePath)).count,
                    severitySummary: details.reviewTargets.severitySummary,
                    isSelected: viewModel.isNeedsAttentionViewSelected
                ) {
                    viewModel.selectNeedsAttentionChanges()
                }
            }

            if !details.skimTargets.isEmpty {
                LowerSignalNavRow(
                    fileCount: details.skimTargets.count,
                    isSelected: viewModel.isLowerSignalViewSelected
                ) {
                    viewModel.selectLowerSignalChanges()
                }
            }

            RailSectionHeader(
                title: "Areas",
                count: details.changeBuckets.count,
                help:
                    "Files grouped by the kind of work they represent, so you can review related changes together."
            )

            if details.changeBuckets.isEmpty {
                RailEmptyRow(icon: "tray", text: "No grouped areas")
            } else {
                VStack(spacing: 2) {
                    ForEach(details.changeBuckets) { bucket in
                        AreaNavRow(
                            bucket: bucket,
                            targetCount: details.reviewTargets.filter {
                                bucket.files.contains($0.filePath)
                            }.count,
                            isSelected: viewModel.selectedBucketId == bucket.id
                        ) {
                            viewModel.selectBucket(bucket.id)
                        }
                    }
                }
            }

            RailSectionHeader(
                title: "In This View",
                count: viewModel.bucketTargets.count,
                help:
                    "Concrete review entry points inside the selected scope, ordered by severity and analyzer confidence."
            )

            if viewModel.bucketTargets.isEmpty {
                RailEmptyRow(icon: "checkmark.seal", text: "No targets in this view")
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(visibleTargets.enumerated()), id: \.element.id) { index, target in
                        TargetNavRow(target: target, index: index)
                    }
                    if viewModel.bucketTargets.count > visibleTargets.count {
                        RailMoreRow(
                            text:
                                "\(viewModel.bucketTargets.count - visibleTargets.count) more targets in this view"
                        )
                    }
                }
            }
        }
    }
}

struct RailSectionHeader: View {
    let title: String
    let count: Int?
    var help: String? = nil
    @State private var isShowingHelp = false

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .kerning(0.5)
            if let help {
                Button {
                    isShowingHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help)
                .popover(isPresented: $isShowingHelp, arrowEdge: .trailing) {
                    Text(help)
                        .font(.system(size: 12))
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 220, alignment: .leading)
                        .padding(12)
                        .background(Color.bgCanvas)
                }
            }
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }
}

struct AllChangesNavRow: View {
    let fileCount: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .accentBlue : .textSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("All Changes")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text("Unfiltered")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accentBlue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentBlue.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    Text(fileCount == 1 ? "1 file" : "\(fileCount) files")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isSelected ? Color.accentBlue.opacity(0.55) : Color.borderMuted,
                    lineWidth: isSelected ? 1 : 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentBlue.opacity(0.10) }
        if isHovered { return Color(NSColor.controlColor).opacity(0.55) }
        return Color.clear
    }
}

struct LowerSignalNavRow: View {
    let fileCount: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .accentBlue : .textSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Low-Signal / Skim")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(fileCount == 1 ? "1 file" : "\(fileCount) files")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isSelected ? Color.accentBlue.opacity(0.55) : Color.borderMuted,
                    lineWidth: isSelected ? 1 : 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(
            "Configuration, documentation, generated, or boilerplate files that are usually safe to skim."
        )
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentBlue.opacity(0.10) }
        if isHovered { return Color(NSColor.controlColor).opacity(0.55) }
        return Color.clear
    }
}

struct NeedsAttentionNavRow: View {
    let fileCount: Int
    let severitySummary: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .accentBlue : .textSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Needs Attention")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(
                        "\(severitySummary) across \(fileCount) \(fileCount == 1 ? "file" : "files")"
                    )
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isSelected ? Color.accentBlue.opacity(0.55) : Color.borderMuted,
                    lineWidth: isSelected ? 1 : 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Files with concrete analyzer targets: \(severitySummary).")
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentBlue.opacity(0.10) }
        if isHovered { return Color(NSColor.controlColor).opacity(0.55) }
        return Color.clear
    }
}

struct SignalNavRow: View {
    let signal: RiskHighlight
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    signal.severity.badgeView
                    Text(
                        signal.category.rawValue.replacingOccurrences(of: "-", with: " ")
                            .capitalized
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                    Spacer()
                }

                Text(signal.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Text(signal.filePath + (signal.lineStart.map { ":L\($0)" } ?? ""))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.accentBlue)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isHovered ? Color(NSColor.controlColor).opacity(0.55) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct AreaNavRow: View {
    let bucket: ChangeBucket
    let targetCount: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: bucket.type.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .accentBlue : .textSecondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(bucket.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    Text(areaMetadata)
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isSelected ? Color.accentBlue.opacity(0.55) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentBlue.opacity(0.10) }
        if isHovered { return Color(NSColor.controlColor).opacity(0.55) }
        return Color.clear
    }

    private var areaMetadata: String {
        let files = bucket.files.count == 1 ? "1 file" : "\(bucket.files.count) files"
        guard targetCount > 0 else { return files }
        let targets = targetCount == 1 ? "1 target" : "\(targetCount) targets"
        return "\(files) · \(targets)"
    }
}

struct TargetNavRow: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let target: ReviewTarget
    let index: Int
    @State private var isHovered = false

    var body: some View {
        Button {
            viewModel.toggleTarget(target)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    target.severity.badgeView
                    Text("#\(index + 1)")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                    Spacer()
                }
                Text(target.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                Text(target.filePath + (target.lineStart.map { ":L\($0)" } ?? ""))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !target.evidence.isEmpty {
                    Text(target.evidence)
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isSelected ? Color.accentBlue.opacity(0.55) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(target.changedFileId == nil)
        .onHover { isHovered = $0 }
    }

    private var isSelected: Bool {
        viewModel.activeTargetId == target.id
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentBlue.opacity(0.10) }
        if isHovered { return Color(NSColor.controlColor).opacity(0.55) }
        return Color.clear
    }
}

struct RailEmptyRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }
}

struct RailMoreRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }
}

struct ReviewMapPanel: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let details: AnalysisDetails

    var topSignals: [RiskHighlight] {
        details.riskHighlights
            .filter { $0.severity >= .medium }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 13))
                        .foregroundColor(.accentBlue)
                    Text("Review Map")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(topSignals.count) priority signal\(topSignals.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }

                if topSignals.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.success)
                        Text("No priority signals detected by configured rules.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.controlColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 6) {
                        ForEach(topSignals) { signal in
                            SignalCard(signal: signal) {
                                viewModel.jumpToHighlight(signal)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct SignalCard: View {
    let signal: RiskHighlight
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    signal.severity.badgeView
                    Text(
                        signal.category.rawValue.replacingOccurrences(of: "-", with: " ")
                            .capitalized
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                }
                Text(signal.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                    Text(signal.filePath + (signal.lineStart.map { ":L\($0)" } ?? ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.accentBlue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentBlue.opacity(0.06) : Color(NSColor.controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isHovered ? Color.accentBlue.opacity(0.3) : Color.borderMuted, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Semantic Buckets Panel (Change Buckets)

struct SemanticBucketsPanel: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let details: AnalysisDetails

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.accentBlue)
                    Text("Semantic Views")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(
                        "\(details.changeBuckets.count) area\(details.changeBuckets.count == 1 ? "" : "s")"
                    )
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                }

                VStack(spacing: 6) {
                    AllChangesCard(
                        fileCount: details.files.count,
                        signalCount: details.riskHighlights.filter { $0.severity >= .medium }.count,
                        isSelected: viewModel.selectedBucketId == nil
                            && !viewModel.isLowerSignalViewSelected
                            && !viewModel.isNeedsAttentionViewSelected
                    ) {
                        viewModel.selectAllChanges()
                    }

                    ForEach(details.changeBuckets) { bucket in
                        BucketCard(
                            bucket: bucket,
                            highlights: details.riskHighlights.filter { $0.bucketId == bucket.id },
                            isSelected: viewModel.selectedBucketId == bucket.id
                        ) {
                            viewModel.selectBucket(bucket.id)
                        }
                    }
                }

                if details.changeBuckets.isEmpty {
                    Text("No change buckets available.")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(12)
        }
    }
}

struct AllChangesCard: View {
    let fileCount: Int
    let signalCount: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("All Changes", systemImage: "rectangle.stack")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("Unfiltered")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentBlue.opacity(0.10))
                        .clipShape(Capsule())
                }

                Text("Every changed file in this PR.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(fileCount) files", systemImage: "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                    Label("\(signalCount) signals", systemImage: "exclamationmark.shield")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentBlue.opacity(0.08)
                    : (isHovered
                        ? Color(NSColor.controlColor).opacity(0.8)
                        : Color(NSColor.controlColor).opacity(0.4))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.accentBlue.opacity(0.6) : Color.borderMuted,
                        lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

struct BucketCard: View {
    let bucket: ChangeBucket
    let highlights: [RiskHighlight]
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var primarySignal: RiskHighlight? { highlights.first }
    var prioritySignalCount: Int { highlights.filter { $0.severity >= .medium }.count }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    BadgeView(
                        text: bucket.riskLevel.displayName, variant: bucket.riskLevel.badgeColor)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: bucket.type.icon)
                            .font(.system(size: 10))
                            .foregroundColor(.textTertiary)
                        Text("#\(bucket.reviewOrder)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(bucket.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(bucket.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label("\(bucket.files.count) files", systemImage: "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                    Label("\(prioritySignalCount) signals", systemImage: "exclamationmark.shield")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }

                if let signal = primarySignal {
                    Divider()
                    Text(signal.title)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentBlue.opacity(0.08)
                    : (isHovered
                        ? Color(NSColor.controlColor).opacity(0.8)
                        : Color(NSColor.controlColor).opacity(0.4))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.accentBlue.opacity(0.6) : Color.borderMuted,
                        lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Review Targets Panel

struct ReviewTargetsPanel: View {
    let targets: [ReviewTarget]

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(
                    "Selected View Targets", icon: "shield.lefthalf.filled",
                    meta: "\(targets.count) target\(targets.count == 1 ? "" : "s")")

                if targets.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No high-priority targets")
                                .font(.system(size: 12, weight: .medium))
                            Text("No priority signals detected by configured rules for this view.")
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(targets.enumerated()), id: \.element.id) { idx, target in
                            ReviewTargetCard(target: target, index: idx)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct ReviewTargetCard: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let target: ReviewTarget
    let index: Int

    var borderColor: Color {
        switch target.severity {
        case .high: .danger
        case .medium: .warning
        case .low: .info
        case .info: .borderDefault
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        target.severity.badgeView
                        Text("#\(index + 1)")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Text("via \(target.source)")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }
                    Text(target.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(3)
                }
                Spacer()
                if target.changedFileId != nil {
                    Button {
                        viewModel.toggleTarget(target)
                    } label: {
                        Label(
                            viewModel.activeTargetId == target.id ? "Clear" : "View diff",
                            systemImage: viewModel.activeTargetId == target.id
                                ? "xmark" : "arrow.right"
                        )
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                    Text(
                        target.filePath
                            + (target.lineStart.map { " · L\($0)–\(target.lineEnd ?? $0)" } ?? "")
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                if !target.evidence.isEmpty {
                    Text(target.evidence)
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(3)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(Color.bgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    viewModel.activeTargetId == target.id
                        ? Color.warning.opacity(0.65) : Color.borderMuted,
                    lineWidth: viewModel.activeTargetId == target.id ? 1.5 : 0.5)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(borderColor)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
    }
}

// MARK: - Safe to Skim Panel

struct SafeToSkimPanel: View {
    let targets: [SkimTarget]
    @State private var isExpanded = false

    var grouped: [ChangedFile.FileClassification: [SkimTarget]] {
        Dictionary(grouping: targets, by: { $0.classification })
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                        Text("Lower-Signal Changes")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(targets.count) file\(targets.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(12)

                if !isExpanded && !targets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(
                                grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self
                            ) { cls in
                                let items = grouped[cls]!
                                BadgeView(
                                    text: "\(items.count) \(items[0].groupName)", variant: .neutral)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                }

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self)
                        { cls in
                            let items = grouped[cls]!
                            VStack(alignment: .leading, spacing: 4) {
                                Text(items[0].groupName.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                                    .kerning(0.5)

                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) {
                                        idx, item in
                                        HStack {
                                            Image(systemName: "doc.text")
                                                .font(.system(size: 10))
                                                .foregroundColor(.textTertiary)
                                            Text(item.filePath)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.textPrimary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Text("+\(item.additions) −\(item.deletions)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.textTertiary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        if idx < items.count - 1 { Divider() }
                                    }
                                }
                                .background(Color(NSColor.controlColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6).stroke(
                                        Color.borderMuted, lineWidth: 0.5))
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

// MARK: - Selected Context Bar

struct SelectedContextBar: View {
    @Environment(AnalysisViewModel.self) private var viewModel
    let details: AnalysisDetails

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.isNavigationRailCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(
                        viewModel.isNavigationRailCollapsed ? .accentBlue : .textSecondary
                    )
                    .frame(width: 26, height: 22)
                    .background(
                        viewModel.isNavigationRailCollapsed
                            ? Color.accentBlue.opacity(0.10)
                            : Color(NSColor.controlColor).opacity(0.45)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(
                                viewModel.isNavigationRailCollapsed
                                    ? Color.accentBlue.opacity(0.35) : Color.borderMuted,
                                lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help(
                viewModel.isNavigationRailCollapsed
                    ? "Show review navigation" : "Hide review navigation"
            )
            .padding(.trailing, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("REVIEW SCOPE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .kerning(0.5)
                Text(viewModel.selectedReviewScopeTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(viewModel.selectedReviewScopeSubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }
            Spacer()

            HStack(spacing: 7) {
                ContextStatChip(icon: "doc.text.fill", text: "\(viewModel.bucketFiles.count) files")
                if viewModel.selectedScopeSignalCount > 0 {
                    ContextStatChip(
                        icon: "exclamationmark.shield.fill",
                        text: "\(viewModel.selectedScopeSignalCount) signals")
                }
                if viewModel.bucketTargets.count > 0 {
                    ContextStatChip(
                        icon: "target", text: "\(viewModel.bucketTargets.count) targets")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.bgSubtle)
    }
}

// MARK: - Review Debug Sheet

struct ReviewDebugSheet: View {
    let details: AnalysisDetails
    let repo: GitRepository
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ReviewDebugTab = .ast

    private var profile: AnalysisProfile {
        AnalysisProfileStore.load(repoPath: repo.path)
    }

    private var profileSource: String {
        AnalysisProfileStore.hasRepoProfile(repoPath: repo.path)
            ? "Repo-defined .diffuse.json"
            : "Built-in \(AnalysisProfileStore.detectBuiltInProfileId(repoPath: repo.path))"
    }

    private var symbolsByPath: [(path: String, symbols: [ChangedSymbol])] {
        let filesById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0.path) })
        return Dictionary(
            grouping: details.symbols,
            by: { filesById[$0.changedFileId] ?? $0.metadata["file_path"] ?? "unknown" }
        )
        .map {
            (
                $0.key,
                $0.value.sorted { lhs, rhs in
                    if lhs.startLine != rhs.startLine { return lhs.startLine < rhs.startLine }
                    return lhs.name < rhs.name
                }
            )
        }
        .sorted { $0.path < $1.path }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "ladybug")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Debug")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("\(repo.name) · \(profile.displayName) · \(profileSource)")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            Picker("Debug view", selection: $selectedTab) {
                ForEach(ReviewDebugTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedTab {
                    case .ast:
                        astBreakdown
                    case .mapping:
                        mappingBreakdown
                    case .performance:
                        performanceBreakdown
                    }
                }
                .padding(14)
            }
            .background(Color.bgCanvas)
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 620, idealHeight: 720)
    }

    private var astBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            DebugMetricStrip(metrics: [
                ("Files", "\(details.files.count)"),
                ("AST symbols", "\(details.symbols.count)"),
                ("Findings", "\(details.findings.count)"),
                ("Targets", "\(details.reviewTargets.count)"),
            ])

            if symbolsByPath.isEmpty {
                DebugEmptyState(text: "No AST symbols were extracted for this analysis.")
            } else {
                ForEach(symbolsByPath, id: \.path) { group in
                    DebugSection(
                        title: group.path,
                        meta: "\(group.symbols.count) symbol\(group.symbols.count == 1 ? "" : "s")"
                    ) {
                        VStack(spacing: 8) {
                            ForEach(group.symbols) { symbol in
                                DebugSymbolCard(symbol: symbol)
                            }
                        }
                    }
                }
            }
        }
    }

    private var mappingBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            DebugSection(title: "Profile", meta: profile.id) {
                VStack(alignment: .leading, spacing: 6) {
                    DebugKeyValueRow(label: "Display name", value: profile.displayName)
                    DebugKeyValueRow(label: "Source", value: profileSource)
                    DebugKeyValueRow(
                        label: "File rules", value: "\(profile.fileClassifications.count)")
                    DebugKeyValueRow(label: "Bucket rules", value: "\(profile.buckets.count)")
                    DebugKeyValueRow(label: "Symbol groups", value: "\(profile.symbolGroups.count)")
                    DebugKeyValueRow(
                        label: "Semantic highlights", value: "\(profile.semanticHighlights.count)")
                    DebugKeyValueRow(
                        label: "AST findings",
                        value:
                            "\(profile.rules.semanticAreaFindings.count + profile.rules.contractFindings.count)"
                    )
                }
            }

            ForEach(details.files.sorted { $0.path < $1.path }) { file in
                DebugFileMappingCard(file: file, details: details, profile: profile)
            }
        }
    }

    private var performanceBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let metrics = state.coordinator.lastRunMetrics {
                // Headline Metric
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOTAL ANALYSIS TIME")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .kerning(0.5)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.3f", metrics.totalTime))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentBlue)
                        Text("seconds")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))

                // Phase Durations
                DebugSection(title: "Analysis Pipeline Breakdown", meta: "duration of each stage") {
                    VStack(spacing: 0) {
                        PerformanceStepRow(
                            label: "Git Gather Diff",
                            duration: metrics.gitGatherDiffTime,
                            meta: "Discovered changes from base Sha",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "Diff Parsing",
                            duration: metrics.diffParsingTime,
                            meta: "Parsed \(metrics.changedFilesCount) changed files",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "AST Parse Changed Symbols",
                            duration: metrics.astParseTime,
                            meta: "Extracted \(metrics.symbolsCount) symbols from changed files",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "AST Base/Head Comparison",
                            duration: metrics.astCompareTime,
                            meta: "Computed contract-deltas & behavioral updates",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "Call Graph Indexing",
                            duration: metrics.astCallGraphTime,
                            meta:
                                "Indexed \(metrics.indexedFilesCount) / \(metrics.trackedFilesCount) matching tracked files",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "Rules Engine Execution",
                            duration: metrics.rulesEngineTime,
                            meta: "Evaluated deterministic rules & calculated risk score",
                            total: metrics.totalTime
                        )
                        Divider()
                        PerformanceStepRow(
                            label: "Triage Engine Derivation",
                            duration: metrics.triageEngineTime,
                            meta: "Categorized change buckets & derived review targets",
                            total: metrics.totalTime
                        )
                    }
                    .background(Color(NSColor.controlColor).opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.system(size: 32))
                        .foregroundColor(.textTertiary)
                    Text("No Performance Data")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Trigger an analysis reload or select another commit to populate timings.")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }
}

private enum ReviewDebugTab: String, CaseIterable, Identifiable {
    case ast
    case mapping
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ast: "Raw AST"
        case .mapping: "Profile Mapping"
        case .performance: "Performance"
        }
    }
}

private struct PerformanceStepRow: View {
    let label: String
    let duration: Double
    let meta: String
    let total: Double

    var percentage: Double {
        total > 0 ? (duration / total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(String(format: "%.3fs", duration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }

            HStack(spacing: 8) {
                // Modern, beautiful progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.borderMuted.opacity(0.4))
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.accentBlue)
                            .frame(width: geo.size.width * CGFloat(percentage), height: 4)
                    }
                }
                .frame(height: 4)

                Text(String(format: "%.0f%%", percentage * 100))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.textTertiary)
                    .frame(width: 28, alignment: .trailing)
            }

            Text(meta)
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
        }
        .padding(10)
    }
}

private struct DebugMetricStrip: View {
    let metrics: [(String, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(metrics, id: \.0) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.0.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.textTertiary)
                    Text(metric.1)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7).stroke(Color.borderMuted, lineWidth: 0.5))
            }
        }
    }
}

private struct DebugSection<Content: View>: View {
    let title: String
    let meta: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let meta {
                    Text(meta)
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
            }
            content()
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
    }
}

private struct DebugSymbolCard: View {
    let symbol: ChangedSymbol

    private var metadataRows: [(String, String)] {
        symbol.metadata
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BadgeView(text: symbol.kind.rawValue, variant: .neutral)
                Text(symbol.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("L\(symbol.startLine)-\(symbol.endLine)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textTertiary)
            }

            HStack(spacing: 12) {
                DebugInlineValue(label: "semantic_type", value: symbol.semanticType)
                DebugInlineValue(label: "area", value: symbol.metadata["semantic_area"] ?? "none")
                DebugInlineValue(label: "language", value: symbol.metadata["language"] ?? "unknown")
            }

            if !symbol.callees.isEmpty || !symbol.callers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !symbol.callees.isEmpty {
                        DebugKeyValueRow(
                            label: "Callees", value: symbol.callees.joined(separator: ", "))
                    }
                    if !symbol.callers.isEmpty {
                        DebugKeyValueRow(
                            label: "Callers", value: symbol.callers.joined(separator: ", "))
                    }
                }
            }

            if !metadataRows.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(metadataRows, id: \.0) { row in
                        DebugInlineValue(label: row.0, value: row.1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct DebugFileMappingCard: View {
    let file: ChangedFile
    let details: AnalysisDetails
    let profile: AnalysisProfile

    private var symbols: [ChangedSymbol] {
        details.symbols
            .filter { $0.changedFileId == file.id }
            .sorted { lhs, rhs in
                if lhs.startLine != rhs.startLine { return lhs.startLine < rhs.startLine }
                return lhs.name < rhs.name
            }
    }

    private var findings: [Finding] {
        details.findings.filter { $0.changedFileId == file.id }
    }

    private var bucketRule: BucketRule? {
        profile.bucketRule(for: file, findings: findings, symbols: symbols)
    }

    var body: some View {
        DebugSection(
            title: file.path, meta: "\(symbols.count) AST symbol\(symbols.count == 1 ? "" : "s")"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                DebugKeyValueRow(
                    label: "File classification",
                    value: "\(file.classification.rawValue) via \(classificationRuleLabel)")
                DebugKeyValueRow(
                    label: "Bucket rule",
                    value: bucketRule.map { "\($0.id) → \($0.title)" } ?? "No matching bucket rule")
                DebugKeyValueRow(
                    label: "Findings",
                    value: findings.isEmpty
                        ? "none"
                        : findings.map { "\($0.ruleSource) (\($0.severity.rawValue))" }.joined(
                            separator: ", "))

                if symbols.isEmpty {
                    DebugEmptyState(
                        text: "No AST symbols for this file; profile mapping is file-only.")
                } else {
                    VStack(spacing: 7) {
                        ForEach(symbols) { symbol in
                            DebugSymbolMappingRow(symbol: symbol, file: file, profile: profile)
                        }
                    }
                }
            }
        }
    }

    private var classificationRuleLabel: String {
        profile.fileClassifications.first { $0.matches(path: file.path) }
            .map { "\($0.classification) path rule" } ?? "default source"
    }
}

private struct DebugSymbolMappingRow: View {
    let symbol: ChangedSymbol
    let file: ChangedFile
    let profile: AnalysisProfile

    private var groupMatches: [String] {
        profile.symbolGroups
            .filter { $0.matches(symbol) }
            .map(\.id)
    }

    private var highlightMatches: [String] {
        profile.semanticHighlights
            .filter { $0.debugMatches(symbol: symbol, path: file.path) }
            .map(\.id)
    }

    private var semanticFindingMatches: [String] {
        profile.rules.semanticAreaFindings
            .filter { $0.debugMatches(symbol: symbol, path: file.path) }
            .map(\.id)
    }

    private var contractFindingMatches: [String] {
        profile.rules.contractFindings
            .filter { rule in
                rule.metadataEquals.allSatisfy { symbol.metadata[$0.key] == $0.value }
            }
            .map(\.id)
    }

    private var bucketMatches: [String] {
        profile.buckets
            .filter { $0.matches(file: file, findings: [], symbols: [symbol]) }
            .map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(symbol.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(symbol.semanticType)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textTertiary)
                Spacer()
                Text("L\(symbol.startLine)-\(symbol.endLine)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textTertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], alignment: .leading,
                spacing: 6
            ) {
                DebugInlineValue(label: "symbol groups", value: debugList(groupMatches))
                DebugInlineValue(label: "bucket rules", value: debugList(bucketMatches))
                DebugInlineValue(label: "semantic highlights", value: debugList(highlightMatches))
                DebugInlineValue(
                    label: "semantic findings", value: debugList(semanticFindingMatches))
                DebugInlineValue(
                    label: "contract findings", value: debugList(contractFindingMatches))
            }
        }
        .padding(9)
        .background(Color(NSColor.controlColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func debugList(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: ", ")
    }
}

private struct DebugInlineValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.textTertiary)
                .lineLimit(1)
            Text(value.isEmpty ? "empty" : value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DebugKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.textTertiary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct DebugEmptyState: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .foregroundColor(.textTertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

extension SemanticHighlightRule {
    fileprivate func debugMatches(symbol: ChangedSymbol, path: String) -> Bool {
        if let semanticArea, symbol.metadata["semantic_area"] != semanticArea { return false }
        if let metadataEquals, !metadataEquals.allSatisfy({ symbol.metadata[$0.key] == $0.value }) {
            return false
        }
        if let paths, !PatternMatcher.matchesAny(path, patterns: paths) { return false }
        if let symbolNames, !PatternMatcher.matchesAny(symbol.name, patterns: symbolNames) {
            return false
        }
        return semanticArea != nil || metadataEquals != nil || paths != nil || symbolNames != nil
    }
}

extension SemanticAreaFindingRule {
    fileprivate func debugMatches(symbol: ChangedSymbol, path: String) -> Bool {
        if let semanticArea, symbol.metadata["semantic_area"] != semanticArea { return false }
        if let metadataEquals, !metadataEquals.allSatisfy({ symbol.metadata[$0.key] == $0.value }) {
            return false
        }
        if let paths, !PatternMatcher.matchesAny(path, patterns: paths) { return false }
        if let symbolNames, !PatternMatcher.matchesAny(symbol.name, patterns: symbolNames) {
            return false
        }
        return semanticArea != nil || metadataEquals != nil || paths != nil || symbolNames != nil
    }
}

extension Array where Element == ReviewTarget {
    fileprivate var severitySummary: String {
        let severities: [(Severity, String)] = [
            (.high, "high"),
            (.medium, "medium"),
            (.low, "low"),
            (.info, "info"),
        ]
        let parts = severities.compactMap { severity, label -> String? in
            let count = filter { $0.severity == severity }.count
            guard count > 0 else { return nil }
            return "\(count) \(label)"
        }
        if parts.isEmpty { return "0 targets" }
        return parts.joined(separator: ", ") + " target\(count == 1 ? "" : "s")"
    }
}

struct ContextStatChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11))
            .foregroundColor(.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
