import SwiftUI

// MARK: - Diff Viewer Panel

struct DiffViewerPanel: View {
    @Environment(AppState.self) private var state
    @Environment(AnalysisViewModel.self) private var viewModel
    let details: AnalysisDetails

    @State private var hideBoilerplate = false
    @State private var compactFileTree = true
    @State private var fileSidebarWidth: CGFloat = 220
    @State private var fileSearchText = ""
    @State private var excludedExtensions: Set<String> = []
    @State private var excludedStatuses: Set<ChangedFile.FileStatus> = []
    @State private var excludedClassifications: Set<ChangedFile.FileClassification> = []
    @State private var showUnviewedOnly = false
    @State private var viewedFileIds: Set<UUID> = []
    @State private var isFilterPopoverPresented = false

    var activeFile: ChangedFile? {
        guard let id = viewModel.activeFileId else { return filteredFiles.first }
        return filteredFiles.first { $0.id == id } ?? filteredFiles.first
    }

    var orderedFiles: [ChangedFile] {
        viewModel.reorderFiles(viewModel.bucketFiles, highlights: details.riskHighlights)
    }

    var filteredFiles: [ChangedFile] {
        orderedFiles.filter { file in
            if hideBoilerplate && !(file.classification == .source || file.classification == .test)
            {
                return false
            }
            if showUnviewedOnly && viewedFileIds.contains(file.id) { return false }
            if excludedExtensions.contains(file.filterExtension) { return false }
            if excludedStatuses.contains(file.status) { return false }
            if excludedClassifications.contains(file.classification) { return false }
            return file.matchesSearch(fileSearchText)
        }
    }

    var activeFilterCount: Int {
        var count =
            excludedExtensions.count + excludedStatuses.count + excludedClassifications.count
        if !fileSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if showUnviewedOnly { count += 1 }
        return count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text("Changed Files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("\(filteredFiles.count)/\(orderedFiles.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.textTertiary)

                FileSearchField(text: $fileSearchText)
                    .frame(maxWidth: 340)

                Button {
                    isFilterPopoverPresented.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .semibold))
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.brandAccent)
                        }
                    }
                    .foregroundColor(activeFilterCount > 0 ? .brandAccent : .textSecondary)
                    .frame(minWidth: 28, minHeight: 22)
                    .padding(.horizontal, activeFilterCount > 0 ? 5 : 0)
                    .background(
                        activeFilterCount > 0
                            ? Color.brandAccent.opacity(0.10)
                            : Color(NSColor.controlColor).opacity(0.45)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(
                                activeFilterCount > 0
                                    ? Color.brandAccent.opacity(0.35) : Color.borderMuted,
                                lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Filter changed files")
                .popover(isPresented: $isFilterPopoverPresented, arrowEdge: .bottom) {
                    FileFilterPopover(
                        files: orderedFiles,
                        excludedExtensions: $excludedExtensions,
                        excludedStatuses: $excludedStatuses,
                        excludedClassifications: $excludedClassifications,
                        showUnviewedOnly: $showUnviewedOnly,
                        viewedFileCount: orderedFiles.filter { viewedFileIds.contains($0.id) }.count
                    ) {
                        resetFileFilters()
                    }
                }

                Spacer()

                // Diff Layout Selector
                Menu {
                    Button {
                        state.diffLayout = .unified
                    } label: {
                        if state.diffLayout == .unified {
                            Text("✓ Unified")
                        } else {
                            Text("Unified")
                        }
                    }
                    Button {
                        state.diffLayout = .split
                    } label: {
                        if state.diffLayout == .split {
                            Text("✓ Split")
                        } else {
                            Text("Split")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(
                            systemName: state.diffLayout == .unified
                                ? "doc.text" : "square.split.2x1"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        Text(state.diffLayout == .unified ? "Unified" : "Split")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.textTertiary)
                    }
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlColor).opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.borderMuted, lineWidth: 0.5)
                    )
                }
                .menuStyle(.borderlessButton)
                .help("Change diff layout")

                DiffToolbarButton(
                    systemImage: hideBoilerplate ? "eye.slash.fill" : "eye",
                    isActive: hideBoilerplate,
                    help: hideBoilerplate ? "Show boilerplate files" : "Hide boilerplate files"
                ) {
                    hideBoilerplate.toggle()
                }

                DiffToolbarButton(
                    systemImage: compactFileTree
                        ? "rectangle.compress.vertical" : "list.bullet.indent",
                    isActive: compactFileTree,
                    help: compactFileTree
                        ? "Show every folder level" : "Fold single-child folder chains"
                ) {
                    compactFileTree.toggle()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.bgSubtle)

            Divider()

            HSplitView {
                // File list sidebar
                FileListSidebar(
                    files: filteredFiles, activeFile: activeFile, compactTree: compactFileTree
                )
                .frame(minWidth: 140, idealWidth: 220, maxWidth: 420)

                // Diff content
                if let file = activeFile {
                    DiffContent(
                        file: file,
                        activeHunkIndex: viewModel.activeHunkIndex,
                        activeTarget: viewModel.activeTarget?.filePath == file.path
                            ? viewModel.activeTarget : nil
                    )
                } else {
                    VStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.textTertiary)
                        Text(
                            filteredFiles.isEmpty
                                ? "No files match the current filters"
                                : "Select a file to view its diff"
                        )
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        if filteredFiles.isEmpty && activeFilterCount > 0 {
                            Button("Clear filters") {
                                resetFileFilters()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgCanvas)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let id = activeFile?.id {
                viewedFileIds.insert(id)
            }
        }
        .onChange(of: activeFile?.id) { _, id in
            if let id { viewedFileIds.insert(id) }
        }
        .onChange(of: filteredFiles.map(\.id)) { _, ids in
            if let activeId = viewModel.activeFileId, !ids.contains(activeId) {
                viewModel.jumpToFile(ids.first ?? activeId)
            }
        }
    }

    private func resetFileFilters() {
        fileSearchText = ""
        excludedExtensions = []
        excludedStatuses = []
        excludedClassifications = []
        showUnviewedOnly = false
    }
}

struct FileSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)

            TextField("Filter files...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear file search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.borderMuted, lineWidth: 0.5))
    }
}

struct FileFilterPopover: View {
    let files: [ChangedFile]
    @Binding var excludedExtensions: Set<String>
    @Binding var excludedStatuses: Set<ChangedFile.FileStatus>
    @Binding var excludedClassifications: Set<ChangedFile.FileClassification>
    @Binding var showUnviewedOnly: Bool
    let viewedFileCount: Int
    let reset: () -> Void

    var extensionCounts: [(String, Int)] {
        counted(files.map(\.filterExtension))
    }

    var statusCounts: [(ChangedFile.FileStatus, Int)] {
        ChangedFile.FileStatus.allCases.compactMap { status in
            let count = files.filter { $0.status == status }.count
            return count == 0 ? nil : (status, count)
        }
    }

    var classificationCounts: [(ChangedFile.FileClassification, Int)] {
        ChangedFile.FileClassification.allCases.compactMap { classification in
            let count = files.filter { $0.classification == classification }.count
            return count == 0 ? nil : (classification, count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File filters")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button("Reset", action: reset)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(.brandAccent)
            }

            FilterSection(title: "Extensions") {
                ForEach(extensionCounts, id: \.0) { ext, count in
                    FilterToggleRow(
                        title: ext,
                        count: count,
                        isIncluded: !excludedExtensions.contains(ext)
                    ) {
                        toggle(ext, in: $excludedExtensions)
                    }
                }
            }

            FilterSection(title: "Status") {
                ForEach(statusCounts, id: \.0) { status, count in
                    FilterToggleRow(
                        title: status.displayName, count: count,
                        isIncluded: !excludedStatuses.contains(status)
                    ) {
                        toggle(status, in: $excludedStatuses)
                    }
                }
            }

            FilterSection(title: "Type") {
                ForEach(classificationCounts, id: \.0) { classification, count in
                    FilterToggleRow(
                        title: classification.displayName, count: count,
                        isIncluded: !excludedClassifications.contains(classification)
                    ) {
                        toggle(classification, in: $excludedClassifications)
                    }
                }
            }

            Divider()

            Button {
                showUnviewedOnly.toggle()
            } label: {
                FilterToggleRowContent(
                    title: "Unviewed only",
                    count: max(files.count - viewedFileCount, 0),
                    isIncluded: showUnviewedOnly
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
        .background(Color.bgCanvas)
    }

    private func counted(_ values: [String]) -> [(String, Int)] {
        Dictionary(grouping: values, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.0 == "No extension" { return false }
                if rhs.0 == "No extension" { return true }
                return lhs.0.localizedStandardCompare(rhs.0) == .orderedAscending
            }
    }

    private func toggle<T: Hashable>(_ value: T, in binding: Binding<Set<T>>) {
        var values = binding.wrappedValue
        if values.contains(value) {
            values.remove(value)
        } else {
            values.insert(value)
        }
        binding.wrappedValue = values
    }
}

struct FilterSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .kerning(0.5)
            VStack(spacing: 2) {
                content
            }
        }
    }
}

struct FilterToggleRow: View {
    let title: String
    let count: Int
    let isIncluded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FilterToggleRowContent(title: title, count: count, isIncluded: isIncluded)
        }
        .buttonStyle(.plain)
    }
}

struct FilterToggleRowContent: View {
    let title: String
    let count: Int
    let isIncluded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textSecondary)
                .opacity(isIncluded ? 1 : 0)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlColor).opacity(0.55))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

extension ChangedFile {
    fileprivate var filterExtension: String {
        let ext = URL(fileURLWithPath: path).pathExtension
        return ext.isEmpty ? "No extension" : ".\(ext)"
    }

    fileprivate func matchesSearch(_ text: String) -> Bool {
        let terms =
            text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0).lowercased() }
        guard !terms.isEmpty else { return true }

        let haystack = "\(path) \(filename) \(classification.displayName) \(status.displayName)"
            .lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }
}

extension ChangedFile.FileStatus: CaseIterable {
    static var allCases: [ChangedFile.FileStatus] {
        [.added, .modified, .deleted, .renamed]
    }

    var displayName: String {
        switch self {
        case .added: "Added"
        case .modified: "Modified"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        }
    }
}

extension ChangedFile.FileClassification: CaseIterable {
    static var allCases: [ChangedFile.FileClassification] {
        [.source, .test, .config, .documentation, .generated, .boilerplate]
    }

    var displayName: String {
        switch self {
        case .source: "Source"
        case .test: "Tests"
        case .config: "Config"
        case .documentation: "Docs"
        case .generated: "Generated"
        case .boilerplate: "Boilerplate"
        }
    }
}

struct DiffToolbarButton: View {
    let systemImage: String
    var isActive = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? .brandAccent : .textSecondary)
                .frame(width: 26, height: 22)
                .background(
                    isActive
                        ? Color.brandAccent.opacity(0.10)
                        : Color(NSColor.controlColor).opacity(0.45)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            isActive ? Color.brandAccent.opacity(0.35) : Color.borderMuted,
                            lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - File List Sidebar

struct FileListSidebar: View {
    @Environment(AnalysisViewModel.self) private var viewModel
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
                        viewModel.jumpToFile(file.id)
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
        .frame(maxWidth: .infinity)
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

        for file in files.sorted(by: {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }) {
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
    @Environment(AnalysisViewModel.self) private var viewModel
    let file: ChangedFile
    let isActive: Bool
    var depth: Int = 0

    var fileTargets: [ReviewTarget] {
        viewModel.bucketTargets.filter { $0.filePath == file.path }
    }

    var topTargetSeverity: Severity? {
        fileTargets.map(\.severity).max()
    }

    var statusColor: Color {
        switch file.status {
        case .added: .success
        case .deleted: .danger
        case .modified: .textSecondary
        case .renamed: .warning
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
                .foregroundColor(isActive ? .brandAccent : .textTertiary)

            Text(file.filename)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isActive ? .textPrimary : .textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if !fileTargets.isEmpty {
                targetIndicator
            }

            classificationBadge(file.classification)
        }
        .padding(.leading, CGFloat(min(depth, 4)) * 12 + 10)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(isActive ? Color.brandAccent.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isActive ? Color.brandAccent : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .help(fileHelpText)
    }

    var targetIndicator: some View {
        HStack(spacing: 3) {
            Image(systemName: "target")
                .font(.system(size: 8, weight: .bold))
            Text("\(fileTargets.count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundColor(targetColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(targetColor.opacity(0.10))
        .clipShape(Capsule())
    }

    var targetColor: Color {
        switch topTargetSeverity {
        case .high: .danger
        case .medium: .warning
        case .low: .info
        case .info, nil: .textTertiary
        }
    }

    var fileHelpText: String {
        guard let firstTarget = fileTargets.first else { return file.path }
        let severity = firstTarget.severity.rawValue.capitalized
        let extraCount = fileTargets.count - 1
        if extraCount > 0 {
            return
                "\(file.path)\nNeeds attention: \(severity) - \(firstTarget.title) (+\(extraCount) more)"
        }
        return "\(file.path)\nNeeds attention: \(severity) - \(firstTarget.title)"
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
    let activeTarget: ReviewTarget?
    @State private var teachMessage: String?

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
                        if let teachMessage {
                            Text(teachMessage)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.success)
                        }
                        Menu {
                            Button("Treat this file as generated") {
                                teachClassification(.generated)
                            }
                            Button("Treat this file as test code") {
                                teachClassification(.test)
                            }
                            Button("Treat this file as config") {
                                teachClassification(.config)
                            }
                            Divider()
                            Button("Mark this path as API surface") {
                                teachRiskPath(.api)
                            }
                            Button("Mark this path as sensitive") {
                                teachRiskPath(.sensitive)
                            }
                        } label: {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .menuStyle(.borderlessButton)
                        .help("Teach Chobi how to classify this path")
                        Text("+\(file.additions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.success)
                        Text("−\(file.deletions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.danger)
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
                            isHighlighted: activeHunkIndex == idx,
                            activeTarget: activeTarget
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

    private func teachClassification(_ classification: ChangedFile.FileClassification) {
        guard let repoPath = state.selectedRepo?.path else { return }
        do {
            try AnalysisProfileStore.teachFileClassification(
                repoPath: repoPath,
                path: file.path,
                classification: classification
            )
            teachMessage = "Saved profile rule"
        } catch {
            teachMessage = "Could not save rule"
        }
    }

    private func teachRiskPath(_ kind: EditableRiskPathKind) {
        guard let repoPath = state.selectedRepo?.path else { return }
        do {
            try AnalysisProfileStore.teachRiskPath(repoPath: repoPath, path: file.path, kind: kind)
            teachMessage = "Saved profile rule"
        } catch {
            teachMessage = "Could not save rule"
        }
    }
}

// MARK: - Hunk View

struct AlignedDiffLine: Identifiable {
    let id = UUID()
    let oldLine: NumberedDiffLine?
    let newLine: NumberedDiffLine?
}

struct HunkView: View {
    @Environment(AppState.self) private var state
    @Environment(AnalysisViewModel.self) private var viewModel
    let hunk: DiffHunk
    let hunkIndex: Int
    let fileId: UUID
    let isHighlighted: Bool
    let activeTarget: ReviewTarget?
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

    var alignedDiffLines: [AlignedDiffLine] {
        var aligned: [AlignedDiffLine] = []

        var pendingDeletions: [NumberedDiffLine] = []
        var pendingAdditions: [NumberedDiffLine] = []

        func flushPending() {
            let maxCount = max(pendingDeletions.count, pendingAdditions.count)
            for i in 0..<maxCount {
                let old = i < pendingDeletions.count ? pendingDeletions[i] : nil
                let new = i < pendingAdditions.count ? pendingAdditions[i] : nil
                aligned.append(AlignedDiffLine(oldLine: old, newLine: new))
            }
            pendingDeletions.removeAll()
            pendingAdditions.removeAll()
        }

        for line in diffLines {
            switch line.type {
            case .context:
                flushPending()
                aligned.append(AlignedDiffLine(oldLine: line, newLine: line))
            case .deleted:
                pendingDeletions.append(line)
            case .added:
                pendingAdditions.append(line)
            case .metadata:
                flushPending()
                aligned.append(AlignedDiffLine(oldLine: line, newLine: line))
            }
        }
        flushPending()

        return aligned
    }

    var unifiedLineNumbers: AttributedString {
        var result = AttributedString()
        for line in diffLines {
            result.append(
                lineNumberText(
                    line.oldLineNumber.map(String.init) ?? "", isTargeted: isTargeted(line)))
        }
        return result
    }

    var unifiedNewLineNumbers: AttributedString {
        var result = AttributedString()
        for line in diffLines {
            result.append(
                lineNumberText(
                    line.newLineNumber.map(String.init) ?? "", isTargeted: isTargeted(line)))
        }
        return result
    }

    var unifiedPrefixes: AttributedString {
        var result = AttributedString()
        for line in diffLines {
            let char: String
            let color: Color
            switch line.type {
            case .added:
                char = "+"
                color = Color.diffAddedFg
            case .deleted:
                char = "−"
                color = Color.danger
            case .context:
                char = " "
                color = Color.textTertiary
            case .metadata:
                char = "\\"
                color = Color.textTertiary
            }
            var attr = AttributedString(char + "\n")
            attr.foregroundColor = color
            if isTargeted(line) {
                attr.backgroundColor = Color.warning.opacity(0.22)
            }
            result.append(attr)
        }
        return result
    }

    var unifiedCode: AttributedString {
        var result = AttributedString()
        for line in diffLines {
            let lineContent = line.rawLine.isEmpty ? "" : String(line.rawLine.dropFirst())
            var attr = AttributedString(lineContent + "\n")

            switch line.type {
            case .added:
                attr.foregroundColor = Color.textPrimary
                attr.backgroundColor = Color.diffAddedBg
            case .deleted:
                attr.foregroundColor = Color.textPrimary
                attr.backgroundColor = Color.diffDeletedBg
            case .context:
                attr.foregroundColor = Color.textPrimary.opacity(0.75)
            case .metadata:
                attr.foregroundColor = Color.textTertiary
            }
            if isTargeted(line) {
                attr.foregroundColor = Color.textPrimary
                attr.backgroundColor = Color.warning.opacity(0.28)
            }
            result.append(attr)
        }
        return result
    }

    func splitLineNumbers(isLeft: Bool) -> AttributedString {
        var result = AttributedString()
        for alignedLine in alignedDiffLines {
            let line = isLeft ? alignedLine.oldLine : alignedLine.newLine
            let isTargeted = line.map { self.isTargeted($0) } ?? false
            if let line {
                let num = isLeft ? line.oldLineNumber : line.newLineNumber
                result.append(lineNumberText(num.map(String.init) ?? "", isTargeted: isTargeted))
            } else {
                result.append(lineNumberText("", isTargeted: false))
            }
        }
        return result
    }

    func splitPrefixes(isLeft: Bool) -> AttributedString {
        var result = AttributedString()
        for alignedLine in alignedDiffLines {
            let line = isLeft ? alignedLine.oldLine : alignedLine.newLine
            if let line {
                let char: String
                let color: Color
                switch line.type {
                case .added:
                    char = "+"
                    color = Color.diffAddedFg
                case .deleted:
                    char = "−"
                    color = Color.diffDeletedFg
                case .context:
                    char = " "
                    color = Color.textTertiary
                case .metadata:
                    char = "\\"
                    color = Color.textTertiary
                }
                var attr = AttributedString(char + "\n")
                attr.foregroundColor = color
                if isTargeted(line) {
                    attr.backgroundColor = Color.warning.opacity(0.22)
                }
                result.append(attr)
            } else {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    func splitCode(isLeft: Bool) -> AttributedString {
        var result = AttributedString()
        for alignedLine in alignedDiffLines {
            let line = isLeft ? alignedLine.oldLine : alignedLine.newLine
            if let line {
                let lineContent = line.rawLine.isEmpty ? "" : String(line.rawLine.dropFirst())
                var attr = AttributedString(lineContent + "\n")

                switch line.type {
                case .added:
                    attr.foregroundColor = Color.textPrimary
                    attr.backgroundColor = Color.diffAddedBg
                case .deleted:
                    attr.foregroundColor = Color.textPrimary
                    attr.backgroundColor = Color.diffDeletedBg
                case .context:
                    attr.foregroundColor = Color.textPrimary.opacity(0.75)
                case .metadata:
                    attr.foregroundColor = Color.textTertiary
                }
                if isTargeted(line) {
                    attr.foregroundColor = Color.textPrimary
                    attr.backgroundColor = Color.warning.opacity(0.28)
                }
                result.append(attr)
            } else {
                var attr = AttributedString(" \n")
                attr.backgroundColor = Color.bgSubtle.opacity(0.15)
                result.append(attr)
            }
        }
        return result
    }

    private func isTargeted(_ line: NumberedDiffLine) -> Bool {
        guard let activeTarget,
            let start = activeTarget.lineStart
        else { return false }
        let end = activeTarget.lineEnd ?? start
        guard let newLineNumber = line.newLineNumber else { return false }
        return newLineNumber >= start && newLineNumber <= end
    }

    private func lineNumberText(_ text: String, isTargeted: Bool) -> AttributedString {
        var attr = AttributedString(text + "\n")
        attr.foregroundColor = isTargeted ? Color.warning : Color.textTertiary
        if isTargeted {
            attr.backgroundColor = Color.warning.opacity(0.22)
        }
        return attr
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hunk header with expand controls in the gutter
            HStack(spacing: 0) {
                HStack(spacing: 3) {
                    Button {
                        Task {
                            await viewModel.expandHunk(
                                fileId: fileId, hunkIndex: hunkIndex, direction: .up)
                        }
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.brandAccent)
                            .frame(width: 17, height: 17)
                            .background(Color.brandAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Expand context up (20 lines)")

                    if hunkIndex > 0 {
                        Button {
                            Task {
                                await viewModel.expandHunk(
                                    fileId: fileId, hunkIndex: hunkIndex, direction: .all)
                            }
                        } label: {
                            Image(systemName: "arrow.up.and.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.brandAccent)
                                .frame(width: 17, height: 17)
                                .background(Color.brandAccent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                        .help("Expand all context to previous hunk")
                    }

                    Button {
                        Task {
                            await viewModel.expandHunk(
                                fileId: fileId, hunkIndex: hunkIndex, direction: .down)
                        }
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.brandAccent)
                            .frame(width: 17, height: 17)
                            .background(Color.brandAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Expand context down (20 lines)")
                }
                .frame(width: state.diffLayout == .split ? 62 : 106, alignment: .center)
                .background(Color.bgSubtle.opacity(0.85))

                Rectangle()
                    .fill(Color.borderMuted)
                    .frame(width: 1)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isCollapsed.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                        Text(
                            "@@ -\(hunk.oldStart),\(hunk.oldLines) +\(hunk.newStart),\(hunk.newLines) @@"
                        )
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.info)
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
            }

            Divider()

            // Hunk lines
            if !isCollapsed {
                if state.diffLayout == .split {
                    HStack(spacing: 0) {
                        // Left Pane
                        HStack(spacing: 0) {
                            Text(splitLineNumbers(isLeft: true))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.textTertiary)
                                .frame(width: 44, alignment: .trailing)
                                .padding(.trailing, 6)
                                .background(Color.bgSubtle.opacity(0.65))
                                .textSelection(.disabled)

                            Text(splitPrefixes(isLeft: true))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 18, alignment: .center)
                                .background(Color.bgSubtle.opacity(0.65))
                                .textSelection(.disabled)

                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(splitCode(isLeft: true))
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(.leading, 8)
                                    .padding(.trailing, 12)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .background(Color.bgCanvas)

                        Rectangle()
                            .fill(Color.borderMuted)
                            .frame(width: 1)

                        // Right Pane
                        HStack(spacing: 0) {
                            Text(splitLineNumbers(isLeft: false))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.textTertiary)
                                .frame(width: 44, alignment: .trailing)
                                .padding(.trailing, 6)
                                .background(Color.bgSubtle.opacity(0.65))
                                .textSelection(.disabled)

                            Text(splitPrefixes(isLeft: false))
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 18, alignment: .center)
                                .background(Color.bgSubtle.opacity(0.65))
                                .textSelection(.disabled)

                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(splitCode(isLeft: false))
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(.leading, 8)
                                    .padding(.trailing, 12)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .background(Color.bgCanvas)
                    }
                } else {
                    HStack(spacing: 0) {
                        Text(unifiedLineNumbers)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.textTertiary)
                            .frame(width: 44, alignment: .trailing)
                            .padding(.trailing, 6)
                            .background(Color.bgSubtle.opacity(0.65))
                            .textSelection(.disabled)

                        Text(unifiedNewLineNumbers)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.textTertiary)
                            .frame(width: 44, alignment: .trailing)
                            .padding(.trailing, 6)
                            .background(Color.bgSubtle.opacity(0.65))
                            .textSelection(.disabled)

                        Text(unifiedPrefixes)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 18, alignment: .center)
                            .background(Color.bgSubtle.opacity(0.65))
                            .textSelection(.disabled)

                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(unifiedCode)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.leading, 8)
                                .padding(.trailing, 12)
                        }
                    }
                    .background(Color.bgCanvas)
                }
            }
        }
        .overlay(alignment: .leading) {
            if isHighlighted {
                Rectangle()
                    .fill(Color.warning.opacity(0.7))
                    .frame(width: 3)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0).stroke(
                isHighlighted ? Color.warning.opacity(0.3) : Color.clear, lineWidth: 1
            ))
    }
}

// MARK: - Diff Line Data Model

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

// MARK: - Sticky modifier (simulated via ZStack positioning)

extension View {
    func sticky() -> some View {
        self
    }
}
