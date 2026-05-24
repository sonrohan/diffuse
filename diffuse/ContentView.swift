import SwiftUI
import AppKit

// MARK: - Main Content View

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showAnalyzeSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(showAnalyzeSheet: $showAnalyzeSheet)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            DetailView()
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowAccessor { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        })
        .sheet(isPresented: $showAnalyzeSheet) {
            AnalyzeRepoSheet(isPresented: $showAnalyzeSheet)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAnalyzeRepo)) { _ in
            showAnalyzeSheet = true
        }
        .task {
            await state.load()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Binding var showAnalyzeSheet: Bool
    @State private var isDraggingOver = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.bgSidebarPanel)
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.borderDefault.opacity(0.8), lineWidth: 0.5)
                        )
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentBlue)
                }
                Text("diffuse")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    Task { await state.refreshWorkspace() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh workspace state")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Workspaces Section Header (Codex Style)
                    HStack {
                        Text("WORKSPACES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .kerning(0.5)
                        
                        Spacer()
                        
                        // Add Workspace Button (Codex folder+ icon)
                        Button {
                            showAnalyzeSheet = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Add Workspace Folder")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Workspaces List
                    VStack(spacing: 4) {
                        ForEach(state.repositories) { repo in
                            let isActive = state.selectedRepoId == repo.id
                            
                            WorkspaceRow(
                                repo: repo,
                                isActive: isActive,
                                onSelect: {
                                    Task { await state.selectRepo(repo.id) }
                                },
                                onRemove: {
                                    Task {
                                        await state.coordinator.deleteRepository(id: repo.id)
                                        await state.load()
                                    }
                                },
                                onOpenInFinder: {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: repo.path))
                                },
                                onRename: { newName in
                                    Task {
                                        await state.renameWorkspace(id: repo.id, newName: newName)
                                    }
                                },
                                onToggleAutoAnalyze: { enabled in
                                    Task {
                                        await state.setWorkspaceAutoAnalyze(id: repo.id, enabled: enabled)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)

                    // Active Workspace Context
                    if let selectedRepo = state.selectedRepo {
                        Divider()
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            // Section Header indicating active repository
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentBlue)
                                Text(selectedRepo.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 4)

                            BranchOverviewCard(
                                repoPath: selectedRepo.path,
                                branch: state.selectedBranch ?? "main",
                                summary: state.selectedBranchSummary,
                                branches: state.localBranches
                            )
                            .padding(.horizontal, 12)
                            
                            // Commits Timeline
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("COMMITS")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.textTertiary)
                                        .kerning(0.5)
                                    Spacer()
                                    if state.isLoadingPRs || state.isLoadingAnalysis {
                                        LoadingSpinner(size: 10)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 4)
                                
                                VStack(spacing: 0) {
                                    ChangeSummaryRow(
                                        fileCount: state.analysisDetails?.files.count ?? 0,
                                        isSelected: state.selectedCommitSha == nil
                                    )
                                    .onTapGesture {
                                        Task { await state.selectCommit(nil) }
                                    }
                                    
                                    ForEach(Array(state.commits.enumerated()), id: \.element.sha) { idx, commit in
                                        CommitListItem(
                                            subject: commit.subject,
                                            author: commit.author,
                                            date: commit.date,
                                            sha: String(commit.sha.prefix(7)),
                                            isSelected: state.selectedCommitSha == commit.sha,
                                            index: idx + 1
                                        )
                                        .onTapGesture {
                                            Task { await state.selectCommit(commit.sha) }
                                        }
                                    }
                                    
                                    if state.commits.isEmpty && !state.isLoadingPRs {
                                        Text("No commits on branch.")
                                            .font(.system(size: 10))
                                            .foregroundColor(.textTertiary)
                                            .italic()
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                }
                                .background(Color.bgSidebarPanel)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.borderMuted, lineWidth: 0.5))
                                .padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }

            // Collapsible Triaged History list
            if !state.pullRequests.isEmpty {
                Divider()
                
                DisclosureGroup {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.pullRequests) { pr in
                                PRListItem(pr: pr, isSelected: state.selectedPRId == pr.id)
                                    .onTapGesture {
                                        Task { await state.selectPR(pr.id) }
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                        Text("Triaged History (\(state.pullRequests.count))")
                            .font(.system(size: 10, weight: .bold))
                            .kerning(0.3)
                    }
                    .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Color.bgSidebar)
        // Modern Drag-and-Drop Workspace Receiver
        .onDrop(of: ["public.file-url"], isTargeted: $isDraggingOver) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url = url, url.isFileURL else { return }
                let path = url.path
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    Task { @MainActor in
                        await state.analyzeRepo(path: path)
                    }
                }
            }
            return true
        }
        .overlay(
            Group {
                if isDraggingOver {
                    ZStack {
                        Color.accentBlue.opacity(0.12)
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(Color.accentBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundColor(.accentBlue)
                            Text("Drop to Add Workspace")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.accentBlue)
                        }
                    }
                    .transition(.opacity)
                }
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.borderDefault.opacity(0.9))
                .frame(width: 1)
        }
    }
}

struct PRListItem: View {
    let pr: PullRequest
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .accentBlue : .textSecondary)
                Text("#\(pr.prNumber)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isSelected ? .accentBlue : .textSecondary)
                Text(pr.repository)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(pr.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let run = pr.latestRun {
                HStack {
                    Text(run.status.rawValue.capitalized)
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                    statusDot(run.status)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentBlue.opacity(0.08) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? Color.accentBlue : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func statusDot(_ status: AnalysisRun.RunStatus) -> some View {
        let color: Color = switch status {
        case .completed: .successColor
        case .analyzing: .warningColor
        case .failed: .dangerColor
        case .queued: .textTertiary
        }
        Circle().fill(color).frame(width: 6, height: 6)
    }
}

struct EmptySidebarView: View {
    @Binding var showAnalyzeSheet: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 28))
                .foregroundColor(.textTertiary)
            Text("No PRs analyzed yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            Text("Click below to analyze a local git repo")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }
}

// MARK: - Detail View

struct DetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if let details = state.analysisDetails {
                AnalysisDetailView(details: details)
                    .transition(.opacity)
            } else if state.isLoadingAnalysis || state.isAnalyzing {
                loadingView
            } else if state.pullRequests.isEmpty {
                welcomeView
            } else {
                noSelectionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas.ignoresSafeArea())
    }

    var loadingView: some View {
        VStack(spacing: 12) {
            LoadingSpinner(size: 28)
            Text(state.isAnalyzing ? "Running analysis…" : "Loading analysis…")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
            if let error = state.analysisError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.dangerColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }

    var welcomeView: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(
                        colors: [Color.accentBlue.opacity(0.15), Color.accentPurple.opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [.accentBlue, .accentPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            VStack(spacing: 6) {
                Text("Welcome to diffuse")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("A deterministic PR review triage tool.\nAnalyze any local git repo to get started.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Text("Use ⌘O or the sidebar button to analyze a local repo.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.bgSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }

    var noSelectionView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.textTertiary)
            Text("No PR selected")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text("Select a pull request from the sidebar")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }
}

// MARK: - Analysis Detail

struct AnalysisDetailView: View {
    @Environment(AppState.self) private var state
    let details: AnalysisDetails

    var body: some View {
        VStack(spacing: 0) {
            // PR Header bar
            PRHeaderBar(pr: details.pr, run: details.run)

            Divider()

            HStack(spacing: 0) {
                // Left pane: review navigation
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 12) {
                            AnalysisNavigationRail(details: details)
                            SafeToSkimPanel(targets: details.skimTargets)
                        }
                        .padding(12)
                    }
                }
                .frame(width: 360)

                Divider()

                // Right pane: context + diff
                VStack(spacing: 0) {
                    SelectedContextBar(details: details)
                    Divider()
                    DiffViewerPanel(details: details)
                }
            }
        }
        .background(Color.bgCanvas)
    }
}

// MARK: - Analyze Repo Sheet

struct AnalyzeRepoSheet: View {
    @Environment(AppState.self) private var state
    @Binding var isPresented: Bool
    @State private var selectedPath: String = ""
    @State private var baseRef: String = ""
    @State private var autoAnalyzeEnabled = true

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 20))
                        .foregroundColor(.accentBlue)
                    Text("Analyze Local Repo")
                        .font(.system(size: 17, weight: .semibold))
                }
                Text("Run diffuse analysis on a local git repository.")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 8) {
                Text("Repository Path")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)

                HStack(spacing: 8) {
                    TextField("Select a folder…", text: $selectedPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Select"
                        if panel.runModal() == .OK {
                            selectedPath = panel.url?.path ?? ""
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Base Ref (optional)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Text("— e.g. main, HEAD~3, a1b2c3d")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                TextField("main", text: $baseRef)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            Toggle("Auto-analyze local changes while app is open", isOn: $autoAnalyzeEnabled)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            if state.isAnalyzing {
                HStack(spacing: 8) {
                    LoadingSpinner(size: 16)
                    Text("Analyzing…")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
            }

            if let error = state.analysisError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.dangerColor)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.dangerColor)
                }
                .padding(10)
                .background(Color.dangerBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Analyze") {
                    Task {
                        await state.analyzeRepo(
                            path: selectedPath.isEmpty ? FileManager.default.currentDirectoryPath : selectedPath,
                            baseRef: baseRef.isEmpty ? nil : baseRef,
                            autoAnalyzeEnabled: autoAnalyzeEnabled
                        )
                        if state.analysisError == nil {
                            isPresented = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentBlue)
                .disabled(state.isAnalyzing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - Window Accessor Helper
struct WindowAccessor: NSViewRepresentable {
    var onChange: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onChange(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Branch Overview

struct BranchOverviewCard: View {
    @Environment(AppState.self) private var state

    let repoPath: String
    let branch: String
    let summary: LocalBranchSummary?
    let branches: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Menu {
                ForEach(branches, id: \.self) { branchName in
                    Button(branchName) {
                        Task { await state.selectBranch(branchName) }
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentBlue)
                        .frame(width: 14)

                    Text(branch)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 2)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .help(branch)

            if let summary {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        BranchInlineMeta(icon: "clock", text: summary.lastUpdated)
                        BranchInlineMeta(icon: "person", text: summary.lastAuthor)
                    }

                    if let upstream = summary.upstream, !upstream.isEmpty {
                        BranchInlineMeta(icon: "arrow.up.right", text: upstream)
                    }
                }
            } else {
                BranchInlineMeta(icon: "arrow.triangle.branch", text: "Local branch")
            }

            HStack(spacing: 5) {
                if summary?.isDirty == true {
                    BranchStatusPill(text: "Dirty", color: .accentPurple)
                }
                if let summary, summary.aheadCount > 0 {
                    BranchStatusPill(text: "Ahead \(summary.aheadCount)", color: .successColor)
                }
                if let summary, summary.behindCount > 0 {
                    BranchStatusPill(text: "Behind \(summary.behindCount)", color: .warningColor)
                }
            }
        }
        .padding(10)
        .background(Color.bgSidebarPanel)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.borderMuted, lineWidth: 0.5))
    }
}

struct BranchInlineMeta: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .frame(width: 10)
            Text(text)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundColor(.textTertiary)
        .help(text)
    }
}

struct BranchStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.5))
    }
}

struct ChangeSummaryRow: View {
    let fileCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sum")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.accentBlue)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("Cumulative Diff")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text(fileCount == 1 ? "1 file" : "\(fileCount) files")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
                Text("All branch and working tree changes")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentBlue.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Commit List Item View
struct CommitListItem: View {
    let subject: String
    let author: String
    let date: String
    let sha: String
    let isSelected: Bool
    let index: Int?

    var body: some View {
        HStack(spacing: 8) {
            // Vertical timeline graph node
            VStack(spacing: 0) {
                // Line above
                Rectangle()
                    .fill(index == 1 ? Color.clear : Color.borderMuted)
                    .frame(width: 1.5, height: 8)
                
                // Timeline node dot
                Circle()
                    .fill(isSelected ? (index == nil ? Color.accentBlue : Color.accentPurple) : Color.borderDefault)
                    .frame(width: 8, height: 8)
                
                // Line below
                Rectangle()
                    .fill(Color.borderMuted)
                    .frame(width: 1.5, height: 16)
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(subject)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    if let idx = index {
                        Text("C\(idx)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentPurple)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentPurple.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Text("ALL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentBlue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentBlue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    
                    if !sha.isEmpty {
                        Text(sha)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }

                    if !author.isEmpty {
                        Text(author)
                            .font(.system(size: 10))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(date)
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentBlue.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Workspace Row View (Codex Style)
struct WorkspaceRow: View {
    let repo: GitRepository
    let isActive: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onOpenInFinder: () -> Void
    let onRename: (String) -> Void
    let onToggleAutoAnalyze: (Bool) -> Void
    
    @State private var isHovered = false
    @State private var showRenameAlert = false
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "folder.fill" : "folder")
                .font(.system(size: 13))
                .foregroundColor(isActive ? .accentBlue : .textSecondary)

            Text(repo.name)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            
            Spacer()
            
            if isHovered {
                HStack(spacing: 6) {
                    Image(systemName: repo.autoAnalyzeEnabled ? "bolt.circle.fill" : "bolt.slash")
                        .font(.system(size: 10))
                        .foregroundColor(repo.autoAnalyzeEnabled ? .accentBlue : .textTertiary)
                        .help(repo.autoAnalyzeEnabled ? "Auto-analyze is on" : "Auto-analyze is off")

                    // Open in Finder
                    Button {
                        onOpenInFinder()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Finder")

                    // Context Menu Trigger
                    Menu {
                        Button("Open in Finder") { onOpenInFinder() }
                        Button("Rename Workspace…") {
                            newName = repo.name
                            showRenameAlert = true
                        }
                        Button(repo.autoAnalyzeEnabled ? "Turn Off Auto-Analyze" : "Turn On Auto-Analyze") {
                            onToggleAutoAnalyze(!repo.autoAnalyzeEnabled)
                        }
                        Divider()
                        Button("Remove Workspace", role: .destructive) { onRemove() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 16, height: 16)
                    .help("Workspace actions")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentBlue.opacity(0.06) : (isHovered ? Color(NSColor.controlColor).opacity(0.4) : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Open in Finder") { onOpenInFinder() }
            Button("Rename Workspace…") {
                newName = repo.name
                showRenameAlert = true
            }
            Button(repo.autoAnalyzeEnabled ? "Turn Off Auto-Analyze" : "Turn On Auto-Analyze") {
                onToggleAutoAnalyze(!repo.autoAnalyzeEnabled)
            }
            Divider()
            Button("Remove Workspace", role: .destructive) { onRemove() }
        }
        .sheet(isPresented: $showRenameAlert) {
            VStack(spacing: 16) {
                Text("Rename Workspace")
                    .font(.system(size: 14, weight: .semibold))
                TextField("Workspace Name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showRenameAlert = false }
                    Spacer()
                    Button("Rename") {
                        onRename(newName)
                        showRenameAlert = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 280)
        }
    }
}
