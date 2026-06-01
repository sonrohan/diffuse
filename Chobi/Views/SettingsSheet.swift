import AppKit
import SwiftUI

struct SettingsSheet: View {
    var isPresented: Binding<Bool>?
    @Environment(AppState.self) private var state
    @AppStorage("appTheme") private var appTheme = "System"
    @AppStorage("defaultLanguage") private var defaultLanguage = "Auto Detect"

    @State private var selectedTab: SettingsTab
    @State private var hoveredTab: SettingsTab? = nil
    @State private var hoveredTheme: AppTheme? = nil
    @State private var mcpViewModel: MCPSettingsViewModel? = nil

    // Cache clearing states
    @State private var showClearConfirmation = false
    @State private var cacheClearedSuccessfully = false

    // Status dot animation state
    @State private var pulseScale: CGFloat = 1.0

    // Workspace Management States
    @State private var selectedRepoId: UUID? = nil
    @State private var repoAlias: String = ""
    @State private var isAutoAnalyzeEnabled: Bool = true
    @State private var showDeleteWorkspaceConfirmation = false

    init(isPresented: Binding<Bool>? = nil, initialTab: SettingsTab = .general) {
        self.isPresented = isPresented
        self._selectedTab = State(initialValue: initialTab)
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case workspaces = "Workspaces"
        case agentAccess = "MCP"
        case appearance = "Appearance"

        var id: String { self.rawValue }

        var iconName: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .workspaces: return "folder.fill"
            case .agentAccess: return "network"
            case .appearance: return "paintpalette.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar Navigation Pane
            sidebarPane

            // Vertical Divider
            Divider()

            // Right Details Panel
            detailsPane
        }
        .frame(width: 760, height: 620)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            initializeWorkspaceSelection()
            if mcpViewModel == nil {
                mcpViewModel = MCPSettingsViewModel(state: state)
            }
        }
        .onChange(of: selectedRepoId) { _, newId in
            loadSelectedWorkspaceDetails(newId)
        }
    }

    // MARK: - Initializer Helpers

    private func initializeWorkspaceSelection() {
        if selectedRepoId == nil {
            selectedRepoId = state.selectedRepoId ?? state.repositories.first?.id
        }
        loadSelectedWorkspaceDetails(selectedRepoId)
    }

    private func loadSelectedWorkspaceDetails(_ id: UUID?) {
        guard let repoId = id,
            let repo = state.repositories.first(where: { $0.id == repoId })
        else { return }
        repoAlias = repo.name
        isAutoAnalyzeEnabled = repo.autoAnalyzeEnabled
    }

    // MARK: - Sidebar Navigation Pane

    private var sidebarPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETTINGS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 14)
                .padding(.top, 18)

            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    let isHovered = hoveredTab == tab

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isSelected ? .brandAccent : .textSecondary)
                                .frame(width: 16, height: 16)

                            Text(LocalizedStringKey(tab.rawValue))
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? .textPrimary : .textSecondary)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    isSelected
                                        ? Color.brandAccent.opacity(0.10)
                                        : (isHovered
                                            ? Color.textPrimary.opacity(0.04) : Color.clear))
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredTab = hovering ? tab : nil
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Helpful note at bottom of sidebar
            VStack(alignment: .leading, spacing: 4) {
                let version = Bundle.main.appVersion
                let build = Bundle.main.appBuildNumber
                Text("Version \(version) (\(build))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
        .frame(width: 170)
        .background(Color.bgSidebar)
    }

    // MARK: - Right Details Pane

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.brandAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(state.selectedRepo?.name ?? "Global Configuration")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let isPresented = isPresented {
                Button("Done") {
                    isPresented.wrappedValue = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
    }

    private var detailsPane: some View {
        VStack(spacing: 0) {
            header
            Divider()

            // Tab Content Frame
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .general:
                        generalView
                    case .workspaces:
                        workspacesView
                    case .agentAccess:
                        if let mcpViewModel {
                            MCPSettingsView(viewModel: mcpViewModel)
                        }
                    case .appearance:
                        appearanceView
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - General Tab View

    private var generalView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // AST Sidecar Status Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                        .foregroundColor(.brandAccent)
                    Text("AST Analysis Engine")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    Spacer()

                    // Status Badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 5, height: 5)
                            .scaleEffect(pulseScale)
                            .onAppear {
                                withAnimation(
                                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                                ) {
                                    pulseScale = 1.4
                                }
                            }

                        Text("Active (Local)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.success)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.successBg)
                    .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Parses symbols and signatures locally using high-fidelity Tree-sitter AST parsers. No code is sent to external APIs."
                    )
                    .font(.system(size: 10.5))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                }
            }
            .padding(12)
            .background(Color.bgSidebarPanel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
            .padding(.horizontal, 24)

            // Language Selection Card
            VStack(alignment: .leading, spacing: 10) {
                Text("App Language")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textPrimary)

                HStack(spacing: 12) {
                    Text(
                        "Select your preferred display language for UI labels and triage summaries."
                    )
                    .font(.system(size: 10.5))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("", selection: $defaultLanguage) {
                        ForEach(
                            [
                                "Auto Detect", "English", "Spanish (Español)", "French (Français)",
                                "Russian (Русский)",
                            ], id: \.self
                        ) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
            .padding(12)
            .background(Color.bgSidebarPanel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
            .padding(.horizontal, 24)

            // Cache Management Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Storage & Cache")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textPrimary)

                HStack(spacing: 12) {
                    Text("Clear the local workspace analyses and persistent triage cache database.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if cacheClearedSuccessfully {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.success)
                            Text("Cleared!")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(.success)
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Button("Clear Cache…") {
                            showClearConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.danger)
                    }
                }
            }
            .padding(12)
            .background(Color.bgSidebarPanel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
            .padding(.horizontal, 24)

            Spacer()
        }
        .confirmationDialog(
            "Clear Database?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Local Data", role: .destructive) {
                Task {
                    await state.coordinator.persistence.deleteAll()
                    await state.load()

                    withAnimation {
                        cacheClearedSuccessfully = true
                    }

                    // Reset the status checkmark after 2.5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            cacheClearedSuccessfully = false
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will delete all analyzed local repository pull requests from the application store. This action cannot be undone."
            )
        }
    }

    // MARK: - Workspaces Tab View

    private var workspacesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace Management")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("Manage paths, aliases, and auto-analysis toggles for active workspaces.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 24)

            if state.repositories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("No workspaces registered")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text(
                        "Use the Folder selector in the top header menu to register a Git repository."
                    )
                    .font(.system(size: 10.5))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Workspace Dropdown Selector
                    HStack(spacing: 12) {
                        Text("Active Workspace:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textSecondary)

                        Picker("", selection: $selectedRepoId) {
                            ForEach(state.repositories) { repo in
                                Text(repo.name).tag(Optional(repo.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }
                    .padding(.horizontal, 24)

                    if let repoId = selectedRepoId,
                        let repo = state.repositories.first(where: { $0.id == repoId })
                    {

                        VStack(alignment: .leading, spacing: 12) {
                            // Folder Path Detail (Read-only + Finder shortcut)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Folder Path")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(.textTertiary)

                                HStack(spacing: 8) {
                                    Text(repo.path)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.bgSubtle)
                                        .cornerRadius(4)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Button {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: repo.path))
                                    } label: {
                                        Image(systemName: "arrow.right.doc.on.clipboard")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.bordered)
                                    .help("Open in Finder")
                                }
                            }

                            // Workspace Alias
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Workspace Alias")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(.textTertiary)

                                HStack(spacing: 8) {
                                    TextField("Workspace name...", text: $repoAlias)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11))

                                    Button("Rename") {
                                        Task {
                                            await state.renameWorkspace(
                                                id: repo.id, newName: repoAlias)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(
                                        repoAlias.trimmingCharacters(in: .whitespacesAndNewlines)
                                            .isEmpty || repoAlias == repo.name)
                                }
                            }

                            // Auto-Analyze Toggle
                            Toggle("Enable Live Auto-Analysis", isOn: $isAutoAnalyzeEnabled)
                                .font(.system(size: 11, weight: .semibold))
                                .toggleStyle(.checkbox)
                                .padding(.top, 4)
                                .onChange(of: isAutoAnalyzeEnabled) { _, newValue in
                                    Task {
                                        await state.setWorkspaceAutoAnalyze(
                                            id: repo.id, enabled: newValue)
                                    }
                                }

                            // Remove Workspace Button
                            HStack {
                                Spacer()
                                Button(role: .destructive) {
                                    showDeleteWorkspaceConfirmation = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                        Text("Remove Workspace")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(.danger)
                            }
                        }
                        .padding(12)
                        .background(Color.bgSidebarPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8).stroke(
                                Color.borderMuted, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 24)
                    }
                }
            }

            Spacer()
        }
        .confirmationDialog(
            "Remove Workspace?",
            isPresented: $showDeleteWorkspaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from Chobi", role: .destructive) {
                if let repoId = selectedRepoId {
                    Task {
                        await state.coordinator.deleteRepository(id: repoId)
                        await state.load()
                        selectedRepoId = state.repositories.first?.id
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will remove the workspace from Chobi. Your local Git repository and files will remain intact."
            )
        }
    }

    // MARK: - Appearance Tab View

    private var appearanceView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Theme Selection")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("Choose your preferred aesthetic style for Chobi.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 24)

            // Side-by-side Theme Selector Cards
            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    themeCard(for: theme)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    @ViewBuilder
    private func themeCard(for theme: AppTheme) -> some View {
        let isSelected = appTheme == theme.rawValue
        let isHovered = hoveredTheme == theme

        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                appTheme = theme.rawValue
            }
        } label: {
            VStack(spacing: 6) {
                // Card Graphic Preview
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(cardBackgroundColor(for: theme))
                        .frame(width: 110, height: 74)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isSelected
                                        ? Color.brandAccent
                                        : (isHovered ? Color.borderDefault : Color.borderMuted),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                        .shadow(
                            color: isSelected ? Color.brandAccent.opacity(0.12) : Color.clear,
                            radius: 4, x: 0, y: 2)

                    // Theme illustration graphic inside
                    themePreviewContent(for: theme)

                    // Selected Checkmark Badge
                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.brandAccent)
                                    .background(Circle().fill(Color.white))
                                    .padding(4)
                            }
                            Spacer()
                        }
                        .frame(width: 110, height: 74)
                    }
                }

                Text(theme.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)
            }
            .contentShape(Rectangle())
            .scaleEffect(isSelected ? 0.98 : (isHovered ? 1.02 : 1.0))
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
            .onHover { hovering in
                hoveredTheme = hovering ? theme : nil
            }
        }
        .buttonStyle(.plain)
    }

    private func cardBackgroundColor(for theme: AppTheme) -> Color {
        switch theme {
        case .light:
            return Color(white: 0.96)
        case .dark:
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        case .system:
            return Color.bgSidebarPanel
        }
    }

    @ViewBuilder
    private func themePreviewContent(for theme: AppTheme) -> some View {
        switch theme {
        case .light:
            VStack(spacing: 3) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)

                // Mini mock window lines
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.12))
                        .frame(width: 36, height: 3)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 50, height: 2)
                }
            }

        case .dark:
            VStack(spacing: 3) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.accentPurple)

                // Mini mock window lines
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 36, height: 3)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 50, height: 2)
                }
            }

        case .system:
            ZStack {
                // Monitor Frame Mock
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.textTertiary)

                // Sunset gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .accentPurple],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 12, height: 12)
            }
        }
    }
}
