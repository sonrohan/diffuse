import SwiftUI

// MARK: - Diff Viewer Panel

struct DiffViewerPanel: View {
    @Environment(AppState.self) private var state
    let details: AnalysisDetails

    @State private var hideBoilerplate = true
    @State private var isFileSidebarCollapsed = false

    var activeFile: ChangedFile? {
        guard let id = state.activeFileId else { return filteredFiles.first }
        return state.bucketFiles.first { $0.id == id }
    }

    var filteredFiles: [ChangedFile] {
        let ordered = state.reorderFiles(state.bucketFiles, highlights: details.riskHighlights)
        if hideBoilerplate {
            return ordered.filter { $0.classification == .source || $0.classification == .test }
        }
        return ordered
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text("Changed Files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    isFileSidebarCollapsed.toggle()
                } label: {
                    Text(isFileSidebarCollapsed ? "Show files" : "Hide files")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Button {
                    hideBoilerplate.toggle()
                } label: {
                    Label(hideBoilerplate ? "Boilerplate hidden" : "Show all",
                          systemImage: hideBoilerplate ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                // File list sidebar
                if !isFileSidebarCollapsed {
                    FileListSidebar(files: filteredFiles, activeFile: activeFile)
                    Divider()
                }

                // Diff content
                if let file = activeFile {
                    DiffContent(file: file, activeHunkIndex: state.activeHunkIndex)
                } else {
                    VStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.textTertiary)
                        Text("Select a file to view its diff")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File List Sidebar

struct FileListSidebar: View {
    @Environment(AppState.self) private var state
    let files: [ChangedFile]
    let activeFile: ChangedFile?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(files) { file in
                    FileListItem(file: file, isActive: activeFile?.id == file.id)
                        .onTapGesture {
                            state.jumpToFile(file.id)
                        }
                }

                if files.isEmpty {
                    Text("No source files in this view.")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .italic()
                        .padding(16)
                }
            }
        }
        .frame(width: 220)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct FileListItem: View {
    let file: ChangedFile
    let isActive: Bool

    var statusColor: Color {
        switch file.status {
        case .added: .successColor
        case .deleted: .dangerColor
        case .modified: .textSecondary
        case .renamed: .warningColor
        }
    }

    var statusBadge: String {
        switch file.status {
        case .added: "A"
        case .deleted: "D"
        case .modified: "M"
        case .renamed: "R"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(statusBadge)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(statusColor)
                .frame(width: 14)

            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundColor(isActive ? .accentBlue : .textTertiary)

            Text(file.filename)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isActive ? .textPrimary : .textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            classificationBadge(file.classification)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? Color.accentBlue.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isActive ? Color.accentBlue : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func classificationBadge(_ cls: ChangedFile.FileClassification) -> some View {
        switch cls {
        case .test:
            BadgeView(text: "test", variant: .info)
        case .config:
            BadgeView(text: "cfg", variant: .neutral)
        case .generated:
            BadgeView(text: "gen", variant: .neutral)
        default:
            EmptyView()
        }
    }
}

// MARK: - Diff Content

struct DiffContent: View {
    @Environment(AppState.self) private var state
    let file: ChangedFile
    let activeHunkIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // File path bar
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Text(file.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("+\(file.additions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.successColor)
                        Text("−\(file.deletions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.dangerColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .sticky()

                    Divider()

                    // Hunks
                    ForEach(Array(file.hunks.enumerated()), id: \.offset) { idx, hunk in
                        HunkView(
                            hunk: hunk,
                            hunkIndex: idx,
                            fileId: file.id,
                            isHighlighted: activeHunkIndex == idx
                        )
                        .id("hunk-\(file.id)-\(idx)")
                    }

                    if file.hunks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 24))
                                .foregroundColor(.textTertiary)
                            Text("No diff hunks available")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                }
            }
            .onChange(of: activeHunkIndex) { _, newIdx in
                if let idx = newIdx {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("hunk-\(file.id)-\(idx)", anchor: .center)
                    }
                }
            }
            .onChange(of: file.id) { _, _ in
                proxy.scrollTo("hunk-\(file.id)-0", anchor: .top)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Hunk View

struct HunkView: View {
    let hunk: DiffHunk
    let hunkIndex: Int
    let fileId: UUID
    let isHighlighted: Bool
    @State private var isCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            // Hunk header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isCollapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                    Text("@@ -\(hunk.oldStart),\(hunk.oldLines) +\(hunk.newStart),\(hunk.newLines) @@")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.infoColor)
                    Spacer()
                    Text("\(hunk.lines.count) lines")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.underPageBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            // Hunk lines
            if !isCollapsed {
                VStack(spacing: 0) {
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { lineIdx, line in
                        DiffLine(line: line, lineNumber: hunk.newStart + lineIdx)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .overlay(alignment: .leading) {
            if isHighlighted {
                Rectangle()
                    .fill(Color.warningColor.opacity(0.7))
                    .frame(width: 3)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 0).stroke(
            isHighlighted ? Color.warningColor.opacity(0.3) : Color.clear, lineWidth: 1
        ))
    }
}

// MARK: - Diff Line

struct DiffLine: View {
    let line: String
    let lineNumber: Int

    var lineType: LineType {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .added }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .deleted }
        return .context
    }

    enum LineType { case added, deleted, context }

    var bgColor: Color {
        switch lineType {
        case .added: Color.diffAddedBg
        case .deleted: Color.diffDeletedBg
        case .context: Color.clear
        }
    }

    var prefixColor: Color {
        switch lineType {
        case .added: Color.diffAddedFg
        case .deleted: Color.dangerColor
        case .context: Color.textTertiary
        }
    }

    var prefix: String {
        switch lineType {
        case .added: "+"
        case .deleted: "−"
        case .context: " "
        }
    }

    var lineContent: String {
        guard !line.isEmpty else { return "" }
        return String(line.dropFirst())
    }

    var body: some View {
        HStack(spacing: 0) {
            // Prefix gutter
            Text(prefix)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(prefixColor)
                .frame(width: 20, alignment: .center)
                .padding(.leading, 8)

            // Line content
            Text(lineContent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(lineType == .context ? Color.textPrimary.opacity(0.75) : .textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
        }
        .frame(minHeight: 20)
        .background(bgColor)
    }
}

// MARK: - Sticky modifier (simulated via ZStack positioning)

extension View {
    func sticky() -> some View {
        self
    }
}
