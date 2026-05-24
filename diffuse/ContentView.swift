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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.18, green: 0.51, blue: 0.97), Color(red: 0.43, green: 0.25, blue: 0.79)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 26, height: 26)
                    Image(systemName: "arrow.triangle.pull")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                Text("diffuse")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.textPrimary, .accentBlue], startPoint: .leading, endPoint: .trailing)
                    )
                Spacer()
                Button {
                    Task { await state.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // PR List
            HStack {
                Text("PULL REQUESTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .kerning(0.5)
                Spacer()
                if state.isLoadingPRs {
                    LoadingSpinner(size: 12)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.pullRequests) { pr in
                        PRListItem(pr: pr, isSelected: state.selectedPRId == pr.id)
                            .onTapGesture {
                                Task { await state.selectPR(pr.id) }
                            }
                    }

                    if state.pullRequests.isEmpty && !state.isLoadingPRs {
                        EmptySidebarView(showAnalyzeSheet: $showAnalyzeSheet)
                    }
                }
            }

            Divider()

            // Analyze button
            Button {
                showAnalyzeSheet = true
            } label: {
                Label("Analyze Local Repo", systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentBlue)
            .padding(10)
        }
        .background(Color(NSColor.controlBackgroundColor))
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
                    BadgeView(text: "Risk: \(run.riskScore)", variant: run.riskScore >= 70 ? .danger : run.riskScore >= 40 ? .warning : .success)
                    Spacer()
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
        .background(Color(NSColor.windowBackgroundColor).ignoresSafeArea())
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
        .background(Color(NSColor.windowBackgroundColor))
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
                .background(Color(NSColor.controlColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
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
        .background(Color(NSColor.windowBackgroundColor))
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
                // Left pane: triage panels
                ScrollView {
                    VStack(spacing: 10) {
                        ReviewMapPanel(details: details)
                        SemanticBucketsPanel(details: details)
                        ReviewTargetsPanel(targets: state.bucketTargets)
                        SafeToSkimPanel(targets: details.skimTargets)
                    }
                    .padding(12)
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
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Analyze Repo Sheet

struct AnalyzeRepoSheet: View {
    @Environment(AppState.self) private var state
    @Binding var isPresented: Bool
    @State private var selectedPath: String = ""
    @State private var baseRef: String = ""

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
                            baseRef: baseRef.isEmpty ? nil : baseRef
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

