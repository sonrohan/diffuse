import SwiftUI
import AppKit

// MARK: - Main Content View

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showAnalyzeSheet = false

    var body: some View {
        VStack(spacing: 0) {
            AppHeaderView(showAnalyzeSheet: $showAnalyzeSheet)
            Divider()
            DetailView()
        }
        .frame(minWidth: 950, minHeight: 600)
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

// MARK: - App Header View

struct AppHeaderView: View {
    @Environment(AppState.self) private var state
    @Binding var showAnalyzeSheet: Bool
    
    @State private var showRenameAlert = false
    @State private var newName = ""
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Spacer to avoid macOS traffic lights window controls
            Spacer()
                .frame(width: 16)
            
            // Logo & Title
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.bgSidebarPanel)
                        .frame(width: 22, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.borderDefault.opacity(0.8), lineWidth: 0.5)
                        )
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentBlue)
                }
                Text("diffuse")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            .padding(.trailing, 16)
            
            Divider()
                .frame(height: 20)
                .padding(.trailing, 16)
            
            // Workspace selector
            Menu {
                // List workspaces
                ForEach(state.repositories) { repo in
                    Button {
                        Task { await state.selectRepo(repo.id) }
                    } label: {
                        if state.selectedRepoId == repo.id {
                            Text("✓ \(repo.name)")
                        } else {
                            Text(repo.name)
                        }
                    }
                }
                
                if let selectedRepo = state.selectedRepo {
                    Divider()
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: selectedRepo.path))
                    }
                    Button("Rename Workspace…") {
                        newName = selectedRepo.name
                        showRenameAlert = true
                    }
                    Button(selectedRepo.autoAnalyzeEnabled ? "Turn Off Auto-Analyze" : "Turn On Auto-Analyze") {
                        Task {
                            await state.setWorkspaceAutoAnalyze(id: selectedRepo.id, enabled: !selectedRepo.autoAnalyzeEnabled)
                        }
                    }
                    Divider()
                    Button("Remove Workspace", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
                
                Divider()
                Button("Add Workspace…") {
                    showAnalyzeSheet = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentBlue)
                    Text(state.selectedRepo?.name ?? "Select Workspace")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            
            // Branch Selector
            if let selectedRepo = state.selectedRepo {
                Divider()
                    .frame(height: 20)
                    .padding(.trailing, 16)
                
                Menu {
                    ForEach(state.localBranches, id: \.self) { branch in
                        Button {
                            Task { await state.selectBranch(branch) }
                        } label: {
                            if state.selectedBranch == branch {
                                Text("✓ \(branch)")
                            } else {
                                Text(branch)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .foregroundColor(.accentBlue)
                        Text(state.selectedBranch ?? "main")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                        
                        if selectedRepo.autoAnalyzeEnabled {
                            Text("Live")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.accentBlue)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentBlue.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                
                // Commit / Review Scope cycling controls
                if !state.commits.isEmpty {
                    Divider()
                        .frame(height: 20)
                        .padding(.trailing, 16)
                    
                    HStack(spacing: 4) {
                        // Previous commit
                        Button {
                            goToPreviousCommit()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(canGoToPreviousCommit ? .textPrimary : .textTertiary)
                                .frame(width: 20, height: 20)
                                .background(Color.bgSidebarPanel.opacity(canGoToPreviousCommit ? 1.0 : 0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.borderDefault.opacity(0.8), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canGoToPreviousCommit)
                        .help("Previous Commit")
                        
                        // Custom Dropdown menu showing current commit / scope
                        ZStack {
                            // 1. The custom styled label that determines size and supports responsive ViewThatFits
                            ViewThatFits(in: .horizontal) {
                                // Expanded layout: shows badge + commit subject + custom chevron
                                HStack(spacing: 5) {
                                    if state.selectedCommitSha == nil {
                                        Image(systemName: "sum")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.accentBlue)
                                        Text("All Changes")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                    } else {
                                        let activeIdx = state.commits.firstIndex(where: { $0.sha == state.selectedCommitSha }) ?? 0
                                        let activeCommit = state.commits[activeIdx]
                                        Text("C\(activeIdx + 1)")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.accentPurple)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.accentPurple.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                        Text(activeCommit.subject)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                            .lineLimit(1)
                                            .frame(maxWidth: 220, alignment: .leading)
                                    }
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.textTertiary)
                                }
                                
                                // Compact fallback layout: only shows badge + custom chevron
                                HStack(spacing: 5) {
                                    if state.selectedCommitSha == nil {
                                        Image(systemName: "sum")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.accentBlue)
                                        Text("All")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                    } else {
                                        let activeIdx = state.commits.firstIndex(where: { $0.sha == state.selectedCommitSha }) ?? 0
                                        Text("C\(activeIdx + 1)")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.accentPurple)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.accentPurple.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Color.bgSidebarPanel)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.borderDefault.opacity(0.8), lineWidth: 0.5)
                            )
                            
                            // 2. The native menu, made completely transparent, sitting on top to intercept clicks
                            Menu {
                                Button {
                                    Task { await state.selectCommit(nil) }
                                } label: {
                                    if state.selectedCommitSha == nil {
                                        Text("✓ All Changes")
                                    } else {
                                        Text("All Changes")
                                    }
                                }
                                
                                Divider()
                                
                                ForEach(Array(state.commits.enumerated()), id: \.element.sha) { idx, commit in
                                    Button {
                                        Task { await state.selectCommit(commit.sha) }
                                    } label: {
                                        if state.selectedCommitSha == commit.sha {
                                            Text("✓ C\(idx + 1): \(commit.subject)")
                                        } else {
                                            Text("C\(idx + 1): \(commit.subject)")
                                        }
                                    }
                                }
                            } label: {
                                Rectangle()
                                    .fill(Color.white.opacity(0.0001))
                                    .frame(maxHeight: 20)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .buttonStyle(.plain)
                        }
                        
                        // Next commit
                        Button {
                            goToNextCommit()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(canGoToNextCommit ? .textPrimary : .textTertiary)
                                .frame(width: 20, height: 20)
                                .background(Color.bgSidebarPanel.opacity(canGoToNextCommit ? 1.0 : 0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.borderDefault.opacity(0.8), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canGoToNextCommit)
                        .help("Next Commit")
                    }
                }
            }
            
            Spacer()
            
            // Loading and Action buttons
            HStack(spacing: 12) {
                if state.isLoadingPRs || state.isLoadingAnalysis || state.isAnalyzing {
                    LoadingSpinner(size: 12)
                }
                
                if state.selectedRepo != nil {
                    Button {
                        Task { await state.reRunAnalysis() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Analyze latest")
                }
                
                Button {
                    // Settings placeholder action
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.trailing, 16)
        }
        .frame(height: 40)
        .background(Color.bgSidebar)
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
                        if let selectedRepo = state.selectedRepo {
                            Task {
                                await state.renameWorkspace(id: selectedRepo.id, newName: newName)
                            }
                        }
                        showRenameAlert = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 280)
        }
        .confirmationDialog(
            "Are you sure you want to remove this workspace?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Workspace", role: .destructive) {
                if let selectedRepo = state.selectedRepo {
                    Task {
                        await state.coordinator.deleteRepository(id: selectedRepo.id)
                        await state.load()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the workspace from diffuse. Your local Git repository and files will not be deleted.")
        }
    }
    
    // MARK: - Cycling Helpers
    
    private func goToPreviousCommit() {
        guard let sha = state.selectedCommitSha else { return }
        guard let idx = state.commits.firstIndex(where: { $0.sha == sha }) else { return }
        if idx == 0 {
            Task { await state.selectCommit(nil) }
        } else {
            Task { await state.selectCommit(state.commits[idx - 1].sha) }
        }
    }
    
    private func goToNextCommit() {
        if state.selectedCommitSha == nil {
            if let first = state.commits.first {
                Task { await state.selectCommit(first.sha) }
            }
        } else if let sha = state.selectedCommitSha,
                  let idx = state.commits.firstIndex(where: { $0.sha == sha }) {
            if idx < state.commits.count - 1 {
                Task { await state.selectCommit(state.commits[idx + 1].sha) }
            }
        }
    }
    
    private var canGoToPreviousCommit: Bool {
        return state.selectedCommitSha != nil && !state.commits.isEmpty
    }
    
    private var canGoToNextCommit: Bool {
        if state.commits.isEmpty { return false }
        if state.selectedCommitSha == nil { return true }
        if let sha = state.selectedCommitSha,
           let idx = state.commits.firstIndex(where: { $0.sha == sha }) {
            return idx < state.commits.count - 1
        }
        return false
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
            Text("Use ⌘O or the header dropdown to analyze a local repo.")
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
            Text("Select a workspace or branch to load analysis.")
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
    @State private var navRailWidth: CGFloat = 360

    var body: some View {
        HStack(spacing: 0) {
            // Left pane: review navigation
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        if !details.symbolReviewGroups.isEmpty {
                            SymbolReviewMapPanel(details: details)
                        }
                        AnalysisNavigationRail(details: details)
                    }
                    .padding(12)
                }
            }
            .frame(width: navRailWidth)

            PaneDivider(width: $navRailWidth, minWidth: 220, maxWidth: 560)

            // Right pane: context + diff
            VStack(spacing: 0) {
                SelectedContextBar(details: details)
                Divider()
                DiffViewerPanel(details: details)
            }
        }
        .background(Color.bgCanvas)
    }
}

// MARK: - Resizable Pane Divider

/// A thin draggable handle that adjusts a pane's width.
struct PaneDivider: View {
    @Binding var width: CGFloat
    var minWidth: CGFloat = 160
    var maxWidth: CGFloat = 800
    @State private var isDragging = false
    @State private var startingWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentBlue.opacity(0.55) : Color.borderDefault.opacity(0.9))
            .frame(width: 1)
            .overlay(
                // Wider invisible hit area for easy grabbing
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    startingWidth = width
                                }
                                let proposed = startingWidth + value.translation.width
                                width = max(minWidth, min(maxWidth, proposed))
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            )
            .animation(.easeInOut(duration: 0.1), value: isDragging)
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


