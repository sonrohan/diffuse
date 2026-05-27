import SwiftUI

enum ProfileStudioSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case fileTypes = "File Types"
    case buckets = "Buckets"
    case symbols = "Symbols"
    case risk = "Risk"
    case tests = "Tests"
    case boundaries = "Boundaries"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .fileTypes: "doc.text.magnifyingglass"
        case .buckets: "tray.full"
        case .symbols: "point.3.connected.trianglepath.dotted"
        case .risk: "target"
        case .tests: "checkmark.seal"
        case .boundaries: "arrow.left.arrow.right"
        }
    }
}

enum ProfileSavePhase {
    case idle
    case saving
    case saved
}

struct AnalysisProfileStudioView: View {
    let repoName: String
    let repoPath: String
    let onSaved: (() -> Void)?

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: ProfileStudioSection = .overview
    @State private var document = EditableAnalysisProfileDocument()
    @State private var errorMessage: String?
    @State private var savePhase: ProfileSavePhase = .idle
    @State private var lastSavedSignature: String?
    @State private var saveLocation: ProfileSaveLocation = .repository
    @State private var lastSavedLocation: ProfileSaveLocation = .repository

    private var profile: AnalysisProfile {
        document.resolvedProfile()
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    sectionContent
                        .padding(18)
                }
                Divider()
                footer
            }
        }
        .frame(width: 760, height: 620)
        .background(Color.bgCanvas)
        .onAppear(perform: loadDocument)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROFILE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 14)
                .padding(.top, 18)

            ForEach(ProfileStudioSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon)
                            .frame(width: 16)
                        Text(section.rawValue)
                        Spacer()
                    }
                    .font(
                        .system(size: 12, weight: selectedSection == section ? .semibold : .medium)
                    )
                    .foregroundColor(selectedSection == section ? .textPrimary : .textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        selectedSection == section ? Color.accentBlue.opacity(0.10) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(width: 160)
        .background(Color.bgSidebar)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.accentBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Analysis Profile Studio")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(repoName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text("flat profile")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.textTertiary)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview: overviewSection
        case .fileTypes: fileTypesSection
        case .buckets: bucketsSection
        case .symbols: symbolsSection
        case .risk: riskSection
        case .tests: testsSection
        case .boundaries: boundariesSection
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Save to:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Picker("Save Location", selection: $saveLocation) {
                    Text("Repository").tag(ProfileSaveLocation.repository)
                    Text("Global Folder").tag(ProfileSaveLocation.global)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .disabled(savePhase == .saving)

                Text(
                    saveLocation == .repository
                        ? "(.chobi.json)"
                        : "(~/.chobi/repos/...)"
                )
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.textTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(.danger)
                        .lineLimit(1)
                } else {
                    Label(saveStatusText, systemImage: saveStatusIcon)
                        .font(.system(size: 10.5))
                        .foregroundColor(saveStatusColor)
                        .lineLimit(1)
                }
            }

            Button("Reload") {
                loadDocument()
            }
            .buttonStyle(.bordered)
            .disabled(savePhase == .saving)

            Button {
                saveDocument()
            } label: {
                saveButtonLabel
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentBlue)
            .disabled(!hasUnsavedChanges || savePhase == .saving)
            .keyboardShortcut("s", modifiers: [.command])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.bgSidebarPanel)
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader(
                title: "Flat Profile",
                subtitle:
                    "Every rule shown here is written directly into this repo's .chobi.json. Nothing is hidden in another profile."
            )

            StudioRuleCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentBlue)
                        .frame(width: 24, height: 24)
                        .background(Color.accentBlue.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Generated from a preset, then edited as one file")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(
                            "Choosing a preset copies its rules into .chobi.json at creation time. After that, the profile is explicit and self-contained."
                        )
                        .font(.system(size: 10.5))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StudioMetric(
                    title: "File type rules", value: "\(profile.fileClassifications.count)",
                    icon: "doc.text")
                StudioMetric(
                    title: "Review buckets", value: "\(profile.buckets.count)", icon: "tray.full")
                StudioMetric(
                    title: "Symbol groups", value: "\(profile.symbolGroups.count)",
                    icon: "point.3.connected.trianglepath.dotted")
                StudioMetric(
                    title: "Boundary rules", value: "\(profile.rules.importBoundaries.count)",
                    icon: "arrow.left.arrow.right")
                StudioMetric(
                    title: "Review signals",
                    value: "\(profile.semanticHighlights.count + profile.fileHighlights.count)",
                    icon: "exclamationmark.shield")
            }

            if let details = state.analysisDetails {
                StudioSectionHeader(
                    title: "Current Diff Preview",
                    subtitle:
                        "This preview uses the open analysis data and the unsaved editor state."
                )
                previewRows(details: details)
            } else {
                StudioEmptyState(
                    icon: "chart.bar.doc.horizontal",
                    title: "No open analysis to preview",
                    detail:
                        "Run an analysis, then reopen this studio to see how these rules classify the current diff."
                )
            }
        }
    }

    private var fileTypesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioSectionHeader(
                title: "File Type Overrides",
                subtitle:
                    "Teach chobi which paths are source, tests, config, docs, generated files, or boilerplate."
            )

            ForEach(fileClassificationRules.indices, id: \.self) { index in
                StudioRuleCard {
                    HStack {
                        Picker("Type", selection: classificationBinding(index)) {
                            ForEach(fileClassificationOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .frame(width: 190)

                        Spacer()

                        Button(role: .destructive) {
                            removeFileClassification(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    PatternListEditor(
                        title: "Path patterns",
                        placeholder: "**/*.generated.ts\n**/fixtures/**",
                        text: patternsBinding(
                            get: { fileClassificationRules[safe: index]?.paths ?? [] },
                            set: { updateFileClassificationPaths(index: index, paths: $0) }
                        )
                    )
                }
            }

            addButton("Add File Type Rule", icon: "plus") {
                addFileClassification()
            }
        }
    }

    private var bucketsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioSectionHeader(
                title: "Review Buckets",
                subtitle: "Group matching paths into the sections reviewers scan first."
            )

            ForEach(bucketRules.indices, id: \.self) { index in
                StudioRuleCard {
                    HStack(spacing: 8) {
                        TextField("id", text: bucketIdBinding(index))
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

                        TextField("Title", text: bucketTitleBinding(index))
                            .textFieldStyle(.roundedBorder)

                        Picker("Type", selection: bucketTypeBinding(index)) {
                            ForEach(ChangeBucketType.allCases, id: \.rawValue) { type in
                                Text(type.displayTitle).tag(type.rawValue)
                            }
                        }
                        .frame(width: 190)

                        Button(role: .destructive) {
                            removeBucket(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    PatternListEditor(
                        title: "Matching paths",
                        placeholder: "**/api/**\n**/routes/**",
                        text: patternsBinding(
                            get: { bucketRules[safe: index]?.paths ?? [] },
                            set: { updateBucketPaths(index: index, paths: $0) }
                        )
                    )

                    Divider()

                    Text("Symbol matches")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.textTertiary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        PatternListEditor(
                            title: "Semantic areas",
                            placeholder: "security_authentication\npayment",
                            text: patternsBinding(
                                get: { bucketRules[safe: index]?.symbolSemanticAreas ?? [] },
                                set: { updateBucketSymbolSemanticAreas(index: index, values: $0) }
                            )
                        )
                        PatternListEditor(
                            title: "Semantic types",
                            placeholder: "function_definition\nclass_declaration",
                            text: patternsBinding(
                                get: { bucketRules[safe: index]?.symbolSemanticTypes ?? [] },
                                set: { updateBucketSymbolSemanticTypes(index: index, values: $0) }
                            )
                        )
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        PatternListEditor(
                            title: "Symbol names",
                            placeholder: "*Auth*\ndelete*",
                            text: patternsBinding(
                                get: { bucketRules[safe: index]?.symbolNames ?? [] },
                                set: { updateBucketSymbolNames(index: index, values: $0) }
                            )
                        )
                        PatternListEditor(
                            title: "Callees",
                            placeholder: "*delete*\nfetch*",
                            text: patternsBinding(
                                get: { bucketRules[safe: index]?.symbolCallees ?? [] },
                                set: { updateBucketSymbolCallees(index: index, values: $0) }
                            )
                        )
                    }

                    KeyValueListEditor(
                        title: "Metadata equals",
                        placeholder: "contract_signature_changed=true\nnetwork_call_added=true",
                        text: keyValueBinding(
                            get: { bucketRules[safe: index]?.symbolMetadataEquals ?? [:] },
                            set: { updateBucketSymbolMetadataEquals(index: index, values: $0) }
                        )
                    )
                }
            }

            addButton("Add Bucket", icon: "tray.and.arrow.down") {
                addBucket()
            }
        }
    }

    private var symbolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioSectionHeader(
                title: "Symbols",
                subtitle:
                    "Use AST symbols to group, flag, and bucket behavior changes without relying only on file paths."
            )

            if let details = state.analysisDetails, !details.symbols.isEmpty {
                StudioSectionHeader(
                    title: "Current Symbol Preview",
                    subtitle: "Use these examples to teach chobi from real changed code."
                )
                StudioRuleCard {
                    ForEach(Array(symbolPreviewRows(details: details).prefix(12))) { row in
                        SymbolPreviewTeachingRow(
                            row: row,
                            onGroup: { teachSymbolGroup(from: row) },
                            onSignal: { teachSymbolSignal(from: row) },
                            onBucket: { teachSymbolBucket(from: row) }
                        )
                    }
                }
            } else {
                StudioEmptyState(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "No changed symbols to preview",
                    detail:
                        "Run an analysis with supported source files to teach symbol rules from real examples."
                )
            }

            StudioSectionHeader(
                title: "Symbol Groups",
                subtitle: "Controls how changed symbols are organized in the review map."
            )

            ForEach(symbolGroupRules.indices, id: \.self) { index in
                StudioRuleCard {
                    HStack(spacing: 8) {
                        TextField("id", text: symbolGroupIdBinding(index))
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        TextField("Label", text: symbolGroupLabelBinding(index))
                            .textFieldStyle(.roundedBorder)
                        TextField("Icon", text: symbolGroupIconBinding(index))
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Toggle("Fallback", isOn: symbolGroupFallbackBinding(index))
                            .toggleStyle(.checkbox)
                        Button(role: .destructive) {
                            removeSymbolGroup(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    PatternListEditor(
                        title: "Semantic areas",
                        placeholder: "security_authentication\npayment",
                        text: patternsBinding(
                            get: { symbolGroupRules[safe: index]?.semanticAreas ?? [] },
                            set: { updateSymbolGroupSemanticAreas(index: index, values: $0) }
                        )
                    )

                    KeyValueListEditor(
                        title: "Metadata equals",
                        placeholder: "is_test=true\ncontract_is_new_public=true",
                        text: keyValueBinding(
                            get: { symbolGroupRules[safe: index]?.metadataEquals ?? [:] },
                            set: { updateSymbolGroupMetadataEquals(index: index, values: $0) }
                        )
                    )
                }
            }

            addButton("Add Symbol Group", icon: "plus") {
                addSymbolGroup()
            }

            StudioSectionHeader(
                title: "Symbol Signals",
                subtitle: "Create review findings when matching symbols change."
            )

            ForEach(symbolSignalRules.indices, id: \.self) { index in
                StudioRuleCard {
                    HStack(spacing: 8) {
                        TextField("id", text: symbolSignalIdBinding(index))
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                        TextField("Semantic area", text: symbolSignalSemanticAreaBinding(index))
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                        Picker("Severity", selection: symbolSignalSeverityBinding(index)) {
                            ForEach(Severity.allCases, id: \.rawValue) { severity in
                                Text(severity.rawValue).tag(severity.rawValue)
                            }
                        }
                        .frame(width: 110)
                        Picker("Category", selection: symbolSignalCategoryBinding(index)) {
                            ForEach(findingCategoryOptions, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .frame(width: 140)
                        Button(role: .destructive) {
                            removeSymbolSignal(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    TextField("Message", text: symbolSignalMessageBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }

            addButton("Add Symbol Signal", icon: "exclamationmark.shield") {
                addSymbolSignal()
            }
        }
    }

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioSectionHeader(
                title: "Risk Inputs",
                subtitle: "Mark paths that should raise review attention when they change."
            )

            StudioRuleCard {
                PatternListEditor(
                    title: "API surface paths",
                    placeholder: "**/api/**\n**/routes/**",
                    text: patternsBinding(
                        get: { document.riskScoring?.apiPaths ?? [] },
                        set: { updateApiPaths($0) }
                    )
                )
            }

            StudioRuleCard {
                PatternListEditor(
                    title: "Sensitive paths",
                    placeholder: "**/*auth*\n**/*payment*\n**/*security*",
                    text: patternsBinding(
                        get: { document.riskScoring?.sensitivePaths ?? [] },
                        set: { updateSensitivePaths($0) }
                    )
                )
            }
        }
    }

    private var testsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioSectionHeader(
                title: "Missing Test Signal",
                subtitle:
                    "Control when chobi warns about production changes without nearby test changes."
            )

            StudioRuleCard {
                Toggle(
                    "Warn when source changes do not include matching tests",
                    isOn: missingTestsEnabledBinding
                )
                .toggleStyle(.checkbox)

                Stepper(value: missingTestsMinimumBinding, in: 1...250) {
                    Text(
                        "Minimum added source lines: \(document.rules?.missingTests?.minimumAdditions ?? defaultMissingTestsRule.minimumAdditions)"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textPrimary)
                }

                PatternListEditor(
                    title: "Source classifications",
                    placeholder: "source",
                    text: patternsBinding(
                        get: {
                            document.rules?.missingTests?.sourceClassifications
                                ?? defaultMissingTestsRule.sourceClassifications
                        },
                        set: { updateMissingTestsSourceClasses($0) }
                    )
                )

                PatternListEditor(
                    title: "Test classifications",
                    placeholder: "test",
                    text: patternsBinding(
                        get: {
                            document.rules?.missingTests?.testClassifications
                                ?? defaultMissingTestsRule.testClassifications
                        },
                        set: { updateMissingTestsTestClasses($0) }
                    )
                )
            }
        }
    }

    private var boundariesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioSectionHeader(
                title: "Architecture Boundaries",
                subtitle:
                    "Warn when symbols in one path layer import forbidden lower-level modules."
            )

            ForEach(importBoundaryRules.indices, id: \.self) { index in
                StudioRuleCard {
                    HStack(spacing: 8) {
                        TextField("id", text: boundaryIdBinding(index))
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        Picker("Severity", selection: boundarySeverityBinding(index)) {
                            ForEach(Severity.allCases, id: \.rawValue) { severity in
                                Text(severity.rawValue).tag(severity.rawValue)
                            }
                        }
                        .frame(width: 110)

                        Picker("Category", selection: boundaryCategoryBinding(index)) {
                            ForEach(findingCategoryOptions, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .frame(width: 140)

                        Button(role: .destructive) {
                            removeBoundary(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    PatternListEditor(
                        title: "Source paths",
                        placeholder: "**/components/**\n**/app/**",
                        text: patternsBinding(
                            get: { importBoundaryRules[safe: index]?.sourcePaths ?? [] },
                            set: { updateBoundarySourcePaths(index: index, paths: $0) }
                        )
                    )

                    PatternListEditor(
                        title: "Forbidden imports",
                        placeholder: "*database*\n*repository*\n*prisma*",
                        text: patternsBinding(
                            get: { importBoundaryRules[safe: index]?.forbiddenImports ?? [] },
                            set: { updateBoundaryForbiddenImports(index: index, paths: $0) }
                        )
                    )

                    TextField("Message", text: boundaryMessageBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }

            addButton("Add Boundary Rule", icon: "plus") {
                addBoundary()
            }
        }
    }
}

extension AnalysisProfileStudioView {
    fileprivate var profileFileName: String {
        switch saveLocation {
        case .repository:
            return ".chobi.json"
        case .global:
            return "~/.chobi/repos/.../config.json"
        }
    }

    fileprivate var currentSignature: String? {
        profileSignature(document)
    }

    fileprivate var hasUnsavedChanges: Bool {
        currentSignature != lastSavedSignature || saveLocation != lastSavedLocation
    }

    fileprivate var saveStatusText: String {
        switch savePhase {
        case .saving:
            return "Saving changes..."
        case .saved:
            return "Saved just now"
        case .idle:
            return hasUnsavedChanges ? "Unsaved changes" : "All changes saved"
        }
    }

    fileprivate var saveStatusIcon: String {
        switch savePhase {
        case .saving:
            return "arrow.triangle.2.circlepath"
        case .saved:
            return "checkmark.circle.fill"
        case .idle:
            return hasUnsavedChanges ? "circle.fill" : "checkmark.circle"
        }
    }

    fileprivate var saveStatusColor: Color {
        switch savePhase {
        case .saving:
            return .accentBlue
        case .saved:
            return .success
        case .idle:
            return hasUnsavedChanges ? .warning : .textTertiary
        }
    }

    @ViewBuilder
    fileprivate var saveButtonLabel: some View {
        switch savePhase {
        case .saving:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Saving")
            }
        case .saved:
            Label("Saved", systemImage: "checkmark")
        case .idle:
            Label(
                hasUnsavedChanges ? "Save Changes" : "Saved",
                systemImage: hasUnsavedChanges ? "square.and.arrow.down" : "checkmark")
        }
    }

    fileprivate var fileClassificationOptions: [String] {
        ["source", "test", "config", "documentation", "generated", "boilerplate"]
    }

    fileprivate var findingCategoryOptions: [String] {
        ["architecture", "test", "security", "performance", "clean-code"]
    }

    fileprivate var fileClassificationRules: [FileClassificationRule] {
        document.fileClassifications ?? []
    }

    fileprivate var bucketRules: [BucketRule] {
        document.buckets ?? []
    }

    fileprivate var symbolGroupRules: [SymbolGroupRule] {
        document.symbolGroups ?? []
    }

    fileprivate var symbolSignalRules: [SemanticAreaFindingRule] {
        document.rules?.semanticAreaFindings ?? []
    }

    fileprivate var importBoundaryRules: [ImportBoundaryRule] {
        document.rules?.importBoundaries ?? []
    }

    fileprivate var defaultMissingTestsRule: MissingTestsRule {
        profile.rules.missingTests
            ?? MissingTestsRule(
                enabled: true,
                minimumAdditions: 10,
                sourceClassifications: ["source"],
                testClassifications: ["test"],
                message:
                    "Significant logic change ({additions} additions) without any matching test file additions or updates in this PR."
            )
    }

    fileprivate var missingTestsEnabledBinding: Binding<Bool> {
        Binding {
            document.rules?.missingTests?.enabled ?? defaultMissingTestsRule.enabled
        } set: { value in
            ensureMissingTestsRule()
            document.rules?.missingTests?.enabled = value
        }
    }

    fileprivate var missingTestsMinimumBinding: Binding<Int> {
        Binding {
            document.rules?.missingTests?.minimumAdditions
                ?? defaultMissingTestsRule.minimumAdditions
        } set: { value in
            ensureMissingTestsRule()
            document.rules?.missingTests?.minimumAdditions = value
        }
    }

    fileprivate func loadDocument() {
        do {
            let result = try AnalysisProfileStore.loadEditableDocument(repoPath: repoPath)
            document = result.doc
            saveLocation = result.location
            lastSavedLocation = result.location
            errorMessage = nil
            savePhase = .idle
            lastSavedSignature = profileSignature(document)
        } catch {
            errorMessage = "Could not load profile: \(error.localizedDescription)"
        }
    }

    fileprivate func saveDocument() {
        savePhase = .saving
        errorMessage = nil
        do {
            try AnalysisProfileStore.writeEditableDocument(
                document, repoPath: repoPath, location: saveLocation)
            lastSavedSignature = currentSignature
            lastSavedLocation = saveLocation
            errorMessage = nil
            savePhase = .saved
            onSaved?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if !hasUnsavedChanges {
                    savePhase = .idle
                }
            }
        } catch {
            savePhase = .idle
            errorMessage = "Could not save profile: \(error.localizedDescription)"
        }
    }

    fileprivate func profileSignature(_ document: EditableAnalysisProfileDocument) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(document.normalized()) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    fileprivate func addButton(_ title: String, icon: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.bordered)
    }

    fileprivate func previewRows(details: AnalysisDetails) -> some View {
        let classified = Dictionary(grouping: details.files) { file in
            profile.classifyFile(file.path).rawValue
        }
        let bucketCounts = previewBucketCounts(details: details)

        return VStack(alignment: .leading, spacing: 10) {
            StudioRuleCard {
                ForEach(classified.keys.sorted(), id: \.self) { key in
                    ProfileSummaryRow(title: key, detail: "\(classified[key]?.count ?? 0) files")
                }
            }

            StudioRuleCard {
                ForEach(bucketCounts, id: \.title) { item in
                    ProfileSummaryRow(title: item.title, detail: "\(item.count) files")
                }
            }
        }
    }

    fileprivate func previewBucketCounts(details: AnalysisDetails) -> [(title: String, count: Int)]
    {
        var counts: [String: (title: String, count: Int)] = [:]
        let findingsByPath = Dictionary(
            grouping: details.findings,
            by: { finding in
                details.files.first { $0.id == finding.changedFileId }?.path ?? ""
            })

        for file in details.files {
            var previewFile = file
            previewFile.classification = profile.classifyFile(file.path)
            let fileFindings = findingsByPath[file.path] ?? []
            let fileSymbols = details.symbols.filter { $0.changedFileId == file.id }
            let rule = profile.bucketRule(
                for: previewFile, findings: fileFindings, symbols: fileSymbols)
            let key = rule?.id ?? ChangeBucketType.behavior.rawValue
            let title = rule?.title ?? ChangeBucketType.behavior.displayTitle
            counts[key] = (title, (counts[key]?.count ?? 0) + 1)
        }

        return counts.values.sorted { $0.title < $1.title }
    }

    fileprivate func patternsBinding(
        get: @escaping () -> [String], set: @escaping ([String]) -> Void
    ) -> Binding<String> {
        Binding {
            get().joined(separator: "\n")
        } set: { text in
            let values =
                text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            set(values)
        }
    }

    fileprivate func keyValueBinding(
        get: @escaping () -> [String: String], set: @escaping ([String: String]) -> Void
    ) -> Binding<String> {
        Binding {
            get()
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: "\n")
        } set: { text in
            let values =
                text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String: String]()) { result, line in
                    let parts = line.split(separator: "=", maxSplits: 1).map {
                        String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    guard parts.count == 2, !parts[0].isEmpty else { return }
                    result[parts[0]] = parts[1]
                }
            set(values)
        }
    }

    fileprivate func symbolPreviewRows(details: AnalysisDetails) -> [SymbolPreviewRow] {
        let filesById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0.path) })
        let grouped = Dictionary(grouping: details.symbols) { symbol in
            symbol.metadata["semantic_area"] ?? symbol.semanticType
        }

        return grouped.map { key, symbols in
            let sample = symbols.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }.first
            return SymbolPreviewRow(
                id: key.isEmpty ? "general" : key,
                label: key.isEmpty ? "general" : key,
                semanticArea: key,
                semanticType: sample?.semanticType ?? "",
                sampleName: sample?.name ?? "",
                samplePath: sample.flatMap { filesById[$0.changedFileId] } ?? "",
                count: symbols.count
            )
        }
        .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
    }
}

extension AnalysisProfileStudioView {
    fileprivate func ensureRules() {
        if document.rules == nil {
            document.rules = EditableRuleProfile()
        }
    }

    fileprivate func ensureRiskScoring() {
        if document.riskScoring == nil {
            document.riskScoring = RiskScoringProfile()
        }
    }

    fileprivate func ensureMissingTestsRule() {
        ensureRules()
        if document.rules?.missingTests == nil {
            document.rules?.missingTests = defaultMissingTestsRule
        }
    }

    fileprivate func addFileClassification() {
        var rules = document.fileClassifications ?? []
        rules.append(
            FileClassificationRule(classification: "generated", paths: ["**/generated/**"]))
        document.fileClassifications = rules
    }

    fileprivate func removeFileClassification(at index: Int) {
        guard document.fileClassifications?.indices.contains(index) == true else { return }
        document.fileClassifications?.remove(at: index)
    }

    fileprivate func classificationBinding(_ index: Int) -> Binding<String> {
        Binding {
            fileClassificationRules[safe: index]?.classification ?? "source"
        } set: { value in
            guard document.fileClassifications?.indices.contains(index) == true else { return }
            document.fileClassifications?[index].classification = value
        }
    }

    fileprivate func updateFileClassificationPaths(index: Int, paths: [String]) {
        guard document.fileClassifications?.indices.contains(index) == true else { return }
        document.fileClassifications?[index].paths = paths
    }

    fileprivate func addBucket() {
        var rules = document.buckets ?? []
        rules.append(
            BucketRule(
                id: "custom-\(rules.count + 1)",
                type: ChangeBucketType.behavior.rawValue,
                title: "Custom review bucket",
                paths: ["**/feature/**"],
                classifications: nil,
                findingCategories: nil,
                symbolSemanticAreas: nil,
                symbolSemanticTypes: nil,
                symbolNames: nil,
                symbolMetadataEquals: nil,
                symbolMetadataMatches: nil,
                symbolCallees: nil
            ))
        document.buckets = rules
    }

    fileprivate func removeBucket(at index: Int) {
        guard document.buckets?.indices.contains(index) == true else { return }
        document.buckets?.remove(at: index)
    }

    fileprivate func bucketIdBinding(_ index: Int) -> Binding<String> {
        Binding {
            bucketRules[safe: index]?.id ?? ""
        } set: { value in
            guard document.buckets?.indices.contains(index) == true else { return }
            document.buckets?[index].id = value
        }
    }

    fileprivate func bucketTitleBinding(_ index: Int) -> Binding<String> {
        Binding {
            bucketRules[safe: index]?.title ?? ""
        } set: { value in
            guard document.buckets?.indices.contains(index) == true else { return }
            document.buckets?[index].title = value
        }
    }

    fileprivate func bucketTypeBinding(_ index: Int) -> Binding<String> {
        Binding {
            bucketRules[safe: index]?.type ?? ChangeBucketType.behavior.rawValue
        } set: { value in
            guard document.buckets?.indices.contains(index) == true else { return }
            document.buckets?[index].type = value
        }
    }

    fileprivate func updateBucketPaths(index: Int, paths: [String]) {
        guard document.buckets?.indices.contains(index) == true else { return }
        document.buckets?[index].paths = paths
    }

    fileprivate func updateBucketSymbolSemanticAreas(index: Int, values: [String]) {
        guard document.buckets?.indices.contains(index) == true else { return }
        document.buckets?[index].symbolSemanticAreas = values.isEmpty ? nil : values
    }

    fileprivate func updateBucketSymbolSemanticTypes(index: Int, values: [String]) {
        guard document.buckets?.indices.contains(index) == true else { return }
        document.buckets?[index].symbolSemanticTypes = values.isEmpty ? nil : values
    }

    fileprivate func updateBucketSymbolNames(index: Int, values: [String]) {
        guard document.buckets?.indices.contains(index) == true else { return }
        document.buckets?[index].symbolNames = values.isEmpty ? nil : values
    }

    fileprivate func updateBucketSymbolCallees(index: Int, values: [String]) {
        guard document.buckets?.indices.contains(index) == true else { return }
        document.buckets?[index].symbolCallees = values.isEmpty ? nil : values
    }

    fileprivate func updateBucketSymbolMetadataEquals(index: Int, values: [String: String]) {
        guard document.buckets?.indices.contains(index) == true else { return }
        document.buckets?[index].symbolMetadataEquals = values.isEmpty ? nil : values
    }

    fileprivate func updateApiPaths(_ paths: [String]) {
        ensureRiskScoring()
        document.riskScoring?.apiPaths = paths
    }

    fileprivate func updateSensitivePaths(_ paths: [String]) {
        ensureRiskScoring()
        document.riskScoring?.sensitivePaths = paths
    }

    fileprivate func updateMissingTestsSourceClasses(_ values: [String]) {
        ensureMissingTestsRule()
        document.rules?.missingTests?.sourceClassifications = values
    }

    fileprivate func updateMissingTestsTestClasses(_ values: [String]) {
        ensureMissingTestsRule()
        document.rules?.missingTests?.testClassifications = values
    }

    fileprivate func addSymbolGroup() {
        var groups = document.symbolGroups ?? []
        groups.append(
            SymbolGroupRule(
                id: "custom-symbol-\(groups.count + 1)",
                label: "Custom Symbols",
                icon: "point.3.connected.trianglepath.dotted",
                semanticAreas: ["custom_area"],
                metadataEquals: nil,
                fallback: nil
            ))
        document.symbolGroups = groups
    }

    fileprivate func removeSymbolGroup(at index: Int) {
        guard document.symbolGroups?.indices.contains(index) == true else { return }
        document.symbolGroups?.remove(at: index)
    }

    fileprivate func symbolGroupIdBinding(_ index: Int) -> Binding<String> {
        Binding {
            symbolGroupRules[safe: index]?.id ?? ""
        } set: { value in
            guard document.symbolGroups?.indices.contains(index) == true else { return }
            document.symbolGroups?[index].id = value
        }
    }

    fileprivate func symbolGroupLabelBinding(_ index: Int) -> Binding<String> {
        Binding {
            symbolGroupRules[safe: index]?.label ?? ""
        } set: { value in
            guard document.symbolGroups?.indices.contains(index) == true else { return }
            document.symbolGroups?[index].label = value
        }
    }

    fileprivate func symbolGroupIconBinding(_ index: Int) -> Binding<String> {
        Binding {
            symbolGroupRules[safe: index]?.icon ?? "point.3.connected.trianglepath.dotted"
        } set: { value in
            guard document.symbolGroups?.indices.contains(index) == true else { return }
            document.symbolGroups?[index].icon = value
        }
    }

    fileprivate func symbolGroupFallbackBinding(_ index: Int) -> Binding<Bool> {
        Binding {
            symbolGroupRules[safe: index]?.fallback == true
        } set: { value in
            guard document.symbolGroups?.indices.contains(index) == true else { return }
            document.symbolGroups?[index].fallback = value ? true : nil
        }
    }

    fileprivate func updateSymbolGroupSemanticAreas(index: Int, values: [String]) {
        guard document.symbolGroups?.indices.contains(index) == true else { return }
        document.symbolGroups?[index].semanticAreas = values.isEmpty ? nil : values
    }

    fileprivate func updateSymbolGroupMetadataEquals(index: Int, values: [String: String]) {
        guard document.symbolGroups?.indices.contains(index) == true else { return }
        document.symbolGroups?[index].metadataEquals = values.isEmpty ? nil : values
    }

    fileprivate func addSymbolSignal() {
        ensureRules()
        var rules = document.rules?.semanticAreaFindings ?? []
        rules.append(
            SemanticAreaFindingRule(
                id: "symbols/custom-\(rules.count + 1)",
                semanticArea: "custom_area",
                paths: nil,
                symbolNames: nil,
                metadataEquals: nil,
                severity: Severity.medium.rawValue,
                category: "architecture",
                message: "Symbol '{symbol}' changed in a configured semantic area."
            ))
        document.rules?.semanticAreaFindings = rules
    }

    fileprivate func removeSymbolSignal(at index: Int) {
        guard document.rules?.semanticAreaFindings?.indices.contains(index) == true else { return }
        document.rules?.semanticAreaFindings?.remove(at: index)
    }

    fileprivate func symbolSignalIdBinding(_ index: Int) -> Binding<String> {
        Binding {
            symbolSignalRules[safe: index]?.id ?? ""
        } set: { value in
            guard document.rules?.semanticAreaFindings?.indices.contains(index) == true else {
                return
            }
            document.rules?.semanticAreaFindings?[index].id = value
        }
    }

    fileprivate func symbolSignalSemanticAreaBinding(_ index: Int) -> Binding<String> {
        Binding {
            symbolSignalRules[safe: index]?.semanticArea ?? ""
        } set: { value in
            guard document.rules?.semanticAreaFindings?.indices.contains(index) == true else {
                return
            }
            document.rules?.semanticAreaFindings?[index].semanticArea =
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        }
    }

    fileprivate func symbolSignalSeverityBinding(_ index: Int) -> Binding<String> {
        Binding {
            symbolSignalRules[safe: index]?.severity ?? Severity.medium.rawValue
        } set: { value in
            guard document.rules?.semanticAreaFindings?.indices.contains(index) == true else {
                return
            }
            document.rules?.semanticAreaFindings?[index].severity = value
        }
    }

    fileprivate func symbolSignalCategoryBinding(_ index: Int) -> Binding<String> {
        Binding {
            symbolSignalRules[safe: index]?.category ?? "architecture"
        } set: { value in
            guard document.rules?.semanticAreaFindings?.indices.contains(index) == true else {
                return
            }
            document.rules?.semanticAreaFindings?[index].category = value
        }
    }

    fileprivate func symbolSignalMessageBinding(_ index: Int) -> Binding<String> {
        Binding {
            symbolSignalRules[safe: index]?.message ?? ""
        } set: { value in
            guard document.rules?.semanticAreaFindings?.indices.contains(index) == true else {
                return
            }
            document.rules?.semanticAreaFindings?[index].message = value
        }
    }

    fileprivate func teachSymbolGroup(from row: SymbolPreviewRow) {
        guard !row.semanticArea.isEmpty else { return }
        var groups = document.symbolGroups ?? []
        guard !groups.contains(where: { $0.semanticAreas?.contains(row.semanticArea) == true })
        else {
            errorMessage = nil
            return
        }
        groups.append(
            SymbolGroupRule(
                id: row.semanticArea,
                label: row.semanticArea.replacingOccurrences(of: "_", with: " ").capitalized,
                icon: "point.3.connected.trianglepath.dotted",
                semanticAreas: [row.semanticArea],
                metadataEquals: nil,
                fallback: nil
            ))
        document.symbolGroups = groups
        errorMessage = nil
    }

    fileprivate func teachSymbolSignal(from row: SymbolPreviewRow) {
        guard !row.semanticArea.isEmpty else { return }
        ensureRules()
        var rules = document.rules?.semanticAreaFindings ?? []
        guard !rules.contains(where: { $0.semanticArea == row.semanticArea }) else {
            errorMessage = nil
            return
        }
        rules.append(
            SemanticAreaFindingRule(
                id: "symbols/\(row.semanticArea)",
                semanticArea: row.semanticArea,
                paths: nil,
                symbolNames: nil,
                metadataEquals: nil,
                severity: Severity.medium.rawValue,
                category: "architecture",
                message:
                    "Symbol '{symbol}' changed in \(row.semanticArea.replacingOccurrences(of: "_", with: " "))."
            ))
        document.rules?.semanticAreaFindings = rules
        errorMessage = nil
    }

    fileprivate func teachSymbolBucket(from row: SymbolPreviewRow) {
        guard !row.semanticArea.isEmpty else { return }
        var rules = document.buckets ?? []
        guard !rules.contains(where: { $0.symbolSemanticAreas?.contains(row.semanticArea) == true })
        else {
            errorMessage = nil
            return
        }
        rules.append(
            BucketRule(
                id: "symbols-\(row.semanticArea)",
                type: ChangeBucketType.behavior.rawValue,
                title: row.semanticArea.replacingOccurrences(of: "_", with: " ").capitalized,
                paths: nil,
                classifications: nil,
                findingCategories: nil,
                symbolSemanticAreas: [row.semanticArea],
                symbolSemanticTypes: nil,
                symbolNames: nil,
                symbolMetadataEquals: nil,
                symbolMetadataMatches: nil,
                symbolCallees: nil
            ))
        document.buckets = rules
        errorMessage = nil
    }

    fileprivate func addBoundary() {
        ensureRules()
        var rules = document.rules?.importBoundaries ?? []
        rules.append(
            ImportBoundaryRule(
                id: "architecture/custom-\(rules.count + 1)",
                sourcePaths: ["**/components/**"],
                forbiddenImports: ["*database*"],
                severity: Severity.medium.rawValue,
                category: "architecture",
                message: "Symbol '{symbol}' imports a forbidden lower-level dependency."
            ))
        document.rules?.importBoundaries = rules
    }

    fileprivate func removeBoundary(at index: Int) {
        guard document.rules?.importBoundaries?.indices.contains(index) == true else { return }
        document.rules?.importBoundaries?.remove(at: index)
    }

    fileprivate func boundaryIdBinding(_ index: Int) -> Binding<String> {
        Binding {
            importBoundaryRules[safe: index]?.id ?? ""
        } set: { value in
            guard document.rules?.importBoundaries?.indices.contains(index) == true else { return }
            document.rules?.importBoundaries?[index].id = value
        }
    }

    fileprivate func boundarySeverityBinding(_ index: Int) -> Binding<String> {
        Binding {
            importBoundaryRules[safe: index]?.severity ?? Severity.medium.rawValue
        } set: { value in
            guard document.rules?.importBoundaries?.indices.contains(index) == true else { return }
            document.rules?.importBoundaries?[index].severity = value
        }
    }

    fileprivate func boundaryCategoryBinding(_ index: Int) -> Binding<String> {
        Binding {
            importBoundaryRules[safe: index]?.category ?? "architecture"
        } set: { value in
            guard document.rules?.importBoundaries?.indices.contains(index) == true else { return }
            document.rules?.importBoundaries?[index].category = value
        }
    }

    fileprivate func boundaryMessageBinding(_ index: Int) -> Binding<String> {
        Binding {
            importBoundaryRules[safe: index]?.message ?? ""
        } set: { value in
            guard document.rules?.importBoundaries?.indices.contains(index) == true else { return }
            document.rules?.importBoundaries?[index].message = value
        }
    }

    fileprivate func updateBoundarySourcePaths(index: Int, paths: [String]) {
        guard document.rules?.importBoundaries?.indices.contains(index) == true else { return }
        document.rules?.importBoundaries?[index].sourcePaths = paths
    }

    fileprivate func updateBoundaryForbiddenImports(index: Int, paths: [String]) {
        guard document.rules?.importBoundaries?.indices.contains(index) == true else { return }
        document.rules?.importBoundaries?[index].forbiddenImports = paths
    }
}

struct StudioSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SymbolPreviewRow: Identifiable {
    let id: String
    let label: String
    let semanticArea: String
    let semanticType: String
    let sampleName: String
    let samplePath: String
    let count: Int
}

struct SymbolPreviewTeachingRow: View {
    let row: SymbolPreviewRow
    let onGroup: () -> Void
    let onSignal: () -> Void
    let onBucket: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentBlue)
                .frame(width: 22, height: 22)
                .background(Color.accentBlue.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.label)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text("\(row.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentBlue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentBlue.opacity(0.10))
                        .clipShape(Capsule())
                }
                if !row.sampleName.isEmpty {
                    Text("\(row.sampleName) · \(row.semanticType)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !row.samplePath.isEmpty {
                    Text(row.samplePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Menu {
                Button("Group symbols like this", action: onGroup)
                Button("Warn when this changes", action: onSignal)
                Button("Bucket files with this symbol", action: onBucket)
            } label: {
                Label("Teach", systemImage: "wand.and.stars")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 5)
    }
}

struct StudioRuleCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .background(Color.bgSidebarPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
    }
}

struct PatternListEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.textTertiary)
            TextEditor(text: $text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 58)
                .padding(6)
                .background(Color.bgSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.borderMuted, lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.textTertiary.opacity(0.65))
                            .padding(11)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

struct KeyValueListEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        PatternListEditor(title: title, placeholder: placeholder, text: $text)
    }
}

struct StudioMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentBlue)
                .frame(width: 24, height: 24)
                .background(Color.accentBlue.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.bgSidebarPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
    }
}

struct StudioEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.textTertiary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.bgSidebarPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
    }
}

extension Array {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
