import SwiftUI

struct MCPIntegrationSection: View {
    @ObservedObject var integration: MCPIntegrationService

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("LM Studio / MCP")
                .font(AppTheme.Font.sectionLabel)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
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
                    Button("Add to LM Studio...") {
                        integration.addToLMStudio()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(integration.status == .commandMissing)

                    Button("Copy mcp.json Snippet") {
                        integration.copySnippet()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!integration.isEnabled || integration.status == .commandMissing)
                }

                Text("Lets local AI apps request document conversion through Upmarket. Disable this to stop advertising Upmarket tools without editing LM Studio settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusColor: Color {
        switch integration.status {
        case .ready:
            return AppTheme.Status.complete
        case .commandMissing, .appMoved:
            return AppTheme.Colour.warning
        case .disabled:
            return AppTheme.Status.queued
        }
    }
}
