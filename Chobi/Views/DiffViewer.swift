import SwiftUI

// MARK: - Diff Viewer Panel

struct DiffViewerPanel: View {
    @Environment(AppState.self) private var state
    @Environment(AnalysisViewModel.self) private var viewModel
    let details: AnalysisDetails
    @Bindable var impactViewModel: ImpactGraphViewModel

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
                    systemImage: "sidebar.right",
                    isActive: viewModel.isImpactInspectorVisible,
                    help: viewModel.isImpactInspectorVisible
                        ? "Hide impact explorer" : "Show impact explorer"
                ) {
                    viewModel.isImpactInspectorVisible.toggle()
                }

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
                    files: filteredFiles,
                    activeFile: activeFile,
                    compactTree: compactFileTree,
                    impactIndicators: impactViewModel.fileImpactIndicators
                )
                .frame(minWidth: 140, idealWidth: 220, maxWidth: 420)

                // Diff content
                if let file = activeFile {
                    DiffContent(
                        file: file,
                        details: details,
                        impactViewModel: impactViewModel,
                        activeHunkIndex: viewModel.activeHunkIndex,
                        activeTarget: viewModel.activeTarget?.filePath == file.path
                            ? viewModel.activeTarget : nil
                    ) { impact in
                        impactViewModel.select(impact)
                        viewModel.jumpToImpactRoot(impact)
                    }

                    if viewModel.isImpactInspectorVisible {
                        ImpactExplorerSidebar(
                            impactViewModel: impactViewModel,
                            details: details,
                            onClose: { viewModel.isImpactInspectorVisible = false },
                            onOpenImpact: { impact in
                                impactViewModel.select(impact)
                                viewModel.jumpToImpactRoot(impact)
                            },
                            onOpenNode: { node in
                                jumpToGraphNode(node, details: details)
                            }
                        )
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
                    }
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

    private func jumpToGraphNode(_ node: ImpactGraphNode, details: AnalysisDetails) {
        guard node.isChangedInPR,
            let file = details.files.first(where: { $0.path == node.filePath })
        else { return }
        viewModel.jumpToFile(file.id, hunkIndex: hunkIndexForLine(file: file, line: node.line))
    }

    private func hunkIndexForLine(file: ChangedFile, line: Int?) -> Int? {
        guard let line else { return nil }
        return file.hunks.firstIndex { hunk in
            line >= hunk.newStart && line <= hunk.newStart + max(hunk.newLines - 1, 0)
        }
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
    let impactIndicators: [UUID: FileImpactIndicator]
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
                        compactTree: compactTree,
                        impactIndicators: impactIndicators
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
    let impactIndicators: [UUID: FileImpactIndicator]
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
                    FileListItem(
                        file: file,
                        isActive: activeFile?.id == file.id,
                        depth: depth + 1,
                        impactIndicator: impactIndicators[file.id]
                    )
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
                        impactIndicators: impactIndicators,
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
    let impactIndicator: FileImpactIndicator?

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

            if let impactIndicator {
                impactBadge(impactIndicator)
            }
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

    func impactBadge(_ indicator: FileImpactIndicator) -> some View {
        Text("\(indicator.count)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(indicator.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(indicator.color.opacity(0.10))
            .clipShape(Capsule())
            .help(indicator.helpText)
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

}

// MARK: - Diff Content

struct DiffContent: View {
    @Environment(AppState.self) private var state
    let file: ChangedFile
    let details: AnalysisDetails
    let impactViewModel: ImpactGraphViewModel
    let activeHunkIndex: Int?
    let activeTarget: ReviewTarget?
    let onOpenImpact: (SymbolImpact) -> Void

    var fileImpacts: [SymbolImpact] {
        impactViewModel.visibleImpacts(for: file)
    }

    var activeImpactRange: ClosedRange<Int>? {
        guard let context = impactViewModel.selectedSourceContext,
            context.isChangedInCurrentPR,
            context.filePath == file.path
        else { return nil }
        return context.startLine...max(context.startLine, context.endLine)
    }

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

                    ReviewImpactSummary(impactViewModel: impactViewModel)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.bgCanvas)

                    if !fileImpacts.isEmpty {
                        FileImpactSummary(file: file, impacts: fileImpacts)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                            .background(Color.bgCanvas)
                    }

                    // Hunks
                    ForEach(Array(file.hunks.enumerated()), id: \.offset) { idx, hunk in
                        HunkView(
                            hunk: hunk,
                            hunkIndex: idx,
                            file: file,
                            impacts: impactViewModel.impacts(for: hunk, fileId: file.id),
                            markers: impactViewModel.inlineMarkers(
                                for: hunk, file: file, hunkIndex: idx),
                            impactViewModel: impactViewModel,
                            isHighlighted: activeHunkIndex == idx,
                            activeTarget: activeTarget,
                            activeImpactRange: activeImpactRange,
                            onOpenImpact: onOpenImpact
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

struct ReviewImpactSummary: View {
    let impactViewModel: ImpactGraphViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.brandAccent)
                Text("Review Next")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(summaryLine)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }

            if impactViewModel.impacts.isEmpty {
                Text("No symbol-level impact data is available for this review.")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            } else {
                HStack(spacing: 10) {
                    ImpactStat(text: "\(impactViewModel.highImpactCount) high impact")
                    ImpactStat(text: "\(impactViewModel.totalImpactedReferenceCount) references")
                    ImpactStat(text: "\(impactViewModel.impactedFileCount) files")
                    ImpactStat(text: "\(impactViewModel.symbolsWithoutTestsCount) without tests")
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(impactViewModel.topImpacts.enumerated()), id: \.element.id) {
                        index, impact in
                        Text(
                            "\(index + 1). \(impact.symbol.name) - \(impact.summary.directCallerCount) callers"
                        )
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
    }

    private var summaryLine: String {
        let count = impactViewModel.impacts.count
        return "\(count) changed symbol\(count == 1 ? "" : "s")"
    }
}

struct FileImpactSummary: View {
    let file: ChangedFile
    let impacts: [SymbolImpact]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Impact Summary")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
            Text(
                "\(impacts.count) changed symbol\(impacts.count == 1 ? "" : "s") in \(file.filename), led by \(topNames)."
            )
            .font(.system(size: 12))
            .foregroundColor(.textSecondary)
            .lineLimit(2)
            Spacer()
        }
    }

    private var topNames: String {
        impacts.prefix(3).map(\.symbol.name).joined(separator: ", ")
    }
}

struct InlineImpactSummaryCard: View {
    let impact: SymbolImpact
    let marker: InlineImpactMarker?
    let impactViewModel: ImpactGraphViewModel?
    let onOpenImpact: (SymbolImpact) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(impact.summary.impactLevel.tintColor)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    BadgeView(
                        text: marker?.isContinuation == true
                            ? "Impact continued"
                            : "\(impact.summary.impactLevel.displayName) impact",
                        variant: impact.summary.impactLevel.badgeVariant)
                    Text(impact.symbol.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button("View graph") {
                        onOpenImpact(impact)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(.brandAccent)
                }

                Text(marker?.summary ?? fallbackSummary)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)

                if !mostAffected.isEmpty {
                    Text("Most affected: \(mostAffected)")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(9)
        .background(Color(NSColor.controlColor).opacity(0.30))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.borderMuted, lineWidth: 0.5))
    }

    init(
        impact: SymbolImpact, marker: InlineImpactMarker? = nil,
        impactViewModel: ImpactGraphViewModel? = nil,
        onOpenImpact: @escaping (SymbolImpact) -> Void = { _ in }
    ) {
        self.impact = impact
        self.marker = marker
        self.impactViewModel = impactViewModel
        self.onOpenImpact = onOpenImpact
    }

    private var fallbackSummary: String {
        "\(impact.summary.directCallerCount) callers · \(impact.summary.directCalleeCount) callees · \(impact.summary.fileCount) files · View graph"
    }

    private var mostAffected: String {
        impact.symbol.callers.prefix(3).map { caller in
            caller.components(separatedBy: ":").last ?? caller
        }
        .joined(separator: ", ")
    }
}

struct ImpactDetailPopover: View {
    let impact: SymbolImpact
    let impactViewModel: ImpactGraphViewModel?
    @State private var activeTab: ImpactDetailTab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Impact Detail")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Changed root")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                Text("\(impact.symbol.name) at \(impact.location)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.brandAccent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Picker("Impact detail", selection: $activeTab) {
                ForEach(ImpactDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch activeTab {
                case .overview:
                    ImpactOverviewTab(impact: impact)
                case .callers:
                    ImpactListTab(
                        title: "Callers",
                        emptyText: "No direct callers found for this changed root.",
                        rows: impact.symbol.callers,
                        connectionSuffix: "calls \(impact.symbol.name)")
                case .callees:
                    ImpactListTab(
                        title: "Callees",
                        emptyText: "No direct callees found for this changed root.",
                        rows: impact.symbol.callees,
                        connectionSuffix: "is called by \(impact.symbol.name)")
                case .graph:
                    if let impactViewModel {
                        ImpactGraphExplorer(impact: impact, viewModel: impactViewModel)
                    } else {
                        ImpactMiniGraph(impact: impact)
                    }
                case .tests:
                    ImpactTestsTab(impact: impact)
                }
            }
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(Color.bgCanvas)
    }
}

enum ImpactDetailTab: String, CaseIterable, Identifiable {
    case overview
    case callers
    case callees
    case graph
    case tests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .callers: "Callers"
        case .callees: "Callees"
        case .graph: "Graph"
        case .tests: "Tests"
        }
    }
}

struct ImpactOverviewTab: View {
    let impact: SymbolImpact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ImpactDetailLine(label: "Summary", value: summary)
            ImpactDetailLine(label: "Why this matters", value: whyThisMatters)
            if !mostImpacted.isEmpty {
                ImpactDetailLine(label: "Most impacted", value: mostImpacted)
            }
        }
    }

    private var summary: String {
        "\(impact.summary.impactLevel.displayName) impact because this changed root has \(impact.summary.directCallerCount) callers across \(impact.summary.fileCount) files."
    }

    private var whyThisMatters: String {
        if impact.summary.testReferenceCount == 0 && impact.summary.directCallerCount > 0 {
            return "Callers exist, but no direct test references were detected for this path."
        }
        return "Impact evidence is based on caller, callee, file, and test reference signals."
    }

    private var mostImpacted: String {
        impact.symbol.callers.prefix(3).map { caller in
            caller.components(separatedBy: ":").last ?? caller
        }
        .joined(separator: ", ")
    }
}

struct ImpactListTab: View {
    let title: String
    let emptyText: String
    let rows: [String]
    let connectionSuffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if rows.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            } else {
                ForEach(Array(rows.prefix(8).enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName(row))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        Text("Connection: \(displayName(row)) \(connectionSuffix)")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlColor).opacity(0.30))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func displayName(_ row: String) -> String {
        row.components(separatedBy: ":").last ?? row
    }
}

struct ImpactGraphExplorer: View {
    let impact: SymbolImpact
    @Bindable var viewModel: ImpactGraphViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Graph Focus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                Text("Current: \(viewModel.focusedNode?.title ?? impact.symbol.name)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text("Origin: \(impact.symbol.name) changed in this PR")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                Text("Path: \(viewModel.graphPathText)")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Button("Back") { viewModel.focusBack() }
                    .disabled(!viewModel.canGoBack)
                Button("Forward") { viewModel.focusForward() }
                    .disabled(!viewModel.canGoForward)
                Button("Origin") { viewModel.focusOrigin() }
                Button("Focus Selected") { viewModel.focusSelectedGraphNode() }
                    .disabled(viewModel.selectedGraphNode == nil)
                Picker("Direction", selection: $viewModel.graphDirection) {
                    ForEach(ImpactGraphDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .labelsHidden()
                .frame(width: 92)
            }
            .font(.system(size: 11))

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(viewModel.visibleGraphNodes) { node in
                        ImpactGraphNodeButton(
                            node: node,
                            isFocused: node.id == viewModel.currentFocusedNodeId,
                            isSelected: node.id == viewModel.selectedGraphNode?.id
                        ) {
                            viewModel.selectGraphNode(node)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let context = viewModel.selectedSourceContext {
                SymbolSourceContextPreview(context: context)
            }
        }
        .onAppear {
            viewModel.select(impact)
        }
    }
}

struct ImpactGraphNodeButton: View {
    let node: ImpactGraphNode
    let isFocused: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if node.role == .caller {
                        Image(systemName: "arrow.down.left")
                    } else if node.role == .callee {
                        Image(systemName: "arrow.down.right")
                    }
                    Text(node.title)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))

                Text(node.isChangedInPR ? "Changed in PR" : "Outside PR")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
            .foregroundColor(isFocused ? .white : .textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(width: 150, alignment: .leading)
            .background(isFocused ? Color.brandAccent : Color(NSColor.controlColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isSelected ? Color.brandAccent.opacity(0.8) : Color.borderMuted,
                    lineWidth: isSelected ? 1.2 : 0.5))
        }
        .buttonStyle(.plain)
        .help("\(node.filePath)\(node.line.map { ":L\($0)" } ?? "")")
    }
}

struct SymbolSourceContextPreview: View {
    let context: SymbolSourceContext

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Selected Symbol")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                Spacer()
                BadgeView(
                    text: context.isChangedInCurrentPR ? "Diff mode" : "Outside this PR",
                    variant: context.isChangedInCurrentPR ? .success : .neutral)
            }
            Text(context.symbolName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.textPrimary)
            Text("\(context.filePath):L\(context.startLine)-L\(context.endLine)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.brandAccent)
                .lineLimit(1)
                .truncationMode(.middle)
            if let callSiteLine = context.callSiteLine {
                Text("Connection to PR change: call site around L\(callSiteLine)")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            Text(context.excerpt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.textSecondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlColor).opacity(0.30))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct ImpactMiniGraph: View {
    let impact: SymbolImpact

    var body: some View {
        VStack(spacing: 8) {
            graphGroup(title: "Callers", rows: Array(impact.symbol.callers.prefix(3)))
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
            Text(impact.symbol.name)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.brandAccent.opacity(0.12))
                .clipShape(Capsule())
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
            graphGroup(title: "Callees", rows: Array(impact.symbol.callees.prefix(3)))
        }
        .frame(maxWidth: .infinity)
    }

    private func graphGroup(title: String, rows: [String]) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
            if rows.isEmpty {
                Text("None detected")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row.components(separatedBy: ":").last ?? row)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct ImpactTestsTab: View {
    let impact: SymbolImpact

    var testReferences: [String] {
        impact.symbol.callers.filter { caller in
            caller.localizedCaseInsensitiveContains("test")
                || caller.localizedCaseInsensitiveContains("spec")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if testReferences.isEmpty {
                ImpactDetailLine(
                    label: "Coverage signal",
                    value: "Weak. No direct test references were detected for this changed root.")
            } else {
                ImpactDetailLine(
                    label: "Coverage signal",
                    value:
                        "Partial. \(testReferences.count) direct test reference\(testReferences.count == 1 ? "" : "s") detected."
                )
                ForEach(Array(testReferences.prefix(6).enumerated()), id: \.offset) { _, test in
                    Text(test)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

struct ImpactDetailLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ImpactExplorerSidebar: View {
    @Bindable var impactViewModel: ImpactGraphViewModel
    let details: AnalysisDetails
    let onClose: () -> Void
    let onOpenImpact: (SymbolImpact) -> Void
    let onOpenNode: (ImpactGraphNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.brandAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Impact Explorer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(headerSubtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.textSecondary)
                .help("Collapse impact explorer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.bgSubtle)

            Divider()

            if impactViewModel.reviewQueue.isEmpty {
                ImpactExplorerEmptyState()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ImpactExplorerRootCard(
                            impact: impactViewModel.originImpact ?? impactViewModel.reviewQueue[0],
                            viewModel: impactViewModel,
                            onOpenRoot: {
                                if let impact = impactViewModel.originImpact {
                                    onOpenImpact(impact)
                                }
                            }
                        )

                        ImpactGraphMap(
                            viewModel: impactViewModel,
                            onOpenNode: onOpenNode
                        )

                        if let impact = impactViewModel.originImpact {
                            ImpactRelationshipSection(
                                impact: impact,
                                viewModel: impactViewModel,
                                onOpenNode: onOpenNode
                            )
                        }

                        if let context = impactViewModel.selectedSourceContext {
                            SymbolSourceContextPreview(context: context)
                            Button {
                                if let node = impactViewModel.selectedGraphNode {
                                    onOpenNode(node)
                                }
                            } label: {
                                Label(
                                    "Open selected symbol in diff",
                                    systemImage: "arrow.turn.down.right"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!(impactViewModel.selectedGraphNode?.isChangedInPR ?? false))
                        }
                    }
                    .padding(12)
                }
                .background(Color.bgCanvas)
            }
        }
        .background(Color.bgCanvas)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.borderMuted)
                .frame(width: 1)
        }
    }

    private var headerSubtitle: String {
        let count = impactViewModel.reviewQueue.count
        return "\(count) impacted changed symbol\(count == 1 ? "" : "s")"
    }
}

struct ImpactExplorerEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 24))
                .foregroundColor(.textTertiary)
            Text("No impact graph available")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("Changed symbols were found, but no caller or callee relationships were detected.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }
}

struct ImpactExplorerRootCard: View {
    let impact: SymbolImpact
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenRoot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                BadgeView(
                    text: "\(impact.summary.impactLevel.displayName) impact",
                    variant: impact.summary.impactLevel.badgeVariant)
                Text(impact.symbol.name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Spacer()
            }

            Text(impact.reason ?? "Review caller and callee relationships for this changed symbol.")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ImpactStat(text: "\(impact.summary.directCallerCount) callers")
                ImpactStat(text: "\(impact.summary.directCalleeCount) callees")
                ImpactStat(text: "\(impact.summary.fileCount) files")
            }

            HStack(spacing: 6) {
                Button("Previous") {
                    viewModel.selectPreviousImpact()
                    onOpenRoot()
                }
                Button("Next") {
                    viewModel.selectNextImpact()
                    onOpenRoot()
                }
                Button("Open Root") { onOpenRoot() }
                Spacer()
                Picker("Direction", selection: $viewModel.graphDirection) {
                    ForEach(ImpactGraphDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .labelsHidden()
                .frame(width: 98)
            }
            .font(.system(size: 11))
        }
        .padding(10)
        .background(Color(NSColor.controlColor).opacity(0.30))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
    }
}

struct ImpactGraphMap: View {
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    var callers: [ImpactGraphNode] {
        viewModel.visibleGraphNodes.filter { $0.role == .caller }
    }

    var callees: [ImpactGraphNode] {
        viewModel.visibleGraphNodes.filter { $0.role == .callee }
    }

    var origin: ImpactGraphNode? {
        viewModel.visibleGraphNodes.first { $0.role == .origin }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Graph")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                Spacer()
                Button("Back") { viewModel.focusBack() }
                    .disabled(!viewModel.canGoBack)
                Button("Forward") { viewModel.focusForward() }
                    .disabled(!viewModel.canGoForward)
                Button("Origin") { viewModel.focusOrigin() }
            }
            .font(.system(size: 11))

            VStack(spacing: 8) {
                ImpactGraphColumn(
                    title: "Callers",
                    emptyText: "No callers detected",
                    nodes: callers,
                    viewModel: viewModel,
                    onOpenNode: onOpenNode
                )

                if let origin {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                    ImpactExplorerNodeCard(
                        node: origin,
                        isFocused: origin.id == viewModel.currentFocusedNodeId,
                        isSelected: origin.id == viewModel.selectedGraphNode?.id,
                        viewModel: viewModel,
                        onOpenNode: onOpenNode
                    )
                }

                if !callees.isEmpty {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }

                ImpactGraphColumn(
                    title: "Callees",
                    emptyText: "No callees detected",
                    nodes: callees,
                    viewModel: viewModel,
                    onOpenNode: onOpenNode
                )
            }
            .padding(10)
            .background(Color(NSColor.controlColor).opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct ImpactGraphColumn: View {
    let title: String
    let emptyText: String
    let nodes: [ImpactGraphNode]
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
            if nodes.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else {
                ForEach(nodes) { node in
                    ImpactExplorerNodeCard(
                        node: node,
                        isFocused: node.id == viewModel.currentFocusedNodeId,
                        isSelected: node.id == viewModel.selectedGraphNode?.id,
                        viewModel: viewModel,
                        onOpenNode: onOpenNode
                    )
                }
            }
        }
    }
}

struct ImpactExplorerNodeCard: View {
    let node: ImpactGraphNode
    let isFocused: Bool
    let isSelected: Bool
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    var body: some View {
        Button {
            viewModel.selectGraphNode(node)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isFocused ? .white : .brandAccent)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(isFocused ? .white : .textPrimary)
                        .lineLimit(1)
                    Text(
                        "\(node.isChangedInPR ? "Changed in PR" : "Outside PR") · \(node.filePath)"
                    )
                    .font(.system(size: 10))
                    .foregroundColor(isFocused ? .white.opacity(0.8) : .textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Spacer()
                Button("Focus") {
                    viewModel.selectGraphNode(node)
                    viewModel.focusSelectedGraphNode()
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundColor(isFocused ? .white : .brandAccent)
                Button {
                    viewModel.selectGraphNode(node)
                    onOpenNode(node)
                } label: {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(isFocused ? .white : .textSecondary)
                .disabled(!node.isChangedInPR)
            }
            .padding(8)
            .background(isFocused ? Color.brandAccent : Color.bgCanvas)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).stroke(
                    isSelected ? Color.brandAccent.opacity(0.85) : Color.borderMuted,
                    lineWidth: isSelected ? 1.2 : 0.5))
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch node.role {
        case .origin: "dot.circle.fill"
        case .caller: "arrow.down.left"
        case .callee: "arrow.down.right"
        }
    }
}

struct ImpactRelationshipSection: View {
    let impact: SymbolImpact
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Impacted Code")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)

            ImpactRelationshipList(
                title: "Callers",
                rows: impact.symbol.callers,
                role: .caller,
                viewModel: viewModel,
                onOpenNode: onOpenNode
            )
            ImpactRelationshipList(
                title: "Callees",
                rows: impact.symbol.callees,
                role: .callee,
                viewModel: viewModel,
                onOpenNode: onOpenNode
            )
        }
    }
}

struct ImpactRelationshipList: View {
    let title: String
    let rows: [String]
    let role: ImpactGraphNode.Role
    @Bindable var viewModel: ImpactGraphViewModel
    let onOpenNode: (ImpactGraphNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textPrimary)
            if rows.isEmpty {
                Text("None detected")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(rows.prefix(8).enumerated()), id: \.offset) { _, row in
                    let node = nodeFromRow(row)
                    Button {
                        viewModel.selectGraphNode(node)
                        onOpenNode(node)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.title)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text(node.filePath)
                                .font(.system(size: 10))
                                .foregroundColor(.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlColor).opacity(0.24))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func nodeFromRow(_ row: String) -> ImpactGraphNode {
        let parts = row.components(separatedBy: ":")
        let filePath = parts.first ?? row
        let title = parts.last ?? row
        let line = parts.compactMap(Int.init).first
        if let existing = viewModel.visibleGraphNodes.first(where: {
            $0.filePath == filePath && $0.title == title && $0.role == role
        }) {
            return existing
        }
        return ImpactGraphNode(
            id: "\(filePath)#\(title)",
            title: title,
            filePath: filePath,
            line: line,
            role: role,
            isChangedInPR: false,
            isTest: row.localizedCaseInsensitiveContains("test")
                || row.localizedCaseInsensitiveContains("spec"))
    }
}

extension ImpactLevel {
    var tintColor: Color {
        switch self {
        case .low: .success
        case .medium: .warning
        case .high: .danger
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
    let file: ChangedFile
    let impacts: [SymbolImpact]
    let markers: [InlineImpactMarker]
    let impactViewModel: ImpactGraphViewModel
    let isHighlighted: Bool
    let activeTarget: ReviewTarget?
    let activeImpactRange: ClosedRange<Int>?
    let onOpenImpact: (SymbolImpact) -> Void
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
        guard let newLineNumber = line.newLineNumber else { return false }
        if let activeTarget,
            let start = activeTarget.lineStart
        {
            let end = activeTarget.lineEnd ?? start
            if newLineNumber >= start && newLineNumber <= end { return true }
        }
        if let activeImpactRange, activeImpactRange.contains(newLineNumber) {
            return true
        }
        return false
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
                                fileId: file.id, hunkIndex: hunkIndex, direction: .up)
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
                                    fileId: file.id, hunkIndex: hunkIndex, direction: .all)
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
                                fileId: file.id, hunkIndex: hunkIndex, direction: .down)
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
                    VStack(spacing: 0) {
                        ForEach(alignedDiffLines) { alignedLine in
                            inlineMarkerCards(for: alignedLine.newLine?.newLineNumber)
                            splitLineRow(alignedLine)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(diffLines) { line in
                            inlineMarkerCards(for: line.newLineNumber)
                            unifiedLineRow(line)
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

    @ViewBuilder
    private func inlineMarkerCards(for lineNumber: Int?) -> some View {
        if let lineNumber {
            let lineMarkers = markers.filter { $0.anchorLine == lineNumber }
            if !lineMarkers.isEmpty {
                VStack(spacing: 6) {
                    ForEach(lineMarkers.prefix(3)) { marker in
                        if let impact = impacts.first(where: { $0.id == marker.rootSymbolId }) {
                            InlineImpactSummaryCard(
                                impact: impact,
                                marker: marker,
                                impactViewModel: impactViewModel,
                                onOpenImpact: onOpenImpact)
                        }
                    }
                }
                .padding(.leading, state.diffLayout == .split ? 72 : 118)
                .padding(.trailing, 12)
                .padding(.vertical, 8)
                .background(Color.bgCanvas)
            }
        }
    }

    private func unifiedLineRow(_ line: NumberedDiffLine) -> some View {
        HStack(spacing: 0) {
            lineNumberColumn(
                line.oldLineNumber.map(String.init) ?? "", isTargeted: isTargeted(line)
            )
            .frame(width: 44, alignment: .trailing)
            lineNumberColumn(
                line.newLineNumber.map(String.init) ?? "", isTargeted: isTargeted(line)
            )
            .frame(width: 44, alignment: .trailing)
            prefixColumn(
                prefix(for: line), color: prefixColor(for: line), isTargeted: isTargeted(line))
            codeColumn(lineContent(for: line), line: line)
        }
        .background(Color.bgCanvas)
    }

    private func splitLineRow(_ alignedLine: AlignedDiffLine) -> some View {
        HStack(spacing: 0) {
            splitPaneLine(alignedLine.oldLine, isLeft: true)
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(Color.borderMuted)
                .frame(width: 1)
            splitPaneLine(alignedLine.newLine, isLeft: false)
                .frame(maxWidth: .infinity)
        }
        .background(Color.bgCanvas)
    }

    @ViewBuilder
    private func splitPaneLine(_ line: NumberedDiffLine?, isLeft: Bool) -> some View {
        HStack(spacing: 0) {
            if let line {
                let lineNumber = isLeft ? line.oldLineNumber : line.newLineNumber
                let targeted = isTargeted(line)
                lineNumberColumn(lineNumber.map(String.init) ?? "", isTargeted: targeted)
                    .frame(width: 44, alignment: .trailing)
                prefixColumn(prefix(for: line), color: prefixColor(for: line), isTargeted: targeted)
                codeColumn(lineContent(for: line), line: line)
            } else {
                lineNumberColumn("", isTargeted: false)
                    .frame(width: 44, alignment: .trailing)
                prefixColumn(" ", color: .textTertiary, isTargeted: false)
                Text(" ")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                    .background(Color.bgSubtle.opacity(0.15))
            }
        }
    }

    private func lineNumberColumn(_ text: String, isTargeted: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(isTargeted ? Color.warning : Color.textTertiary)
            .frame(minHeight: 17, alignment: .trailing)
            .padding(.trailing, 6)
            .background(
                isTargeted ? Color.warning.opacity(0.22) : Color.bgSubtle.opacity(0.65)
            )
            .textSelection(.disabled)
    }

    private func prefixColumn(_ text: String, color: Color, isTargeted: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(color)
            .frame(width: 18, alignment: .center)
            .frame(minHeight: 17)
            .background(
                isTargeted ? Color.warning.opacity(0.22) : Color.bgSubtle.opacity(0.65)
            )
            .textSelection(.disabled)
    }

    private func codeColumn(_ text: String, line: NumberedDiffLine) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(codeForeground(for: line))
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
            .background(codeBackground(for: line))
    }

    private func lineContent(for line: NumberedDiffLine) -> String {
        line.rawLine.isEmpty ? "" : String(line.rawLine.dropFirst())
    }

    private func prefix(for line: NumberedDiffLine) -> String {
        switch line.type {
        case .added: "+"
        case .deleted: "−"
        case .context: " "
        case .metadata: "\\"
        }
    }

    private func prefixColor(for line: NumberedDiffLine) -> Color {
        switch line.type {
        case .added: Color.diffAddedFg
        case .deleted: Color.danger
        case .context, .metadata: Color.textTertiary
        }
    }

    private func codeForeground(for line: NumberedDiffLine) -> Color {
        if isTargeted(line) { return Color.textPrimary }
        switch line.type {
        case .metadata:
            return Color.textTertiary
        case .context:
            return Color.textPrimary.opacity(0.75)
        case .added, .deleted:
            return Color.textPrimary
        }
    }

    private func codeBackground(for line: NumberedDiffLine) -> Color {
        if isTargeted(line) { return Color.warning.opacity(0.28) }
        switch line.type {
        case .added:
            return Color.diffAddedBg
        case .deleted:
            return Color.diffDeletedBg
        case .context, .metadata:
            return Color.clear
        }
    }
}

// MARK: - Diff Line Data Model

struct NumberedDiffLine: Identifiable {
    let id = UUID()
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
