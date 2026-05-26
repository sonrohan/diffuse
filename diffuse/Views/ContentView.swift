import AppKit
import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.locale) private var locale
    @State private var showAnalyzeSheet = false

    var body: some View {
        VStack(spacing: 0) {
            AppHeaderView(showAnalyzeSheet: $showAnalyzeSheet)
            Divider()
            DetailView()
        }
        .frame(minWidth: 950, minHeight: 600)
        .background(
            WindowAccessor { window in
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
        )
        .sheet(isPresented: $showAnalyzeSheet) {
            AnalyzeRepoSheet(isPresented: $showAnalyzeSheet)
                .environment(\.locale, locale)
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
    @Environment(\.locale) private var locale
    @Binding var showAnalyzeSheet: Bool

    @State private var showRenameAlert = false
    @State private var newName = ""
    @State private var showDeleteConfirmation = false
    @State private var showSettingsSheet = false
    @State private var settingsInitialTab: SettingsSheet.SettingsTab = .general
    @State private var isWorkspacePickerPresented = false
    @State private var isBranchPickerPresented = false
    @State private var isCommitPickerPresented = false
    @State private var commitVM: CommitScopeViewModel? = nil

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
            HeaderPickerButton(isPresented: $isWorkspacePickerPresented) {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentBlue)
                    if let repo = state.selectedRepo {
                        Text(repo.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    } else {
                        Text("Select Workspace")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .popover(isPresented: $isWorkspacePickerPresented, arrowEdge: .bottom) {
                WorkspacePickerPopover(
                    isPresented: $isWorkspacePickerPresented,
                    showAnalyzeSheet: $showAnalyzeSheet,
                    showRenameAlert: $showRenameAlert,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    newName: $newName
                )
                .environment(\.locale, locale)
            }
            .padding(.trailing, 16)

            // Branch Selector
            if let selectedRepo = state.selectedRepo {
                Divider()
                    .frame(height: 20)
                    .padding(.trailing, 16)

                HeaderPickerButton(isPresented: $isBranchPickerPresented) {
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
                .popover(isPresented: $isBranchPickerPresented, arrowEdge: .bottom) {
                    BranchPickerPopover(isPresented: $isBranchPickerPresented)
                        .environment(\.locale, locale)
                }
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
                                .foregroundColor(
                                    canGoToPreviousCommit ? .textPrimary : .textTertiary
                                )
                                .frame(width: 20, height: 20)
                                .background(
                                    Color.bgSidebarPanel.opacity(canGoToPreviousCommit ? 1.0 : 0.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.borderDefault.opacity(0.8), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canGoToPreviousCommit)
                        .help("Previous Commit")

                        // Review scope picker
                        HeaderPickerButton(isPresented: $isCommitPickerPresented) {
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
                                        let activeIdx =
                                            state.commits.firstIndex(where: {
                                                $0.sha == state.selectedCommitSha
                                            }) ?? 0
                                        let activeCommit = state.commits[activeIdx]
                                        Text("C\(activeIdx + 1)")
                                            .font(
                                                .system(size: 9, weight: .bold, design: .monospaced)
                                            )
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
                                        let activeIdx =
                                            state.commits.firstIndex(where: {
                                                $0.sha == state.selectedCommitSha
                                            }) ?? 0
                                        Text("C\(activeIdx + 1)")
                                            .font(
                                                .system(size: 9, weight: .bold, design: .monospaced)
                                            )
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
                        }
                        .popover(isPresented: $isCommitPickerPresented, arrowEdge: .bottom) {
                            CommitScopePickerPopover(isPresented: $isCommitPickerPresented)
                                .environment(\.locale, locale)
                        }

                        // Next commit
                        Button {
                            goToNextCommit()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(canGoToNextCommit ? .textPrimary : .textTertiary)
                                .frame(width: 20, height: 20)
                                .background(
                                    Color.bgSidebarPanel.opacity(canGoToNextCommit ? 1.0 : 0.5)
                                )
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
                    settingsInitialTab = .general
                    showSettingsSheet = true
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
        .background(Color.bgToolbar)
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
            .environment(\.locale, locale)
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
            Text(
                "This will remove the workspace from diffuse. Your local Git repository and files will not be deleted."
            )
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheet(isPresented: $showSettingsSheet, initialTab: settingsInitialTab)
                .environment(\.locale, locale)
        }
        .onAppear {
            if commitVM == nil {
                commitVM = CommitScopeViewModel(state: state)
            }
        }
    }

    // MARK: - Cycling Helpers

    private func goToPreviousCommit() {
        Task { await commitVM?.goToPreviousCommit() }
    }

    private func goToNextCommit() {
        Task { await commitVM?.goToNextCommit() }
    }

    private var canGoToPreviousCommit: Bool {
        commitVM?.canGoToPreviousCommit ?? false
    }

    private var canGoToNextCommit: Bool {
        commitVM?.canGoToNextCommit ?? false
    }
}

// MARK: - Header Pickers

struct HeaderPickerButton<Label: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

struct WorkspacePickerPopover: View {
    @Environment(AppState.self) private var state
    @Binding var isPresented: Bool
    @Binding var showAnalyzeSheet: Bool
    @Binding var showRenameAlert: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var newName: String

    @State private var viewModel: WorkspacePickerViewModel? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel {
                WorkspacePickerContent(
                    viewModel: viewModel,
                    isPresented: $isPresented,
                    showAnalyzeSheet: $showAnalyzeSheet,
                    showRenameAlert: $showRenameAlert,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    newName: $newName
                )
            } else {
                ProgressView()
                    .padding(24)
                    .onAppear {
                        viewModel = WorkspacePickerViewModel(state: state)
                    }
            }
        }
        .frame(width: state.repositories.isEmpty ? 300 : 420)
    }
}

struct WorkspacePickerContent: View {
    @Bindable var viewModel: WorkspacePickerViewModel
    @Binding var isPresented: Bool
    @Binding var showAnalyzeSheet: Bool
    @Binding var showRenameAlert: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var newName: String

    var body: some View {
        if viewModel.repositories.isEmpty {
            EmptyWorkspaceAddView {
                showAnalyzeSheet = true
                isPresented = false
            }
        } else {
            PickerHeader(
                title: "Workspaces",
                count: viewModel.repositories.count,
                query: $viewModel.query,
                placeholder: "Search names or paths"
            )

            Picker("Workspace filter", selection: $viewModel.filter) {
                ForEach(WorkspaceFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            PickerDivider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.visibleRepositories) { repo in
                            WorkspaceRow(
                                repo: repo, isSelected: repo.id == viewModel.selectedRepoId
                            ) {
                                Task { await viewModel.selectRepo(repo.id) }
                                isPresented = false
                            }
                            .id(repo.id)
                        }

                        if viewModel.visibleRepositories.isEmpty {
                            EmptyPickerState(
                                icon: "folder.badge.questionmark", text: "No workspaces match")
                        }
                    }
                    .padding(8)
                }
                .frame(height: 280)
                .onAppear {
                    if let selected = viewModel.selectedRepoId {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }

            PickerDivider()

            HStack(spacing: 8) {
                Button {
                    showAnalyzeSheet = true
                    isPresented = false
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Spacer()

                if let selectedRepo = viewModel.selectedRepo {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: selectedRepo.path))
                        isPresented = false
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help("Open in Finder")

                    Button {
                        newName = selectedRepo.name
                        showRenameAlert = true
                        isPresented = false
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Rename Workspace")

                    Button {
                        Task {
                            await viewModel.setWorkspaceAutoAnalyze(
                                id: selectedRepo.id, enabled: !selectedRepo.autoAnalyzeEnabled)
                        }
                    } label: {
                        Image(systemName: selectedRepo.autoAnalyzeEnabled ? "bolt.slash" : "bolt")
                    }
                    .buttonStyle(.borderless)
                    .help(
                        selectedRepo.autoAnalyzeEnabled
                            ? "Turn Off Auto-Analyze" : "Turn On Auto-Analyze")

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                        isPresented = false
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove Workspace")
                }
            }
            .padding(12)
        }
    }
}

struct EmptyWorkspaceAddView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .regular))
                .foregroundColor(.accentBlue)

            VStack(spacing: 4) {
                Text("Add Workspace")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Choose a local Git repository to analyze.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onAdd()
            } label: {
                Label("Add Workspace", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 300)
    }
}

struct WorkspaceRow: View {
    let repo: GitRepository
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "folder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .accentBlue : .textTertiary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(repo.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        if repo.autoAnalyzeEnabled {
                            PickerBadge("Live", color: .accentBlue)
                        }
                    }
                    Text(repo.path)
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentBlue.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct BranchPickerPopover: View {
    @Environment(AppState.self) private var state
    @Binding var isPresented: Bool
    @State private var viewModel: BranchPickerViewModel? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel {
                BranchPickerContent(viewModel: viewModel, isPresented: $isPresented)
            } else {
                ProgressView()
                    .padding(24)
                    .onAppear {
                        viewModel = BranchPickerViewModel(state: state)
                    }
            }
        }
        .frame(width: 500)
    }
}

struct BranchPickerContent: View {
    @Bindable var viewModel: BranchPickerViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            PickerHeader(
                title: "Branches",
                count: viewModel.visibleSummaries.count,
                query: $viewModel.query,
                placeholder: "Search branch, author, PR, upstream"
            )

            Picker("Branch filter", selection: $viewModel.filter) {
                ForEach(BranchFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            PickerDivider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.visibleSummaries) { summary in
                            BranchRow(
                                summary: summary,
                                isSelected: summary.branch == viewModel.selectedBranch
                            ) {
                                Task { await viewModel.selectBranch(summary.branch) }
                                isPresented = false
                            }
                            .id(summary.branch)
                        }

                        if viewModel.visibleSummaries.isEmpty {
                            EmptyPickerState(
                                icon: "arrow.triangle.branch", text: "No branches match")
                        }
                    }
                    .padding(8)
                }
                .frame(height: 330)
                .onAppear {
                    if let selected = viewModel.selectedBranch {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }
        }
    }
}

struct BranchRow: View {
    let summary: LocalBranchSummary
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .accentBlue : .textTertiary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(summary.branch)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if summary.isDirty { PickerBadge("Dirty", color: .warningColor) }
                        if summary.aheadCount > 0 {
                            PickerBadge("↑\(summary.aheadCount)", color: .successColor)
                        }
                        if summary.behindCount > 0 {
                            PickerBadge("↓\(summary.behindCount)", color: .dangerColor)
                        }
                        if let number = summary.relatedPRNumber {
                            PickerBadge("#\(number)", color: .accentPurple)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(summary.lastUpdated)
                        Text("by \(summary.lastAuthor)")
                        if let upstream = summary.upstream {
                            Text("• \(upstream)")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)

                    if let title = summary.relatedPRTitle {
                        Text(title)
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentBlue.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct CommitScopePickerPopover: View {
    @Environment(AppState.self) private var state
    @Binding var isPresented: Bool
    @State private var viewModel: CommitScopeViewModel? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel {
                CommitScopePickerContent(viewModel: viewModel, isPresented: $isPresented)
            } else {
                ProgressView()
                    .padding(24)
                    .onAppear {
                        viewModel = CommitScopeViewModel(state: state)
                    }
            }
        }
        .frame(width: 520)
    }
}

struct CommitScopePickerContent: View {
    @Bindable var viewModel: CommitScopeViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            PickerHeader(
                title: "Review Scope",
                count: viewModel.commits.count,
                query: $viewModel.query,
                placeholder: "Search C#, subject, author, sha"
            )

            Picker("Commit filter", selection: $viewModel.filter) {
                ForEach(CommitFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            PickerDivider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        CommitAllChangesRow(isSelected: viewModel.selectedCommitSha == nil) {
                            Task { await viewModel.selectCommit(nil) }
                            isPresented = false
                        }
                        .id("all-changes")

                        if !viewModel.visibleCommits.isEmpty {
                            SectionLabel("Commits")
                        }

                        ForEach(viewModel.visibleCommits, id: \.element.sha) { idx, commit in
                            CommitRow(
                                index: idx + 1,
                                commit: commit,
                                isSelected: commit.sha == viewModel.selectedCommitSha
                            ) {
                                Task { await viewModel.selectCommit(commit.sha) }
                                isPresented = false
                            }
                            .id(commit.sha)
                        }

                        if viewModel.visibleCommits.isEmpty {
                            EmptyPickerState(
                                icon: "clock.arrow.circlepath", text: "No commits match")
                        }
                    }
                    .padding(8)
                }
                .frame(height: 360)
                .onAppear {
                    proxy.scrollTo(viewModel.selectedCommitSha ?? "all-changes", anchor: .center)
                }
            }

            PickerDivider()

            HStack(spacing: 8) {
                Button {
                    viewModel.query = ""
                    viewModel.filter = .all
                } label: {
                    Label("Reset", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    if let first = viewModel.commits.first {
                        Task { await viewModel.selectCommit(first.sha) }
                        isPresented = false
                    }
                } label: {
                    Label("First", systemImage: "backward.end")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.commits.isEmpty)

                Button {
                    if let last = viewModel.commits.last {
                        Task { await viewModel.selectCommit(last.sha) }
                        isPresented = false
                    }
                } label: {
                    Label("Latest", systemImage: "forward.end")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.commits.isEmpty)
            }
            .padding(12)
        }
    }
}

struct CommitAllChangesRow: View {
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "sum")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .accentBlue : .textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text("All Changes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Review the full branch diff")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentBlue.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct CommitRow: View {
    let index: Int
    let commit: GitCommit
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .accentBlue : .textTertiary)
                    .frame(width: 18)

                Text("C\(index)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentPurple)
                    .frame(width: 40, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.subject)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(commit.author)
                        Text("• \(commit.date)")
                        Text("• \(commit.sha.prefix(8))")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentBlue.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct PickerHeader: View {
    let title: String
    let count: Int
    @Binding var query: String
    let placeholder: String

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("\(count) total")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.bgSidebarPanel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.borderMuted, lineWidth: 0.5))
        }
        .padding(12)
    }
}

struct PickerBadge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

struct EmptyPickerState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.textTertiary)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

struct PickerDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderMuted)
            .frame(height: 0.5)
    }
}

extension String {
    fileprivate func fuzzyContains(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = localizedLowercase
        let needles = trimmed.localizedLowercase.split(whereSeparator: \.isWhitespace)
        return needles.allSatisfy { haystack.contains($0) }
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
            if state.isAnalyzing {
                Text("Running analysis…")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
            } else {
                Text("Loading analysis…")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
            }
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
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentBlue.opacity(0.15), Color.accentPurple.opacity(0.1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentBlue, .accentPurple], startPoint: .topLeading,
                            endPoint: .bottomTrailing)
                    )
            }
            VStack(spacing: 6) {
                Text("Welcome to diffuse")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(
                    "A deterministic PR review triage tool.\nAnalyze any local git repo to get started."
                )
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
    @State private var viewModel: AnalysisViewModel? = nil

    var body: some View {
        Group {
            if let viewModel {
                HStack(spacing: 0) {
                    // Left pane: review navigation
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 12) {
                                AnalysisNavigationRail(details: details)
                            }
                            .padding(12)
                        }
                        .background(Color.bgSidebar)
                    }
                    .frame(width: navRailWidth)
                    .background(Color.bgSidebar)

                    PaneDivider(width: $navRailWidth, minWidth: 220, maxWidth: 560)

                    // Right pane: context + diff
                    VStack(spacing: 0) {
                        SelectedContextBar(details: details)
                        Divider()
                        DiffViewerPanel(details: details)
                    }
                }
                .environment(viewModel)
            } else {
                VStack {
                    LoadingSpinner(size: 24)
                    Text("Configuring workspace...")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    viewModel = AnalysisViewModel(state: state)
                }
            }
        }
        .background(Color.bgCanvas)
        .onChange(of: state.analysisDetails?.run.id) { _, _ in
            viewModel?.refreshIfNecessary()
        }
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
    @State private var createProfileIfMissing = true
    @State private var selectedPresetId = "generic"
    @State private var isProfileWizardPresented = false
    @State private var isProfileRulesPresented = false
    @State private var profileMessage: String?

    private var resolvedPath: String {
        selectedPath.isEmpty ? FileManager.default.currentDirectoryPath : selectedPath
    }

    private var repoName: String {
        URL(fileURLWithPath: resolvedPath).lastPathComponent
    }

    private var hasProfile: Bool {
        AnalysisProfileStore.hasRepoProfile(repoPath: resolvedPath)
    }

    private var detectedPresetId: String {
        AnalysisProfileStore.detectBuiltInProfileId(repoPath: resolvedPath)
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
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

            VStack(alignment: .leading, spacing: 12) {
                workspacePathSection
                profileSetupSection
                analysisOptionsSection
            }

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
                        if createProfileIfMissing && !hasProfile {
                            do {
                                try AnalysisProfileStore.writeProfile(
                                    repoPath: resolvedPath, presetId: selectedPresetId)
                            } catch {
                                profileMessage =
                                    "Could not create .diffuse.json: \(error.localizedDescription)"
                            }
                        }
                        await state.analyzeRepo(
                            path: resolvedPath,
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
        .frame(width: 560)
        .onAppear {
            selectedPresetId = detectedPresetId
        }
        .onChange(of: selectedPath) { _, _ in
            selectedPresetId = detectedPresetId
            profileMessage = nil
        }
        .sheet(isPresented: $isProfileWizardPresented) {
            AnalysisProfileWizard(repoName: repoName, repoPath: resolvedPath) { presetId in
                selectedPresetId = presetId
                createProfileIfMissing = false
                profileMessage = "Created .diffuse.json using \(presetId)"
            }
        }
        .sheet(isPresented: $isProfileRulesPresented) {
            AnalysisProfileRulesSheet(repoName: repoName, repoPath: resolvedPath)
        }
    }

    private var workspacePathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repository")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textSecondary)

            HStack(spacing: 8) {
                TextField("Select a folder…", text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Select"
                    if panel.runModal() == .OK {
                        selectedPath = panel.url?.path ?? ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Browse")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var profileSetupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Analysis Profile")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(hasProfile ? "Repo-defined" : "Preset to copy")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(hasProfile ? .successColor : .accentBlue)
            }

            HStack(spacing: 10) {
                Image(systemName: hasProfile ? "checkmark.seal.fill" : "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(hasProfile ? .successColor : .accentBlue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hasProfile ? ".diffuse.json found" : presetDisplayName(selectedPresetId))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(
                        hasProfile
                            ? "Diffuse will use this repo's configured rules and groupings."
                            : "Diffuse will copy \(selectedPresetId) into a flat .diffuse.json."
                    )
                    .font(.system(size: 10.5))
                    .foregroundColor(.textSecondary)
                }

                Spacer()

                Button {
                    isProfileRulesPresented = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .help("Edit active analysis profile")

                if !hasProfile {
                    Button {
                        isProfileWizardPresented = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("Choose")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(10)
            .background(Color.bgSidebarPanel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))

            if !hasProfile {
                Toggle("Create .diffuse.json before first analysis", isOn: $createProfileIfMissing)
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)
            }

            if let profileMessage {
                Text(profileMessage)
                    .font(.system(size: 10.5))
                    .foregroundColor(
                        profileMessage.hasPrefix("Could not") ? .dangerColor : .textSecondary)
            }
        }
    }

    private var analysisOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Base Ref")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textSecondary)
                    Text("optional")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
                TextField("main, HEAD~3, a1b2c3d", text: $baseRef)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            Toggle("Auto-analyze local changes while app is open", isOn: $autoAnalyzeEnabled)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func presetDisplayName(_ id: String) -> String {
        AnalysisProfileStore.builtInPresets.first { $0.id == id }?.displayName ?? id
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
