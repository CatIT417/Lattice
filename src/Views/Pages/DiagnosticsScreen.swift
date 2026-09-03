import SwiftUI
import SQLiteData

struct DiagnosticsScreen: View {
	@Environment(\.dismiss) private var dismiss
	@Dependency(\.defaultSyncEngine) private var syncEngine

	@State private var isBackingUp = false
	@State private var backups: [URL] = []
	@State private var lastMergeCount: Int?
	@State private var health = SyncHealth.shared

	@FetchOne(Page.all.count()) private var pageCount = 0
	@FetchOne(Paragraph.all.count()) private var paragraphCount = 0

	var body: some View {
		NavigationStack {
			List {
				syncSection
				contentSection
				issuesSection
				maintenanceSection
				backupsSection
			}
			.navigationTitle("Diagnostics")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") { dismiss() }
				}
			}
			.task { refreshBackups() }
		}
		#if os(macOS)
		.frame(minWidth: 480, minHeight: 480)
		#endif
	}

	private var syncSection: some View {
		Section("iCloud sync") {
			LabeledContent("Running", value: syncEngine.isRunning ? "Yes" : "No")
			LabeledContent("Sending changes", value: syncEngine.isSendingChanges ? "Yes" : "No")
			LabeledContent("Fetching changes", value: syncEngine.isFetchingChanges ? "Yes" : "No")
			LabeledContent("Failures since launch", value: "\(health.syncFailureCount)")

			Button("Sync now") {
				Task {
					await withErrorReporting { try await syncEngine.syncChanges() }
				}
			}
		}
	}

	private var contentSection: some View {
		Section("Content") {
			LabeledContent("Pages", value: "\(pageCount)")
			LabeledContent("Paragraphs", value: "\(paragraphCount)")
		}
	}

	private var issuesSection: some View {
		Section("Recent issues") {
			if health.issues.isEmpty {
				Text("None")
					.foregroundStyle(.secondary)
			} else {
				ForEach(health.issues.reversed()) { issue in
					VStack(alignment: .leading, spacing: 2) {
						Text(issue.message)
							.font(.callout)
							.lineLimit(4)

						Text(issue.date, format: .dateTime)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
		}
	}

	private var maintenanceSection: some View {
		Section("Maintenance") {
			Button("Merge duplicate pages") {
				Task { lastMergeCount = try? await MergeDuplicatePages.run().count }
			}

			if let lastMergeCount {
				Text("Merged \(lastMergeCount) page(s)")
					.foregroundStyle(.secondary)
			}
		}
	}

	private var backupsSection: some View {
		Section("Backups") {
			if backups.isEmpty {
				Text("No backups yet")
					.foregroundStyle(.secondary)
			}

			ForEach(backups, id: \.self) { backup in
				HStack {
					Text(backup.lastPathComponent)
						.font(.callout.monospaced())

					Spacer()

					ShareLink(item: backup)
				}
			}

			Button("Back up now") {
				isBackingUp = true

				Task {
					await Task.detached(priority: .userInitiated) { DatabaseBackups.backup(force: true) }.value
					refreshBackups()
					isBackingUp = false
				}
			}
			.disabled(isBackingUp)
		}
	}

	private func refreshBackups() {
		backups = (try? DatabaseBackups.existingBackups()) ?? []
	}
}

#Preview {
	let _ = previewData()

	DiagnosticsScreen()
}
