import SwiftUI

// MARK: - Diff Viewer Panel

struct DiffViewerPanel: View {
    @Environment(AppState.self) private var state
    let details: AnalysisDetails

    @State private var hideBoilerplate = false
    @State private var isFileSidebarCollapsed = false
    @State private var compactFileTree = true
    @State private var fileSidebarWidth: CGFloat = 220

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
                    Label(hideBoilerplate ? "Boilerplate hidden" : "Hide boilerplate",
                          systemImage: hideBoilerplate ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Button {
                    compactFileTree.toggle()
                } label: {
                    Label(compactFileTree ? "Compact tree" : "Full tree",
                          systemImage: compactFileTree ? "rectangle.compress.vertical" : "list.bullet.indent")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help(compactFileTree ? "Fold single-child folder chains" : "Show every folder level")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.bgSubtle)

            Divider()

            HStack(spacing: 0) {
                // File list sidebar
                if !isFileSidebarCollapsed {
                    FileListSidebar(files: filteredFiles, activeFile: activeFile, compactTree: compactFileTree, width: fileSidebarWidth)
                    PaneDivider(width: $fileSidebarWidth, minWidth: 140, maxWidth: 420)
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
                    .background(Color.bgCanvas)
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
    let compactTree: Bool
    var width: CGFloat = 220
    @State private var collapsedFolders: Set<String> = []

    var roots: [FileTreeNode] {
        FileTreeNode.build(files: files)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(roots) { node in
                    FileTreeNodeView(
                        node: node,
                        depth: 0,
                        activeFile: activeFile,
                        collapsedFolders: $collapsedFolders,
                        compactTree: compactTree
                    ) { file in
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
        .frame(width: width)
        .background(Color.bgSubtle)
    }
}

struct FileTreeNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    var files: [ChangedFile] = []
    var children: [FileTreeNode] = []

    var fileCount: Int {
        files.count + children.reduce(0) { $0 + $1.fileCount }
    }

    var isSingleChildDirectoryChain: Bool {
        files.isEmpty && children.count == 1
    }

    static func build(files: [ChangedFile]) -> [FileTreeNode] {
        var root = MutableFileTreeNode(name: "", path: "")

        for file in files.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            let parts = file.path.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }
            root.insert(file: file, folders: Array(parts.dropLast()))
        }

        return root.children.values
            .map { $0.toImmutable() }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct MutableFileTreeNode {
    let name: String
    let path: String
    var files: [ChangedFile] = []
    var children: [String: MutableFileTreeNode] = [:]

    mutating func insert(file: ChangedFile, folders: [String]) {
        guard let folder = folders.first else {
            files.append(file)
            files.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
            return
        }

        let childPath = path.isEmpty ? folder : "\(path)/\(folder)"
        if children[folder] == nil {
            children[folder] = MutableFileTreeNode(name: folder, path: childPath)
        }
        children[folder]?.insert(file: file, folders: Array(folders.dropFirst()))
    }

    func toImmutable() -> FileTreeNode {
        FileTreeNode(
            id: path.isEmpty ? name : path,
            name: name,
            path: path,
            files: files,
            children: children.values
                .map { $0.toImmutable() }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }
}

struct FileTreeNodeView: View {
    let node: FileTreeNode
    let depth: Int
    let activeFile: ChangedFile?
    @Binding var collapsedFolders: Set<String>
    let compactTree: Bool
    let onSelectFile: (ChangedFile) -> Void

    var displayedNode: FileTreeNode {
        guard compactTree else { return node }
        var current = node
        var names = [current.name]
        while current.isSingleChildDirectoryChain, let child = current.children.first {
            current = child
            names.append(current.name)
        }
        return FileTreeNode(
            id: current.id,
            name: names.joined(separator: "/"),
            path: current.path,
            files: current.files,
            children: current.children
        )
    }

    var body: some View {
        let node = displayedNode
        let isCollapsed = collapsedFolders.contains(node.id)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isCollapsed {
                    collapsedFolders.remove(node.id)
                } else {
                    collapsedFolders.insert(node.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 10)

                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Text(node.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    Text("\(node.fileCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textTertiary)
                }
                .padding(.leading, CGFloat(min(depth, 4)) * 12 + 8)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(node.path)

            if !isCollapsed {
                ForEach(node.files) { file in
                    FileListItem(file: file, isActive: activeFile?.id == file.id, depth: depth + 1)
                        .onTapGesture {
                            onSelectFile(file)
                        }
                }

                ForEach(node.children) { child in
                    FileTreeNodeView(
                        node: child,
                        depth: depth + 1,
                        activeFile: activeFile,
                        collapsedFolders: $collapsedFolders,
                        compactTree: compactTree,
                        onSelectFile: onSelectFile
                    )
                }
            }
        }
    }
}

struct FileListItem: View {
    let file: ChangedFile
    let isActive: Bool
    var depth: Int = 0

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
                .frame(width: 16)

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
        .padding(.leading, CGFloat(min(depth, 4)) * 12 + 10)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(isActive ? Color.accentBlue.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isActive ? Color.accentBlue : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .help(file.path)
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
                    .background(Color.bgSubtle)
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
        .background(Color.bgCanvas)
    }
}

// MARK: - Hunk View

struct HunkView: View {
    let hunk: DiffHunk
    let hunkIndex: Int
    let fileId: UUID
    let isHighlighted: Bool
    @State private var isCollapsed = false

    var diffLines: [NumberedDiffLine] {
        var oldLine = hunk.oldStart
        var newLine = hunk.newStart

        return hunk.lines.map { rawLine in
            let type = NumberedDiffLine.LineType(rawLine: rawLine)
            let numbered = NumberedDiffLine(
                rawLine: rawLine,
                oldLineNumber: type.showsOldLine ? oldLine : nil,
                newLineNumber: type.showsNewLine ? newLine : nil,
                type: type
            )

            if type.advancesOldLine { oldLine += 1 }
            if type.advancesNewLine { newLine += 1 }

            return numbered
        }
    }

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
                    ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                        DiffLine(line: line)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .background(Color.bgCanvas)
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

struct NumberedDiffLine {
    enum LineType {
        case added, deleted, context, metadata

        init(rawLine: String) {
            if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                self = .added
            } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                self = .deleted
            } else if rawLine.hasPrefix("\\") {
                self = .metadata
            } else {
                self = .context
            }
        }

        var showsOldLine: Bool {
            switch self {
            case .added, .metadata: false
            case .deleted, .context: true
            }
        }

        var showsNewLine: Bool {
            switch self {
            case .deleted, .metadata: false
            case .added, .context: true
            }
        }

        var advancesOldLine: Bool { showsOldLine }
        var advancesNewLine: Bool { showsNewLine }
    }

    let rawLine: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let type: LineType
}

struct DiffLine: View {
    let line: NumberedDiffLine

    var bgColor: Color {
        switch line.type {
        case .added: Color.diffAddedBg
        case .deleted: Color.diffDeletedBg
        case .context, .metadata: Color.clear
        }
    }

    var prefixColor: Color {
        switch line.type {
        case .added: Color.diffAddedFg
        case .deleted: Color.dangerColor
        case .context, .metadata: Color.textTertiary
        }
    }

    var prefix: String {
        switch line.type {
        case .added: "+"
        case .deleted: "−"
        case .context: " "
        case .metadata: "\\"
        }
    }

    var lineContent: String {
        guard !line.rawLine.isEmpty else { return "" }
        if line.type == .metadata { return String(line.rawLine.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return String(line.rawLine.dropFirst())
    }

    var body: some View {
        HStack(spacing: 0) {
            LineNumberText(line.oldLineNumber)
            LineNumberText(line.newLineNumber)

            // Prefix gutter
            Text(prefix)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(prefixColor)
                .frame(width: 18, alignment: .center)
                .background(Color.bgSubtle.opacity(0.65))

            // Line content
            Text(lineContent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(line.type == .context ? Color.textPrimary.opacity(0.75) : line.type == .metadata ? .textTertiary : .textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .padding(.trailing, 12)
        }
        .frame(minHeight: 20)
        .background(bgColor)
    }
}

struct LineNumberText: View {
    let number: Int?

    init(_ number: Int?) {
        self.number = number
    }

    var body: some View {
        Text(number.map(String.init) ?? "")
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.textTertiary)
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 6)
            .background(Color.bgSubtle.opacity(0.65))
    }
}

// MARK: - Sticky modifier (simulated via ZStack positioning)

extension View {
    func sticky() -> some View {
        self
    }
}
