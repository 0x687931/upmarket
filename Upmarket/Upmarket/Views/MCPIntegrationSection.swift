import SwiftUI

struct MCPIntegrationSection: View {
    @ObservedObject var integration: MCPIntegrationService

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LM Studio / MCP")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                Text("Advertise Upmarket to local AI tools")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Make Upmarket available to LM Studio", isOn: Binding(
                get: { integration.isEnabled },
                set: { integration.setAdvertisementEnabled($0) }
            ))
            .toggleStyle(.checkbox)

            LabeledContent("Status:") {
                Label(integration.status.displayText, systemImage: integration.status.systemImage)
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                Button("Add to LM Studio…") {
                    integration.addToLMStudio()
                }
                .buttonStyle(AppActionButtonStyle())
                .controlSize(.small)
                .disabled(integration.status == .commandMissing)

                Button("Copy mcp.json Snippet") {
                    integration.copySnippet()
                }
                .buttonStyle(AppActionButtonStyle())
                .controlSize(.small)
                .disabled(!integration.isEnabled || integration.status == .commandMissing)
            }

            Text("Lets local AI apps request document conversion through Upmarket. Disable this to stop advertising Upmarket tools without editing LM Studio settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch integration.status {
        case .ready:
            return .green
        case .commandMissing, .appMoved:
            return .orange
        case .disabled:
            return .secondary
        }
    }
}
