import SwiftUI

struct SaveLocationSettingsView: View {
    @Binding var destination: SavePreference.Destination
    @Binding var chosenFolderURL: URL?

    let title: String?
    let description: String?
    let onChooseFolder: () -> Void
    let showsCardChrome: Bool

    var body: some View {
        let content = VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
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
                            .buttonStyle(AppActionButtonStyle())
                            .controlSize(.small)
                    }
                }
            }
        }

        if showsCardChrome {
            AppSectionCard(title: title, subtitle: description) {
                content
            }
        } else {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if let title {
                    Text(title.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                }

                if let description {
                    Text(description)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
            }
        }
    }

    private var destinationBinding: Binding<SavePreference.Destination> {
        Binding(
            get: { destination },
            set: { destination = $0 }
        )
    }
}
