import SwiftUI

struct MCPSettingsView: View {
    @Bindable var viewModel: MCPSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent Access")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("Expose local read-only review context to MCP-capable agents.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 24)

            statusCard
            configCard
            permissionsCard
            activityCard

            Spacer()
        }
        .task {
            await viewModel.refresh()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    viewModel.isRunning ? "Running" : "Off",
                    systemImage: viewModel.isRunning ? "network" : "power"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(viewModel.isRunning ? .successColor : .textSecondary)

                Spacer()

                Button(viewModel.isRunning ? "Stop" : "Start") {
                    viewModel.isRunning ? viewModel.stop() : viewModel.start()
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRunning ? .dangerColor : .accentBlue)
            }

            Text(viewModel.endpointText)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundColor(.dangerColor)
            }
        }
        .settingsCard()
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connect an Agent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    viewModel.rotateToken()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Rotate token")

                Button {
                    viewModel.copyConnectionDetails()
                } label: {
                    Label("Copy Details", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 6) {
                connectionRow("Protocol", value: viewModel.protocolText)
                connectionRow("URL", value: viewModel.endpointText)
                connectionRow("Auth", value: "Bearer token")
                connectionRow("Header", value: viewModel.authHeaderText)
                connectionRow(
                    "Token",
                    value: viewModel.tokenText.isEmpty
                        ? "Generated when server starts" : viewModel.tokenText)
            }

            Text(
                "Use these values in any MCP client that supports Streamable HTTP. The server only accepts loopback requests with the Authorization header."
            )
            .font(.system(size: 10.5))
            .foregroundColor(.textSecondary)

            if let copied = viewModel.copiedState {
                Text(copied)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.successColor)
            }
        }
        .settingsCard()
    }

    private func connectionRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.textTertiary)
                .frame(width: 52, alignment: .leading)

            Text(value)
                .font(.system(size: 10.5, design: label == "Header" ? .monospaced : .default))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textPrimary)

            Toggle("Allow bounded file range reads", isOn: $viewModel.allowFileRangeReads)
                .font(.system(size: 11))
                .toggleStyle(.checkbox)

            HStack {
                Text(viewModel.readOnlyPermissionsText)
                    .font(.system(size: 10.5))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("\(viewModel.lineRangeLimit) lines")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.textTertiary)
            }

            Toggle("Mutation tools", isOn: .constant(false))
                .font(.system(size: 11))
                .toggleStyle(.checkbox)
                .disabled(true)
        }
        .settingsCard()
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Events")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textPrimary)

            if viewModel.recentEvents.isEmpty {
                Text("No local MCP activity yet.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.textSecondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.recentEvents.prefix(5)) { event in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(event.status == "ok" ? Color.successColor : Color.dangerColor)
                                .frame(width: 6, height: 6)
                            Text(event.name)
                                .font(.system(size: 10.5))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(event.errorCode ?? event.status)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
            }
        }
        .settingsCard()
    }
}

private struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.bgSidebarPanel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderMuted, lineWidth: 0.5))
            .padding(.horizontal, 24)
    }
}

extension View {
    fileprivate func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }
}
