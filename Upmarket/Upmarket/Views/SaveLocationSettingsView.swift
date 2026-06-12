import SwiftUI

struct SaveLocationSettingsView: View {
    @Binding var destination: SavePreference.Destination
    @Binding var chosenFolderURL: URL?

    let title: String?
    let description: String?
    let onChooseFolder: () -> Void
    let showsCardChrome: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            if let description {
                Text(description)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Save files", selection: destinationBinding) {
                Text("Same folder as original").tag(SavePreference.Destination.sameFolder)
                Text("Ask each time").tag(SavePreference.Destination.askEachTime)
                Text("Choose folder…").tag(SavePreference.Destination.chosenFolder)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if destination == .chosenFolder {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(chosenFolderURL?.lastPathComponent ?? "No folder chosen")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(chosenFolderURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…", action: onChooseFolder)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        // Card chrome uses Radius.md (matches AppSectionCard / modal card convention —
        // prior implementation used Radius.lg which deviated from the --radius-md card standard)
        .padding(.horizontal, showsCardChrome ? AppTheme.Spacing.lg : 0)
        .padding(.vertical, showsCardChrome ? AppTheme.Spacing.md : 0)
        .backgroundIf(showsCardChrome) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colour.controlBackground.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(AppTheme.Colour.border, lineWidth: 1)
                )
        }
    }

    private var destinationBinding: Binding<SavePreference.Destination> {
        Binding(
            get: { destination },
            set: { destination = $0 }
        )
    }
}

private extension View {
    @ViewBuilder
    func backgroundIf<S: View>(_ condition: Bool, @ViewBuilder style: () -> S) -> some View {
        if condition {
            background { style() }
        } else {
            self
        }
    }
}
