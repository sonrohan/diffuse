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
    @AppStorage("minImpactFilter") private var minImpactFilter = "all"

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

            // Filter by minimum impact level
            if minImpactFilter != "all" {
                guard let ind = impactViewModel.fileImpactIndicators[file.id] else {
                    return false
                }
                if minImpactFilter == "high" && ind.highCount == 0 {
                    return false
                }
                if minImpactFilter == "medium" && ind.highCount == 0 && ind.mediumCount == 0 {
                    return false
                }
            }

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

                Menu {
                    Button {
                        minImpactFilter = "all"
                    } label: {
                        HStack {
                            Text("All Files")
                            if minImpactFilter == "all" { Image(systemName: "checkmark") }
                        }
                    }
                    Button {
                        minImpactFilter = "medium"
                    } label: {
                        HStack {
                            Text("Medium & High Impact")
                            if minImpactFilter == "medium" { Image(systemName: "checkmark") }
                        }
                    }
                    Button {
                        minImpactFilter = "high"
                    } label: {
                        HStack {
                            Text("High Impact Only")
                            if minImpactFilter == "high" { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.shield")
                            .font(.system(size: 11, weight: .semibold))
                        Text(
                            minImpactFilter == "all"
                                ? "All" : (minImpactFilter == "medium" ? "Med+" : "High")
                        )
                        .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.textTertiary)
                    }
                    .foregroundColor(minImpactFilter != "all" ? .brandAccent : .textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        minImpactFilter != "all"
                            ? Color.brandAccent.opacity(0.10)
                            : Color(NSColor.controlColor).opacity(0.45)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(
                                minImpactFilter != "all"
                                    ? Color.brandAccent.opacity(0.35) : Color.borderMuted,
                                lineWidth: 0.5)
                    )
                }
                .menuStyle(.borderlessButton)
                .help("Filter files by AST impact level")

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
                    impactViewModel: impactViewModel
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
        minImpactFilter = "all"
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
    let impactViewModel: ImpactGraphViewModel
    var width: CGFloat = 220
    @State private var collapsedFolders: Set<String> = []
    @State private var expandedFileIds: Set<UUID> = []

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
                        expandedFileIds: $expandedFileIds,
                        compactTree: compactTree,
                        impactViewModel: impactViewModel
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

    func aggregateImpact(impactIndicators: [UUID: FileImpactIndicator]) -> FileImpactIndicator? {
        var totalCount = 0
        var totalHighCount = 0
        var totalMediumCount = 0
        var totalCallerCount = 0
        var totalChangedHighImpactCount = 0
        var totalWeakTestCount = 0

        for file in files {
            if let ind = impactIndicators[file.id] {
                totalCount += ind.count
                totalHighCount += ind.highCount
                totalMediumCount += ind.mediumCount
                totalCallerCount += ind.callerCount
                totalChangedHighImpactCount += ind.changedHighImpactCount
                totalWeakTestCount += ind.weakTestCount
            }
        }

        for child in children {
            if let ind = child.aggregateImpact(impactIndicators: impactIndicators) {
                totalCount += ind.count
                totalHighCount += ind.highCount
                totalMediumCount += ind.mediumCount
                totalCallerCount += ind.callerCount
                totalChangedHighImpactCount += ind.changedHighImpactCount
                totalWeakTestCount += ind.weakTestCount
            }
        }

        guard totalCount > 0 else { return nil }
        return FileImpactIndicator(
            count: totalCount,
            highCount: totalHighCount,
            mediumCount: totalMediumCount,
            callerCount: totalCallerCount,
            changedHighImpactCount: totalChangedHighImpactCount,
            weakTestCount: totalWeakTestCount
        )
    }

    func folderHeatmapColor(impactIndicators: [UUID: FileImpactIndicator]) -> Color {
        guard let agg = aggregateImpact(impactIndicators: impactIndicators) else {
            return .clear
        }
        if agg.highCount > 0 { return .danger }
        if agg.mediumCount > 0 { return .warning }
        return .clear
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
    @Binding var expandedFileIds: Set<UUID>
    let compactTree: Bool
    let impactViewModel: ImpactGraphViewModel
    let onSelectFile: (ChangedFile) -> Void

    var impactIndicators: [UUID: FileImpactIndicator] {
        impactViewModel.fileImpactIndicators
    }

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

                    if isCollapsed,
                        let aggImpact = node.aggregateImpact(impactIndicators: impactIndicators)
                    {
                        Text("\(aggImpact.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(aggImpact.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(aggImpact.color.opacity(0.10))
                            .clipShape(Capsule())
                            .help(aggImpact.helpText)
                    } else {
                        Text("\(node.fileCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }
                }
                .padding(.leading, CGFloat(min(depth, 4)) * 12 + 8)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    let color = node.folderHeatmapColor(impactIndicators: impactIndicators)
                    Rectangle()
                        .fill(color)
                        .frame(width: 3)
                }
            }
            .buttonStyle(.plain)
            .help(node.path)

            if !isCollapsed {
                ForEach(node.files) { file in
                    FileListItem(
                        file: file,
                        isActive: activeFile?.id == file.id,
                        depth: depth + 1,
                        impactViewModel: impactViewModel,
                        expandedFileIds: $expandedFileIds,
                        onSelectFile: onSelectFile
                    )
                }

                ForEach(node.children) { child in
                    FileTreeNodeView(
                        node: child,
                        depth: depth + 1,
                        activeFile: activeFile,
                        collapsedFolders: $collapsedFolders,
                        expandedFileIds: $expandedFileIds,
                        compactTree: compactTree,
                        impactViewModel: impactViewModel,
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
    let impactViewModel: ImpactGraphViewModel
    @Binding var expandedFileIds: Set<UUID>
    let onSelectFile: (ChangedFile) -> Void

    var fileTargets: [ReviewTarget] {
        viewModel.bucketTargets.filter { $0.filePath == file.path }
    }

    var topTargetSeverity: Severity? {
        fileTargets.map(\.severity).max()
    }

    var fileImpacts: [SymbolImpact] {
        impactViewModel.visibleImpacts(for: file)
    }

    var heatmapColor: Color {
        guard let ind = impactViewModel.fileImpactIndicators[file.id] else { return .clear }
        if ind.highCount > 0 { return .danger }
        if ind.mediumCount > 0 { return .warning }
        return .clear
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // Expanded Chevron
                if !fileImpacts.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if expandedFileIds.contains(file.id) {
                                expandedFileIds.remove(file.id)
                            } else {
                                expandedFileIds.insert(file.id)
                            }
                        }
                    } label: {
                        Image(
                            systemName: expandedFileIds.contains(file.id)
                                ? "chevron.down" : "chevron.right"
                        )
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }

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

                if let impactIndicator = impactViewModel.fileImpactIndicators[file.id] {
                    impactBadge(impactIndicator)
                }
            }
            .padding(.leading, CGFloat(min(depth, 4)) * 12 + 10)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(isActive ? Color.brandAccent.opacity(0.08) : Color.clear)
            .overlay(alignment: .leading) {
                let barColor = isActive && heatmapColor == .clear ? Color.brandAccent : heatmapColor
                Rectangle()
                    .fill(barColor)
                    .frame(width: 3)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectFile(file)
            }
            .help(fileHelpText)

            if expandedFileIds.contains(file.id) {
                ForEach(fileImpacts) { impact in
                    SymbolListItemRow(
                        impact: impact,
                        depth: depth + 1,
                        onTap: {
                            impactViewModel.select(impact)
                            viewModel.isImpactInspectorVisible = true
                            viewModel.jumpToImpactRoot(impact)
                        }
                    )
                }
            }
        }
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

struct SymbolListItemRow: View {
    let impact: SymbolImpact
    let depth: Int
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 12)  // Alignment with chevron

            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundColor(iconColor)

            Text(impact.symbol.name)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(impact.summary.impactLevel.displayName)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(levelColor(impact.summary.impactLevel))
                .padding(.horizontal, 4)
                .padding(.vertical, 0.5)
                .background(levelColor(impact.summary.impactLevel).opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.leading, CGFloat(min(depth, 5)) * 12 + 10)
        .padding(.trailing, 8)
        .padding(.vertical, 3.5)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var iconName: String {
        switch impact.symbol.kind {
        case .function, .method:
            return "f.circle.fill"
        case .class:
            return "c.circle.fill"
        case .struct, .enum, .type, .protocol:
            return "s.circle.fill"
        default:
            return "square.stack.3d.down.right.fill"
        }
    }

    private var iconColor: Color {
        switch impact.symbol.kind {
        case .function, .method:
            return .brandAccent
        case .class, .struct, .type, .protocol, .enum:
            return .warning
        default:
            return .textTertiary
        }
    }

    private func levelColor(_ level: ImpactLevel) -> Color {
        switch level {
        case .high: return .danger
        case .medium: return .warning
        case .low: return .success
        }
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

struct SymbolSourceContextPreview: View {
    let context: SymbolSourceContext
    @Bindable var impactViewModel: ImpactGraphViewModel
    @State private var isShowingFullFileSheet = false
    @State private var isCollapsed = false

    var filename: String {
        (context.filePath as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)

                    Text("Source Preview")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .textCase(.uppercase)

                    Spacer()

                    if !isCollapsed {
                        BadgeView(
                            text: context.isChangedInCurrentPR ? "Diff mode" : "Outside this PR",
                            variant: context.isChangedInCurrentPR ? .success : .neutral)
                    } else {
                        Text(context.symbolName)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.brandAccent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.symbolName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text("\(filename):L\(context.startLine)-L\(context.endLine)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.brandAccent)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button {
                            isShowingFullFileSheet = true
                        } label: {
                            Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.brandAccent)
                    }

                    if let callSiteLine = context.callSiteLine {
                        Text("Connection: call site around L\(callSiteLine)")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                    }

                    // Interactive Code block
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(
                                impactViewModel.showFullFile
                                    ? "Source File Preview" : "Call Site Context"
                            )
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.textSecondary)

                            Spacer()

                            Button(action: {
                                withAnimation {
                                    impactViewModel.showFullFile.toggle()
                                    impactViewModel.loadSourceCodeForSelectedNode()
                                }
                            }) {
                                Text(impactViewModel.showFullFile ? "Show Context" : "Show All")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.brandAccent)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.bgSubtle)

                        Divider()

                        if impactViewModel.isLoadingSourceCode {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Reading workspace file...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textTertiary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .background(Color.bgSidebarPanel.opacity(0.25))
                        } else if let error = impactViewModel.sourceCodeError {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.warning)
                                    Text("Local file not readable")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.textPrimary)
                                }
                                Text(error)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textSecondary)

                                Divider().padding(.vertical, 4)

                                // Fallback excerpt
                                Text(context.excerpt)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(10)
                            .background(Color.warning.opacity(0.08))
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 1) {
                                    ForEach(impactViewModel.selectedSourceLines) { line in
                                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                                            Text("\(line.lineNumber)")
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundColor(
                                                    line.isHighlighted
                                                        ? .brandAccent : .textTertiary
                                                )
                                                .frame(width: 30, alignment: .trailing)
                                                .padding(.trailing, 2)

                                            Text(line.text.isEmpty ? " " : line.text)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundColor(.textPrimary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.vertical, 0.5)
                                        .padding(.horizontal, 6)
                                        .background(
                                            line.isHighlighted
                                                ? Color.brandAccent.opacity(0.12) : Color.clear)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .frame(maxHeight: 200)
                            .background(Color.bgSidebarPanel.opacity(0.2))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $isShowingFullFileSheet) {
            FullFileCodeSheet(
                title: context.symbolName,
                filePath: context.filePath,
                lines: impactViewModel.selectedSourceLines,
                onDismiss: { isShowingFullFileSheet = false }
            )
        }
    }
}

struct FullFileCodeSheet: View {
    let title: String
    let filePath: String
    let lines: [SourceCodeLine]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(filePath)
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.bgSubtle)

            Divider()

            // Large scrollable code view
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(line.lineNumber)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(
                                        line.isHighlighted ? .brandAccent : .textTertiary
                                    )
                                    .frame(width: 38, alignment: .trailing)
                                    .padding(.trailing, 4)

                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 1)
                            .padding(.horizontal, 8)
                            .background(
                                line.isHighlighted ? Color.brandAccent.opacity(0.12) : Color.clear
                            )
                            .id(line.lineNumber)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color.bgCanvas)
                .onAppear {
                    // Scroll to the highlighted line!
                    if let highlighted = lines.first(where: \.isHighlighted) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(highlighted.lineNumber, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 450)
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

                        if let context = impactViewModel.selectedSourceContext {
                            SymbolSourceContextPreview(
                                context: context, impactViewModel: impactViewModel)
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
        HStack(spacing: 0) {
            // Visual accent bar
            Rectangle()
                .fill(impact.summary.impactLevel.tintColor)
                .frame(width: 4)
                .clipShape(Capsule())
                .padding(.vertical, 8)
                .padding(.leading, 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    BadgeView(
                        text: "\(impact.summary.impactLevel.displayName) impact",
                        variant: impact.summary.impactLevel.badgeVariant)
                    Text(impact.symbol.name)
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.top, 2)

                Text(
                    impact.reason
                        ?? "Review caller and callee relationships for this changed symbol."
                )
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

                // Stats strip
                HStack(spacing: 12) {
                    Label(
                        "\(impact.summary.directCallerCount) callers",
                        systemImage: "arrow.down.left")
                    Label(
                        "\(impact.summary.directCalleeCount) callees",
                        systemImage: "arrow.down.right")
                    Label("\(impact.summary.fileCount) files", systemImage: "doc.on.doc")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.textTertiary)
                .imageScale(.small)
                .padding(.vertical, 2)

                Divider()
                    .opacity(0.6)

                // Actions toolbar
                HStack(spacing: 6) {
                    Button(action: {
                        viewModel.selectPreviousImpact()
                        onOpenRoot()
                    }) {
                        Label("Previous", systemImage: "arrow.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        viewModel.selectNextImpact()
                        onOpenRoot()
                    }) {
                        Label("Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onOpenRoot) {
                        Label("Open Root", systemImage: "target")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Picker("Direction", selection: $viewModel.graphDirection) {
                        ForEach(ImpactGraphDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .controlSize(.small)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(Color.bgSidebarPanel.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderMuted, lineWidth: 0.5)
        )
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
                Label("Graph Explorer", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                Spacer()

                // Navigation history buttons
                HStack(spacing: 4) {
                    Button(action: { viewModel.focusBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .disabled(!viewModel.canGoBack)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Go back in history")

                    Button(action: { viewModel.focusForward() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .disabled(!viewModel.canGoForward)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Go forward in history")

                    Button(action: { viewModel.focusOrigin() }) {
                        Image(systemName: "house")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reset to PR Origin symbol")
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 6) {
                ImpactGraphColumn(
                    title: "Callers",
                    emptyText: "No callers detected",
                    nodes: callers,
                    viewModel: viewModel,
                    onOpenNode: onOpenNode
                )

                if let origin {
                    HStack {
                        Spacer()
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textTertiary.opacity(0.6))
                        Spacer()
                    }
                    .padding(.vertical, 2)

                    ImpactExplorerNodeCard(
                        node: origin,
                        isFocused: origin.id == viewModel.currentFocusedNodeId,
                        isSelected: origin.id == viewModel.selectedGraphNode?.id,
                        viewModel: viewModel,
                        onOpenNode: onOpenNode
                    )
                }

                if !callees.isEmpty {
                    HStack {
                        Spacer()
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textTertiary.opacity(0.6))
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }

                ImpactGraphColumn(
                    title: "Callees",
                    emptyText: "No callees detected",
                    nodes: callees,
                    viewModel: viewModel,
                    onOpenNode: onOpenNode
                )
            }
            .padding(8)
            .background(Color.bgSidebarPanel.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5)
            )
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

    var filename: String {
        (node.filePath as NSString).lastPathComponent
    }

    var body: some View {
        Button {
            viewModel.selectGraphNode(node)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isFocused ? .white : .brandAccent)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(node.title)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(isFocused ? .white : .textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if node.isChangedInPR {
                            Text("PR")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(isFocused ? .white : .success)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 0.5)
                                .background(
                                    isFocused
                                        ? Color.white.opacity(0.2) : Color.success.opacity(0.12)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        } else if node.isTest {
                            Image(systemName: "flask")
                                .font(.system(size: 9))
                                .foregroundColor(isFocused ? .white : .textTertiary)
                        }
                    }

                    Text("\(filename)\(node.line.map { ":L\($0)" } ?? "")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(isFocused ? .white.opacity(0.8) : .textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if isSelected {
                    HStack(spacing: 4) {
                        if node.id != viewModel.currentFocusedNodeId {
                            Button {
                                viewModel.selectGraphNode(node)
                                viewModel.focusSelectedGraphNode()
                            } label: {
                                Image(systemName: "scope")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isFocused ? .white : .brandAccent)
                            .help("Focus Graph on this node")
                        }

                        if node.isChangedInPR {
                            Button {
                                viewModel.selectGraphNode(node)
                                onOpenNode(node)
                            } label: {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(isFocused ? .white : .textSecondary)
                            .help("Open in diff viewer")
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isFocused ? Color.brandAccent : Color.bgSidebarPanel.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(
                    isSelected ? Color.brandAccent.opacity(0.85) : Color.borderMuted,
                    lineWidth: isSelected ? 1.0 : 0.5))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .help("\(node.filePath)\(node.line.map { ":L\($0)" } ?? "")")
    }

    private var iconName: String {
        if node.isTest { return "flask.fill" }
        return switch node.role {
        case .origin: "dot.circle.fill"
        case .caller: "arrow.down.left"
        case .callee: "arrow.down.right"
        }
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
