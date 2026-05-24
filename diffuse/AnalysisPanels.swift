import SwiftUI

// MARK: - Review Map Panel

struct AnalysisNavigationRail: View {
    @Environment(AppState.self) private var state
    let details: AnalysisDetails

    var prioritySignals: [RiskHighlight] {
        details.riskHighlights
            .filter { $0.severity >= .medium }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailSectionHeader(title: "View", count: nil)

            AllChangesNavRow(
                fileCount: details.files.count,
                isSelected: state.selectedBucketId == nil && !state.isLowerSignalViewSelected
            ) {
                state.selectAllChanges()
            }

            if !details.skimTargets.isEmpty {
                LowerSignalNavRow(
                    fileCount: details.skimTargets.count,
                    isSelected: state.isLowerSignalViewSelected
                ) {
                    state.selectLowerSignalChanges()
                }
            }

            RailSectionHeader(
                title: "Signals",
                count: prioritySignals.count,
                help: "Concrete analyzer signals that may deserve attention, such as contract changes, data model shifts, or behavior-impacting edits."
            )

            if prioritySignals.isEmpty {
                RailEmptyRow(icon: "checkmark.circle", text: "No priority signals")
            } else {
                VStack(spacing: 2) {
                    ForEach(prioritySignals) { signal in
                        SignalNavRow(signal: signal) {
                            state.jumpToHighlight(signal)
                        }
                    }
                }
            }

            RailSectionHeader(
                title: "Areas",
                count: details.changeBuckets.count,
                help: "Files grouped by the kind of work they represent, so you can review related changes together."
            )

            if details.changeBuckets.isEmpty {
                RailEmptyRow(icon: "tray", text: "No grouped areas")
            } else {
                VStack(spacing: 2) {
                    ForEach(details.changeBuckets) { bucket in
                        AreaNavRow(
                            bucket: bucket,
                            isSelected: state.selectedBucketId == bucket.id
                        ) {
                            state.selectBucket(bucket.id)
                        }
                    }
                }
            }

            RailSectionHeader(
                title: "Targets",
                count: state.bucketTargets.count,
                help: "Suggested review entry points for the currently selected view, ordered by concrete analyzer signals and symbol-level impact."
            )

            if state.bucketTargets.isEmpty {
                RailEmptyRow(icon: "checkmark.seal", text: "No selected-view targets")
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(state.bucketTargets.prefix(6).enumerated()), id: \.element.id) { index, target in
                        TargetNavRow(target: target, index: index)
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
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color.accentBlue.opacity(0.55) : Color.borderMuted, lineWidth: isSelected ? 1 : 0.5))
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
                    Text("Lower-Signal Changes")
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
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color.accentBlue.opacity(0.55) : Color.borderMuted, lineWidth: isSelected ? 1 : 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Configuration, documentation, generated, or boilerplate files that are usually safe to skim.")
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
                    Text(signal.category.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
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

                    Text(bucket.files.count == 1 ? "1 file" : "\(bucket.files.count) files")
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
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color.accentBlue.opacity(0.55) : Color.clear, lineWidth: 1))
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

struct TargetNavRow: View {
    @Environment(AppState.self) private var state
    let target: ReviewTarget
    let index: Int
    @State private var isHovered = false

    var body: some View {
        Button {
            if let fileId = target.changedFileId {
                state.jumpToFile(fileId, hunkIndex: target.hunkIndex)
            }
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
            .background(isHovered ? Color(NSColor.controlColor).opacity(0.55) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(target.changedFileId == nil)
        .onHover { isHovered = $0 }
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

struct ReviewMapPanel: View {
    @Environment(AppState.self) private var state
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
                            .foregroundColor(.successColor)
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
                                state.jumpToHighlight(signal)
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
                    Text(signal.category.rawValue.replacingOccurrences(of: "-", with: " ").capitalized)
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
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isHovered ? Color.accentBlue.opacity(0.3) : Color.borderMuted, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Semantic Buckets Panel (Change Buckets)

struct SemanticBucketsPanel: View {
    @Environment(AppState.self) private var state
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
                    Text("\(details.changeBuckets.count) area\(details.changeBuckets.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }

                VStack(spacing: 6) {
                    AllChangesCard(
                        fileCount: details.files.count,
                        signalCount: details.riskHighlights.filter { $0.severity >= .medium }.count,
                        isSelected: state.selectedBucketId == nil
                    ) {
                        state.selectAllChanges()
                    }

                    ForEach(details.changeBuckets) { bucket in
                        BucketCard(
                            bucket: bucket,
                            highlights: details.riskHighlights.filter { $0.bucketId == bucket.id },
                            isSelected: state.selectedBucketId == bucket.id
                        ) {
                            state.selectBucket(bucket.id)
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
            .background(isSelected ? Color.accentBlue.opacity(0.08) : (isHovered ? Color(NSColor.controlColor).opacity(0.8) : Color(NSColor.controlColor).opacity(0.4)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentBlue.opacity(0.6) : Color.borderMuted, lineWidth: isSelected ? 1 : 0.5)
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
                    BadgeView(text: bucket.riskLevel.displayName, variant: bucket.riskLevel.badgeColor)
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
            .background(isSelected ? Color.accentBlue.opacity(0.08) : (isHovered ? Color(NSColor.controlColor).opacity(0.8) : Color(NSColor.controlColor).opacity(0.4)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentBlue.opacity(0.6) : Color.borderMuted, lineWidth: isSelected ? 1 : 0.5)
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
                SectionHeading("Selected View Targets", icon: "shield.lefthalf.filled",
                               meta: "\(targets.count) target\(targets.count == 1 ? "" : "s")")

                if targets.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.successColor)
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
    @Environment(AppState.self) private var state
    let target: ReviewTarget
    let index: Int

    var borderColor: Color {
        switch target.severity {
        case .high: .dangerColor
        case .medium: .warningColor
        case .low: .infoColor
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
                if let fileId = target.changedFileId {
                    Button {
                        state.jumpToFile(fileId, hunkIndex: target.hunkIndex)
                    } label: {
                        Label("View diff", systemImage: "arrow.right")
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
                    Text(target.filePath + (target.lineStart.map { " · L\($0)–\(target.lineEnd ?? $0)" } ?? ""))
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
                .stroke(Color.borderMuted, lineWidth: 0.5)
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
                            ForEach(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { cls in
                                let items = grouped[cls]!
                                BadgeView(text: "\(items.count) \(items[0].groupName)", variant: .neutral)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                }

                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { cls in
                            let items = grouped[cls]!
                            VStack(alignment: .leading, spacing: 4) {
                                Text(items[0].groupName.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                                    .kerning(0.5)

                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
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
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.borderMuted, lineWidth: 0.5))
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
    @Environment(AppState.self) private var state
    let details: AnalysisDetails
    @State private var isProfileRulesPresented = false
    @State private var isProfileRulesHovered = false

    var nextTarget: ReviewTarget? {
        state.bucketTargets.first { $0.changedFileId != nil }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REVIEW SCOPE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .kerning(0.5)
                Text(state.selectedReviewScopeTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text(state.selectedReviewScopeSubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }
            Spacer()

            HStack(spacing: 7) {
                ContextStatChip(icon: "doc.text.fill", text: "\(state.bucketFiles.count) files")
                if state.selectedScopeSignalCount > 0 {
                    ContextStatChip(icon: "exclamationmark.shield.fill", text: "\(state.selectedScopeSignalCount) signals")
                }
                if state.bucketTargets.count > 0 {
                    ContextStatChip(icon: "target", text: "\(state.bucketTargets.count) targets")
                }

                if let repo = state.selectedRepo {
                    Button {
                        isProfileRulesPresented = true
                    } label: {
                        Label("Rules", systemImage: "list.bullet.rectangle")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(NSColor.controlColor).opacity(isProfileRulesHovered ? 0.85 : 0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .onHover { isProfileRulesHovered = $0 }
                    .help("View active analysis rules and groupings")
                    .sheet(isPresented: $isProfileRulesPresented) {
                        AnalysisProfileRulesSheet(repoName: repo.name, repoPath: repo.path)
                    }
                }

                if let nextTarget, let fileId = nextTarget.changedFileId {
                    Button {
                        state.jumpToFile(fileId, hunkIndex: nextTarget.hunkIndex)
                    } label: {
                        Label("Review next", systemImage: "arrow.right.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentBlue)
                    .help(nextTarget.title)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.bgSubtle)
    }
}

private extension AppState {
    var selectedReviewScopeTitle: String {
        if isLowerSignalViewSelected { return "Lower-signal changes" }
        return selectedBucket?.title ?? "All changes"
    }

    var selectedReviewScopeSubtitle: String {
        if isLowerSignalViewSelected {
            return "Configuration, documentation, generated, and boilerplate files."
        }
        if let selectedBucket {
            return selectedBucket.summary
        }
        return "Unfiltered branch and working tree changes."
    }

    var selectedScopeSignalCount: Int {
        bucketHighlights.filter { $0.severity >= .medium }.count
    }
}

struct ContextStatChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
