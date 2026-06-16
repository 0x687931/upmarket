import SwiftUI
import AppKit

// MARK: - Tab enum

private enum Tab: CaseIterable, Identifiable {
	case general, conversion, automation, about

	var id: Self { self }

	var label: String {
		switch self {
		case .general: return "General"
		case .conversion: return "Conversion"
		case .automation: return "Automation"
		case .about: return "About"
		}
	}

	var icon: String {
		switch self {
		case .general: return "gearshape"
		case .conversion: return "doc.text"
		case .automation: return "desktopcomputer"
		case .about: return "info.circle"
		}
	}
}

// MARK: - SegButton component

private struct SegButton<T: Equatable>: View {
	let label: String
	@Binding var selection: T
	let value: T

	var body: some View {
		Button {
			selection = value
		} label: {
			Text(label)
				.font(.system(size: 13, weight: selection == value ? .semibold : .medium))
				.foregroundStyle(selection == value ? Color.accentColor : Color.secondary)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
				.padding(.horizontal, 10)
				.background(selection == value ? Color.accentColor.opacity(0.10) : Color.clear)
				.clipShape(RoundedRectangle(cornerRadius: 8))
				.overlay(
					RoundedRectangle(cornerRadius: 8)
						.stroke(selection == value ? Color.accentColor : AppTheme.Colour.separator,
								lineWidth: selection == value ? 1.5 : 1)
				)
		}
		.buttonStyle(.plain)
	}
}

// SegButtonAction — for complex cases with action closures
private struct SegButtonAction: View {
	let label: String
	let selected: Bool
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Text(label)
				.font(.system(size: 13, weight: selected ? .semibold : .medium))
				.foregroundStyle(selected ? Color.accentColor : Color.secondary)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 8)
				.padding(.horizontal, 10)
				.background(selected ? Color.accentColor.opacity(0.10) : Color.clear)
				.clipShape(RoundedRectangle(cornerRadius: 8))
				.overlay(
					RoundedRectangle(cornerRadius: 8)
						.stroke(selected ? Color.accentColor : AppTheme.Colour.separator,
								lineWidth: selected ? 1.5 : 1)
				)
		}
		.buttonStyle(.plain)
	}
}

// MARK: - PrefSection component

private struct PrefSection<Content: View>: View {
	let icon: String
	let color: Color
	let title: String
	@ViewBuilder var content: () -> Content

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(spacing: 10) {
				ZStack {
					RoundedRectangle(cornerRadius: 7)
						.fill(color.opacity(0.12))
						.frame(width: 28, height: 28)
					Image(systemName: icon)
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(color)
				}

				Text(title.uppercased())
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(.secondary)
					.kerning(0.4)
			}

			VStack(alignment: .leading, spacing: 10) {
				content()
			}
			.padding(.leading, 38)
		}
	}
}

// MARK: - PlanCard component

private struct PlanCard: View {
	let entitlement: AppTier

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: iconName)
				.font(.system(size: 16))
				.foregroundStyle(iconColor)
			VStack(alignment: .leading, spacing: 3) {
				Text(planName)
					.font(.system(size: 14, weight: .semibold))
				Text(planDetail)
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
			}
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(bgColor)
		.clipShape(RoundedRectangle(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1.5))
	}

	private var planName: String {
		switch entitlement {
		case .basic: return "Upmarket Basic"
		case .pro: return "Upmarket Pro"
		case .max: return "Upmarket Max"
		}
	}

	private var planDetail: String {
		switch entitlement {
		case .basic: return "Unlimited · Native conversion"
		case .pro: return "Unlimited · Enhanced conversion"
		case .max: return "Unlimited · AI pipeline included"
		}
	}

	private var iconName: String {
		switch entitlement {
		case .max: return "crown.fill"
		default: return "checkmark.circle.fill"
		}
	}

	private var iconColor: Color {
		switch entitlement {
		case .basic: return .secondary
		case .pro: return .accentColor
		case .max: return AppTheme.Colour.sectionAmber
		}
	}

	private var borderColor: Color {
		switch entitlement {
		case .basic: return AppTheme.Colour.separator
		case .pro: return .accentColor
		case .max: return AppTheme.Colour.sectionAmber
		}
	}

	private var bgColor: Color {
		switch entitlement {
		case .basic: return Color(nsColor: .controlBackgroundColor)
		case .pro: return .accentColor.opacity(0.06)
		case .max: return AppTheme.Colour.sectionAmber.opacity(0.06)
		}
	}
}

// MARK: - Main view

struct PreferencesView: View {
	@EnvironmentObject private var modelManager: ModelManager
	@EnvironmentObject private var store: StoreManager
	@EnvironmentObject private var watchedFolderService: WatchedFolderService

	@StateObject private var mcpIntegration = MCPIntegrationService.shared
	private let device = DeviceCapability.shared

	@State private var selectedTab: Tab = .general
	@State private var watchedFolderError: String?
	@State private var showAttributions = false
	@State private var showPaywall = false

	@AppStorage(AppVisibilityPreference.showDockIconKey) private var showDockIcon = AppVisibilityPreference.defaultShowDockIcon
	@AppStorage(AppVisibilityPreference.showMenuBarIconKey) private var showMenuBarIcon = AppVisibilityPreference.defaultShowMenuBarIcon
	@AppStorage(AppVisibilityPreference.showShelfKey) private var showShelf = AppVisibilityPreference.defaultShowShelf
	@AppStorage("upmarket.shelfAnchor") private var shelfAnchorRaw: Int = ShelfWindowController.ShelfAnchor.center.rawValue

	var body: some View {
		VStack(spacing: 0) {
			titleBar
			Divider()
			tabBar
			Divider()
			ScrollView {
				Group {
					switch selectedTab {
					case .general: generalTabContent
					case .conversion: conversionTabContent
					case .automation: automationTabContent
					case .about: aboutTabContent
					}
				}
				.padding(28)
				.id(selectedTab)
			}
			.transaction { $0.animation = nil }
		}
		.frame(width: 600)
		.sheet(isPresented: $showPaywall) {
			PaywallView()
				.environmentObject(store)
		}
		.onChange(of: showDockIcon) { value in
			AppVisibilityPreference.apply(showDockIcon: value)
			showDockIcon = AppVisibilityPreference.showDockIcon
		}
		.onChange(of: showMenuBarIcon) { _ in
			AppVisibilityPreference.normalizePersistentVisibility()
			AppVisibilityPreference.applyMenuBarVisibility(showMenuBarIcon: showMenuBarIcon)
		}
		.onChange(of: showShelf) { value in
			AppVisibilityPreference.applyShelfVisibility(showShelf: value)
		}
		.onAppear {
			AppVisibilityPreference.normalizePersistentVisibility()
			showDockIcon = AppVisibilityPreference.showDockIcon
			AppVisibilityPreference.apply(showDockIcon: showDockIcon)
			AppVisibilityPreference.applyMenuBarVisibility(showMenuBarIcon: showMenuBarIcon)
			if !showShelf { ShelfWindowController.shared.hide(animate: false) }
			modelManager.checkModels()
		}
	}

	// MARK: - Title bar

	private var titleBar: some View {
		HStack(spacing: 10) {
			ZStack {
				RoundedRectangle(cornerRadius: 8)
					.fill(Color.accentColor.opacity(0.10))
					.frame(width: 32, height: 32)
				Image(systemName: "slider.horizontal.3")
					.font(.system(size: 16, weight: .medium))
					.foregroundStyle(Color.accentColor)
			}

			Text("Preferences")
				.font(.system(size: 17, weight: .bold))
				.foregroundStyle(.primary)

			Spacer()
		}
		.padding(.horizontal, 28)
		.padding(.top, 20)
		.padding(.bottom, 16)
	}

	// MARK: - Tab bar

	private var tabBar: some View {
		HStack(spacing: 0) {
			ForEach(Tab.allCases) { tab in
				Button {
					selectedTab = tab
				} label: {
					VStack(spacing: 0) {
						HStack(spacing: 6) {
							Image(systemName: tab.icon)
								.font(.system(size: 13))
							Text(tab.label)
								.font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium))
						}
						.foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
						.padding(.horizontal, 14)
						.padding(.vertical, 10)

						Rectangle()
							.fill(selectedTab == tab ? Color.accentColor : Color.clear)
							.frame(height: 2)
					}
				}
				.buttonStyle(.plain)
			}
			Spacer()
		}
	}

	// MARK: - General tab

	private var generalTabContent: some View {
		VStack(alignment: .leading, spacing: 28) {
			PrefSection(icon: "app.badge", color: AppTheme.Colour.sectionBlue, title: "App Visibility") {
				Toggle("Show Dock icon", isOn: dockIconBinding)
				Toggle("Show in menu bar", isOn: menuBarIconBinding)
			}

			PrefSection(icon: "sidebar.right", color: .accentColor, title: "Shelf Widget") {
				HStack(spacing: 8) {
					Button {
						shelfAnchor.wrappedValue = .bottomLeft
					} label: {
						Text("Left")
							.font(.system(size: 13, weight: shelfAnchor.wrappedValue == .bottomLeft ? .semibold : .medium))
							.foregroundStyle(shelfAnchor.wrappedValue == .bottomLeft ? Color.accentColor : Color.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.padding(.horizontal, 10)
							.background(shelfAnchor.wrappedValue == .bottomLeft ? Color.accentColor.opacity(0.10) : Color.clear)
							.clipShape(RoundedRectangle(cornerRadius: 8))
							.overlay(
								RoundedRectangle(cornerRadius: 8)
									.stroke(shelfAnchor.wrappedValue == .bottomLeft ? Color.accentColor : AppTheme.Colour.separator,
											lineWidth: shelfAnchor.wrappedValue == .bottomLeft ? 1.5 : 1)
							)
					}
					.buttonStyle(.plain)

					Button {
						shelfAnchor.wrappedValue = .bottomRight
					} label: {
						Text("Right")
							.font(.system(size: 13, weight: shelfAnchor.wrappedValue == .bottomRight ? .semibold : .medium))
							.foregroundStyle(shelfAnchor.wrappedValue == .bottomRight ? Color.accentColor : Color.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.padding(.horizontal, 10)
							.background(shelfAnchor.wrappedValue == .bottomRight ? Color.accentColor.opacity(0.10) : Color.clear)
							.clipShape(RoundedRectangle(cornerRadius: 8))
							.overlay(
								RoundedRectangle(cornerRadius: 8)
									.stroke(shelfAnchor.wrappedValue == .bottomRight ? Color.accentColor : AppTheme.Colour.separator,
											lineWidth: shelfAnchor.wrappedValue == .bottomRight ? 1.5 : 1)
							)
					}
					.buttonStyle(.plain)
				}
				VStack(alignment: .leading, spacing: 4) {
					Toggle("Hide shelf when idle", isOn: $showShelf)
					Text("Hides the conversion sidebar after 10 seconds of inactivity")
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
				}
			}

			PrefSection(icon: "folder.fill", color: AppTheme.Colour.sectionGreen, title: "Save Location") {
				HStack {
					Picker("", selection: saveDestinationBinding) {
						Text("Same folder as original").tag(SavePreference.Destination.sameFolder)
						Text("Ask each time").tag(SavePreference.Destination.askEachTime)
						Text("Choose folder…").tag(SavePreference.Destination.chosenFolder)
					}
					.pickerStyle(.menu)
					.labelsHidden()
					Image(systemName: "chevron.down")
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(.secondary)
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 10)
				.background(Color(nsColor: .controlBackgroundColor))
				.clipShape(RoundedRectangle(cornerRadius: 8))
				.overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.Colour.separator, lineWidth: 0.5))
			}
		}
	}

	// MARK: - Conversion tab

	private var conversionTabContent: some View {
		VStack(alignment: .leading, spacing: 28) {
			PrefSection(icon: "doc.text", color: .accentColor, title: "Output Format") {
				HStack(spacing: 8) {
					Button {
						outputModeBinding.wrappedValue = .markdown
					} label: {
						Text("Markdown")
							.font(.system(size: 13, weight: outputModeBinding.wrappedValue == .markdown ? .semibold : .medium))
							.foregroundStyle(outputModeBinding.wrappedValue == .markdown ? Color.accentColor : Color.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.padding(.horizontal, 10)
							.background(outputModeBinding.wrappedValue == .markdown ? Color.accentColor.opacity(0.10) : Color.clear)
							.clipShape(RoundedRectangle(cornerRadius: 8))
							.overlay(
								RoundedRectangle(cornerRadius: 8)
									.stroke(outputModeBinding.wrappedValue == .markdown ? Color.accentColor : AppTheme.Colour.separator,
											lineWidth: outputModeBinding.wrappedValue == .markdown ? 1.5 : 1)
							)
					}
					.buttonStyle(.plain)

					Button {
						outputModeBinding.wrappedValue = .json
					} label: {
						Text("JSON")
							.font(.system(size: 13, weight: outputModeBinding.wrappedValue == .json ? .semibold : .medium))
							.foregroundStyle(outputModeBinding.wrappedValue == .json ? Color.accentColor : Color.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.padding(.horizontal, 10)
							.background(outputModeBinding.wrappedValue == .json ? Color.accentColor.opacity(0.10) : Color.clear)
							.clipShape(RoundedRectangle(cornerRadius: 8))
							.overlay(
								RoundedRectangle(cornerRadius: 8)
									.stroke(outputModeBinding.wrappedValue == .json ? Color.accentColor : AppTheme.Colour.separator,
											lineWidth: outputModeBinding.wrappedValue == .json ? 1.5 : 1)
							)
					}
					.buttonStyle(.plain)
				}
			}

			PrefSection(icon: "brain.head.profile", color: AppTheme.Colour.sectionPurple, title: "AI Models") {
				Text("Download models to unlock enhanced and AI-powered conversion. Everything runs on your Mac — nothing is sent to the cloud.")
					.font(.system(size: 13))
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.bottom, 4)

				VStack(spacing: 8) {
					ModelManagementRow(asset: .upmarketAI, onUpgrade: { showPaywall = true })
						.environmentObject(modelManager)
						.environmentObject(store)
				}
			}
		}
	}

	// MARK: - Automation tab

	private var automationTabContent: some View {
		VStack(alignment: .leading, spacing: 28) {
			PrefSection(icon: "folder.badge.magnifyingglass", color: AppTheme.Colour.sectionAmber, title: "Watched Folders") {
				if watchedFolderService.folders.isEmpty {
					VStack(spacing: 8) {
						Image(systemName: "folder.badge.plus")
							.font(.system(size: 24))
							.foregroundStyle(.tertiary)
						VStack(spacing: 2) {
							Text("No folders watched yet")
								.font(.system(size: 13, weight: .medium))
								.foregroundStyle(.secondary)
							Text("Click \"Add Folder…\" to start watching folders")
								.font(.system(size: 12))
								.foregroundStyle(.tertiary)
						}
					}
					.frame(maxWidth: .infinity)
					.padding(.vertical, 20)
					.background(Color(nsColor: .controlBackgroundColor))
					.clipShape(RoundedRectangle(cornerRadius: 8))
					.overlay(
						RoundedRectangle(cornerRadius: 8)
							.stroke(AppTheme.Colour.separator, style: StrokeStyle(lineWidth: 1, dash: [4]))
					)
				}

				Button("Add Folder…") { chooseWatchedFolder() }
					.buttonStyle(.bordered)
					.frame(maxWidth: .infinity)
			}

			PrefSection(icon: "line.3.horizontal.decrease.circle", color: AppTheme.Colour.sectionRed, title: "File Types") {
				HStack(spacing: 8) {
					Button {
						watchedFolderService.includePatterns = ""
					} label: {
						Text("All")
							.font(.system(size: 13, weight: usesAllWatchedFileTypes ? .semibold : .medium))
							.foregroundStyle(usesAllWatchedFileTypes ? Color.accentColor : Color.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.padding(.horizontal, 10)
							.background(usesAllWatchedFileTypes ? Color.accentColor.opacity(0.10) : Color.clear)
							.clipShape(RoundedRectangle(cornerRadius: 8))
							.overlay(
								RoundedRectangle(cornerRadius: 8)
									.stroke(usesAllWatchedFileTypes ? Color.accentColor : AppTheme.Colour.separator,
											lineWidth: usesAllWatchedFileTypes ? 1.5 : 1)
							)
					}
					.buttonStyle(.plain)

					Button {
						watchedFolderService.includePatterns = Self.watchDocumentOptions.flatMap(\.patterns).joined(separator: ", ")
					} label: {
						let selected = patternsEqual(Self.watchDocumentOptions.flatMap(\.patterns), watchedFolderService.includePatterns)
						Text("Docs only")
							.font(.system(size: 13, weight: selected ? .semibold : .medium))
							.foregroundStyle(selected ? Color.accentColor : Color.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.padding(.horizontal, 10)
							.background(selected ? Color.accentColor.opacity(0.10) : Color.clear)
							.clipShape(RoundedRectangle(cornerRadius: 8))
							.overlay(
								RoundedRectangle(cornerRadius: 8)
									.stroke(selected ? Color.accentColor : AppTheme.Colour.separator,
											lineWidth: selected ? 1.5 : 1)
							)
					}
					.buttonStyle(.plain)

					Button {
						watchedFolderService.includePatterns = watchDocumentAndImagePatterns.joined(separator: ", ")
					} label: {
						let selected = patternsEqual(watchDocumentAndImagePatterns, watchedFolderService.includePatterns)
						Text("Docs + Images")
							.font(.system(size: 13, weight: selected ? .semibold : .medium))
							.foregroundStyle(selected ? Color.accentColor : Color.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
							.padding(.horizontal, 10)
							.background(selected ? Color.accentColor.opacity(0.10) : Color.clear)
							.clipShape(RoundedRectangle(cornerRadius: 8))
							.overlay(
								RoundedRectangle(cornerRadius: 8)
									.stroke(selected ? Color.accentColor : AppTheme.Colour.separator,
											lineWidth: selected ? 1.5 : 1)
							)
					}
					.buttonStyle(.plain)
				}
				Toggle("Skip temporary files (.tmp, ~$)", isOn: defaultWatchedExclusionsBinding)
			}
		}
	}

	// MARK: - About tab

	private var aboutTabContent: some View {
		VStack(alignment: .leading, spacing: 28) {
			PrefSection(icon: "shippingbox.fill", color: .accentColor, title: "App") {
				HStack(spacing: 14) {
					Image(nsImage: NSApp.applicationIconImage)
						.resizable()
						.frame(width: 32, height: 32)
						.clipShape(RoundedRectangle(cornerRadius: 8))

					VStack(alignment: .leading, spacing: 3) {
						Text("Upmarket")
							.font(.system(size: 14, weight: .semibold))
						Text("Version \(appVersionLabel) · macOS 15.0+")
							.font(.system(size: 12))
							.foregroundStyle(.secondary)
					}
				}
				.padding(14)
				.background(Color(nsColor: .controlBackgroundColor))
				.clipShape(RoundedRectangle(cornerRadius: 10))
				.overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.Colour.separator, lineWidth: 0.5))
			}

			PrefSection(icon: "crown.fill", color: AppTheme.Colour.sectionAmber, title: "Plan") {
				PlanCard(entitlement: store.tier)

				Button("Restore Purchases") { Task { await store.restorePurchases() } }
					.buttonStyle(.plain)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.secondary)
			}

			// Command-line tool is a Pro/Max feature. The sandboxed app can't symlink into
			// /usr/local/bin itself, so we surface the one-time install command to copy.
			if store.tier >= .pro {
				PrefSection(icon: "terminal.fill", color: AppTheme.Colour.sectionBlue, title: "Command-Line Tool") {
					let cmd = "sudo ln -sf \"\(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/upmarket-cli").path)\" /usr/local/bin/upmarket-cli"
					VStack(alignment: .leading, spacing: 8) {
						Text("Install upmarket-cli to convert from Terminal. Run once:")
							.font(.system(size: 12))
							.foregroundStyle(.secondary)
						HStack(alignment: .top, spacing: 8) {
							Text(cmd)
								.font(.system(size: 11, design: .monospaced))
								.textSelection(.enabled)
								.lineLimit(3)
							Spacer()
							Button("Copy") { FileAccessService.shared.copyText(cmd) }
							.controlSize(.small)
						}
					}
					.padding(14)
					.background(Color(nsColor: .controlBackgroundColor))
					.clipShape(RoundedRectangle(cornerRadius: 10))
					.overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.Colour.separator, lineWidth: 0.5))
				}
			}

			#if DEBUG
			PrefSection(icon: "hammer.fill", color: Color.red, title: "Debug Tier Override") {
				VStack(spacing: 8) {
					Text("Current: \(store.tier.displayName)")
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.secondary)
					HStack(spacing: 8) {
						Button("Basic") { store.setDebugTier(.basic) }
							.buttonStyle(.bordered)
							.controlSize(.small)
						Button("Pro") { store.setDebugTier(.pro) }
							.buttonStyle(.bordered)
							.controlSize(.small)
						Button("Max") { store.setDebugTier(.max) }
							.buttonStyle(.bordered)
							.controlSize(.small)
					}
				}
			}
			#endif
		}
	}

	// MARK: - Bindings

	private var dockIconBinding: Binding<Bool> {
		Binding(
			get: { AppVisibilityPreference.showDockIcon },
			set: { AppVisibilityPreference.showDockIcon = $0; showDockIcon = AppVisibilityPreference.showDockIcon }
		)
	}

	private var menuBarIconBinding: Binding<Bool> {
		Binding(get: { showMenuBarIcon }, set: { showMenuBarIcon = $0 })
	}

	private var shelfAnchor: Binding<ShelfWindowController.ShelfAnchor> {
		Binding(
			get: { ShelfWindowController.ShelfAnchor(rawValue: shelfAnchorRaw) ?? .center },
			set: { shelfAnchorRaw = $0.rawValue; ShelfWindowController.shared.anchor = $0; ShelfWindowController.shared.reposition() }
		)
	}

	private var saveDestinationBinding: Binding<SavePreference.Destination> {
		Binding(get: { SavePreference.shared.destination }, set: { SavePreference.shared.destination = $0 })
	}

	private var outputModeBinding: Binding<OutputMode> {
		Binding(get: { OutputPreference.shared.mode }, set: { OutputPreference.shared.mode = $0 })
	}

	private var usesAllWatchedFileTypes: Bool {
		watchedFolderService.includePatterns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private var usesDefaultWatchedExclusions: Bool {
		containsAll(defaultWatchedExclusionPatterns, in: watchedFolderService.excludePatterns)
	}

	private var defaultWatchedExclusionsBinding: Binding<Bool> {
		Binding(
			get: { usesDefaultWatchedExclusions },
			set: { watchedFolderService.excludePatterns = $0 ? defaultWatchedExclusionPatterns.joined(separator: ", ") : "" }
		)
	}

	private var appVersionLabel: String {
		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
		case let (.some(v), .some(b)): return "Version \(v) (\(b))"
		case let (.some(v), .none): return "Version \(v)"
		case let (.none, .some(b)): return "Build \(b)"
		case (.none, .none): return "Version unknown"
		}
	}

	// MARK: - File patterns

	private static let watchDocumentOptions: [WatchPatternOption] = [
		WatchPatternOption(title: "PDF", detail: ".pdf", patterns: ["*.pdf"]),
		WatchPatternOption(title: "Word", detail: ".docx", patterns: ["*.docx"]),
		WatchPatternOption(title: "Slides", detail: ".pptx", patterns: ["*.pptx"]),
		WatchPatternOption(title: "Sheets", detail: ".xlsx", patterns: ["*.xlsx"]),
		WatchPatternOption(title: "HTML", detail: ".html", patterns: ["*.html", "*.htm"]),
		WatchPatternOption(title: "Text", detail: ".txt", patterns: ["*.txt"]),
		WatchPatternOption(title: "EPUB", detail: ".epub", patterns: ["*.epub"]),
		WatchPatternOption(title: "ZIP", detail: ".zip", patterns: ["*.zip"]),
		WatchPatternOption(title: "CSV", detail: ".csv", patterns: ["*.csv"]),
		WatchPatternOption(title: "XML", detail: ".xml", patterns: ["*.xml"]),
	]
	private static let watchImageOptions: [WatchPatternOption] = [
		WatchPatternOption(title: "PNG", detail: ".png", patterns: ["*.png"]),
		WatchPatternOption(title: "JPEG", detail: ".jpg", patterns: ["*.jpg", "*.jpeg"]),
		WatchPatternOption(title: "GIF", detail: ".gif", patterns: ["*.gif"]),
		WatchPatternOption(title: "TIFF", detail: ".tiff", patterns: ["*.tif", "*.tiff"]),
	]
	private static let watchAudioOptions: [WatchPatternOption] = [
		WatchPatternOption(title: "MP3/M4A", detail: ".mp3 .m4a", patterns: ["*.mp3", "*.m4a"]),
		WatchPatternOption(title: "WAV/AIFF", detail: "+ Opus", patterns: ["*.wav", "*.aiff", "*.opus"]),
	]
	private static let watchExcludeOptions: [WatchPatternOption] = [
		WatchPatternOption(title: "Converted outputs", detail: "Markdown and JSON", patterns: ["*.md", "*.markdown", "*.json"]),
		WatchPatternOption(title: "Temporary downloads", detail: "Partial download files", patterns: ["*.tmp", "*.download", "*.part", "*.crdownload", "~$*"]),
		WatchPatternOption(title: "Drafts", detail: "Files with 'draft' in name", patterns: ["*draft*"]),
	]

	private var watchDocumentAndImagePatterns: [String] {
		(Self.watchDocumentOptions + Self.watchImageOptions).flatMap(\.patterns)
	}

	private var defaultWatchedExclusionPatterns: [String] {
		Self.watchExcludeOptions.flatMap(\.patterns)
	}

	// MARK: - Pattern helpers

	private func containsAll(_ patterns: [String], in rawPatterns: String) -> Bool {
		let tokens = Set(patternTokens(rawPatterns))
		return patterns.map { $0.lowercased() }.allSatisfy { tokens.contains($0) }
	}

	private func patternsEqual(_ patterns: [String], _ rawPatterns: String) -> Bool {
		Set(patterns.map { $0.lowercased() }) == Set(patternTokens(rawPatterns))
	}

	private func patternTokens(_ rawPatterns: String) -> [String] {
		var seen = Set<String>()
		return rawPatterns
			.split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
			.map { String($0).lowercased() }
			.filter { seen.insert($0).inserted }
	}

	// MARK: - Folder actions

	private func chooseWatchedFolder() {
		watchedFolderError = nil
		guard let url = FileAccessService.shared.chooseDirectory(message: "Choose a folder for Upmarket to watch.", prompt: "Watch") else { return }
		do { try watchedFolderService.addFolder(url) } catch { watchedFolderError = FileAccessService.userVisibleMessage(for: error) }
	}
}

// MARK: - Supporting types

private struct WatchPatternOption: Identifiable {
	var id: String { title }
	let title: String
	let detail: String
	let patterns: [String]
}

// MARK: - Model Status Row

// MARK: - ModelManagementRow

private struct ModelManagementRow: View {
	let asset: ModelAsset
	@EnvironmentObject private var modelManager: ModelManager
	@EnvironmentObject private var store: StoreManager
	var onUpgrade: () -> Void

	private var gate: AppTierGate { modelManager.gate(tier: store.tier) }
	private var isDownloaded: Bool { modelManager.downloadedAssets.contains(asset) }
	private var isBundled: Bool { asset.delivery == .bundledInApp }
	private var gateReason: String? { gate.downloadUnavailableReason(for: asset) }
	private var isLocked: Bool { store.tier < asset.requiredTier }
	private var isDownloading: Bool { modelManager.isDownloading && modelManager.downloadingModelKey == asset.rawValue }
	private var canDownload: Bool { gateReason == nil && !isDownloaded }

	private var badgeLabel: String {
		switch asset.requiredTier {
		case .pro:  return "PRO"
		case .max:  return "MAX"
		case .basic: return ""
		}
	}

	private var stateDescription: String {
		if isLocked {
			return gateReason ?? "Requires \(asset.requiredTier.displayName)"
		}
		if isDownloading {
			return "Downloading…"
		}

		switch asset {
		case .upmarketAI:
			let sizeString = isDownloaded
				? "\(modelManager.actualInstalledSizeMB(.upmarketAI)) MB installed"
				: "\(asset.sizeMB) MB (one-time download)"
			return "Understands scanned pages and complex documents · \(sizeString)"
		}
	}

	private var stateIconName: String {
		if isLocked        { return "lock.fill" }
		if isDownloading   { return "arrow.down.circle.fill" }
		if isDownloaded    { return "checkmark.circle.fill" }
		return "sparkles"
	}

	private var iconColor: Color {
		if isLocked        { return .secondary }
		if isDownloading   { return .accentColor }
		if isDownloaded    { return Color(red: 0.2, green: 0.78, blue: 0.35) }
		return .accentColor
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 12) {
				// Icon
				ZStack {
					Circle()
						.fill(iconColor.opacity(0.12))
						.frame(width: 28, height: 28)
					Image(systemName: stateIconName)
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(iconColor)
				}

				// Name + description
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 6) {
						Text(asset.displayName)
							.font(.system(size: 14, weight: .medium))
						if !badgeLabel.isEmpty {
							AppBadge(badgeLabel, variant: .accent)
						}
					}
					Text(stateDescription)
						.font(.system(size: 12))
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}

				Spacer(minLength: 8)

				// Right action area
				HStack(spacing: 8) {
					rightLabel
					rightAction
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)

			// Progress bar during download
			if isDownloading {
				ProgressView(value: modelManager.downloadProgress, total: 100)
					.progressViewStyle(.linear)
					.tint(Color.accentColor)
					.padding(.horizontal, 12)
					.padding(.bottom, 10)
			}
		}
		.background(Color(nsColor: .controlBackgroundColor))
		.clipShape(RoundedRectangle(cornerRadius: 8))
		.overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.Colour.separator, lineWidth: 0.5))
		.opacity(isLocked ? 0.75 : 1.0)
	}

	@ViewBuilder private var rightLabel: some View {
		if isDownloading {
			Text("\(Int(modelManager.downloadProgress))%")
				.font(.system(size: 12, weight: .semibold).monospacedDigit())
				.foregroundStyle(Color.accentColor)
		} else if isDownloaded {
			Text("Ready")
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.35))
		} else if !isLocked {
			Text("\(asset.sizeMB) MB")
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder private var rightAction: some View {
		if isBundled {
			EmptyView()
		} else if isLocked {
			Button("Upgrade") {
				onUpgrade()
			}
			.buttonStyle(.plain)
			.font(.system(size: 12, weight: .medium))
			.foregroundStyle(Color.accentColor)
		} else if isDownloading {
			EmptyView()
		} else if isDownloaded {
			Button("Delete") {
				modelManager.deleteModel(key: asset.rawValue)
			}
			.buttonStyle(AppActionButtonStyle())
			.controlSize(.small)
			.foregroundStyle(Color(red: 1.0, green: 0.2, blue: 0.35))
		} else if canDownload {
			Button("Download") {
				modelManager.downloadAsset(asset, gate: gate)
			}
			.buttonStyle(AppActionButtonStyle())
			.controlSize(.small)
		}
	}
}

#Preview {
	PreferencesView()
		.environmentObject(ModelManager.shared)
		.environmentObject(StoreManager.shared)
		.environmentObject(WatchedFolderService.shared)
}
