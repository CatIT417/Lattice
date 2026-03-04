import SwiftUI
import SQLiteData
import UniformTypeIdentifiers

struct RoamImportModifier: ViewModifier {
	enum ParseError: Error, LocalizedError {
		case file(Error)
		case parse(Error)

		var errorDescription: String? {
			switch self {
				case .file: return "Failed to read the selected file."
				case .parse: return "Could not parse your Roam export. Please ensure it's in the correct format and try again."
			}
		}
	}

	struct ImportState {
		var currentConflict: Int?
		var conflictQueue = [Int]()
		var conflictResolved = false
		var failedPages = [RoamImporter.FailedPage]()
		var preparedPages = [RoamImporter.PreparedPage]()

		var totalPageCount = 0
		var isImporting = false
		var result: RoamImporter.Result?
		var failedPagesForSheet = [RoamImporter.FailedPage]()

		mutating func clear() {
			failedPages = []
			preparedPages = []
			conflictQueue = []
			currentConflict = nil
		}
	}

	@Environment(Router.self) private var router

	@State private var state = ImportState()
	@State private var parseError: ParseError?
	@State private var showingFileImporter = false

	func body(content: Content) -> some View {
		content
			.disabled(state.isImporting)
			.overlay {
				if state.isImporting {
					ZStack {
						Color.black.opacity(0.1)
							.ignoresSafeArea()

						ProgressView()
							.controlSize(.large)
							.padding(30)
							.background(.thinMaterial, in: .rect(cornerRadius: 12))
					}
				}
			}
			.toolbar {
				ToolbarItem {
					Button("Import", systemImage: "square.and.arrow.down") {
						showingFileImporter = true
					}
				}
			}
			.fileImporter(
				isPresented: $showingFileImporter,
				allowedContentTypes: [.json],
				onCompletion: handleFileSelected
			)
			.alert(isPresented: $parseError.isPresent(), error: parseError) {
				Button("OK", role: .cancel) {}
			}
			.alert(conflictTitle, isPresented: $state.currentConflict.isPresent()) {
				Button("Merge") { resolveConflict(.merge) }
				Button("Skip") { resolveConflict(.skip) }
				Button("Replace", role: .destructive) { resolveConflict(.replace) }
			} message: {
				Text("A page with this title already exists in Lattice.")
			}
			.onChange(of: state.currentConflict) { old, new in
				guard old != nil, new == nil else { return }

				if state.conflictResolved {
					state.conflictResolved = false
					advanceConflictQueueOrImport()
				} else {
					state.clear()
				}
			}
			.alert("Import Complete", isPresented: $state.result.isPresent(), presenting: state.result) { result in
				if !result.failed.isEmpty {
					Button("View Failed") {
						state.failedPagesForSheet = result.failed
					}
				}
				Button("OK", role: .cancel) {
					navigateIfSinglePage(result: result)
				}
			} message: { result in
				Text(summaryMessage(for: result))
			}
			.sheet(isPresented: .init(
				get: { !state.failedPagesForSheet.isEmpty },
				set: { if !$0 { state.failedPagesForSheet = [] } }
			)) {
				FailedPagesSheet(pages: state.failedPagesForSheet)
			}
	}

	// MARK: - File Handling

	private func handleFileSelected(_ result: Result<URL, Error>) {
		switch result {
			case let .failure(error) where (error as? CocoaError)?.code == .userCancelled: break
			case let .failure(error): parseError = .file(error)
			case let .success(url):
				Task {
					do {
						let (pageCount, valid, failed, conflicts) = try await Task.detached(priority: .userInitiated) {
							let importer = try RoamImporter(url: url)
							let (valid, failed) = importer.prepare()
							let conflicts = RoamImporter.detectConflicts(in: valid)
							return (importer.roamPages.count, valid, failed, conflicts)
						}.value

						state.failedPages = failed
						state.preparedPages = valid
						state.totalPageCount = pageCount
						state.conflictQueue = conflicts
						advanceConflictQueueOrImport()
					} catch {
						parseError = .parse(error)
					}
				}
		}
	}

	// MARK: - Conflict Resolution

	private var conflictTitle: String {
		guard let conflictIndex = state.currentConflict else { return "Page Already Exists" }
		return "\"\(state.preparedPages[conflictIndex].page.title)\" Already Exists"
	}

	private func resolveConflict(_ resolution: RoamImporter.ConflictResolution) {
		guard let conflictIndex = state.currentConflict else { return }
		state.preparedPages[conflictIndex].resolution = resolution
		state.conflictResolved = true
	}

	private func advanceConflictQueueOrImport() {
		if let next = state.conflictQueue.first {
			state.conflictQueue.removeFirst()
			state.currentConflict = next
		} else {
			state.currentConflict = nil
			executeImport()
		}
	}

	// MARK: - Import Execution

	private func executeImport() {
		let pages = state.preparedPages
		let failedPages = state.failedPages

		withAnimation { state.isImporting = true }

		Task {
			defer { withAnimation { state.isImporting = false } }

			await withErrorReporting {
				let result = try await Task.detached(priority: .userInitiated) {
					try RoamImporter.execute(pages: pages)
				}.value

				state.result = RoamImporter.Result(
					imported: result.imported,
					failed: failedPages + result.failed,
					skipped: result.skipped
				)
				state.clear()
			}
		}
	}

	// MARK: - Summary

	private func summaryMessage(for result: RoamImporter.Result) -> String {
		if result.imported.count == 1, result.skipped == 0, result.failed.isEmpty {
			return "\"\(result.imported[0].title)\" imported successfully."
		}

		var parts = [String]()
		if !result.imported.isEmpty {
			parts.append("\(pageLabel(for: result.imported.count)) imported")
		}
		if result.skipped > 0 {
			parts.append("\(result.skipped) skipped")
		}
		if !result.failed.isEmpty {
			parts.append("\(result.failed.count) failed")
		}
		return parts.joined(separator: ", ")
	}

	private func pageLabel(for count: Int) -> String {
		"\(count) page\(count == 1 ? "" : "s")"
	}

	private func navigateIfSinglePage(result: RoamImporter.Result) {
		defer { state.totalPageCount = 0 }

		guard state.totalPageCount == 1,
		      result.imported.count == 1,
		      let page = result.imported.first
		else { return }

		router.push(.page(id: page.id))
	}
}

// MARK: - Failed Pages Sheet

private struct FailedPagesSheet: View {
	let pages: [RoamImporter.FailedPage]

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List(pages.enumerated(), id: \.offset) { _, page in
				VStack(alignment: .leading) {
					Text(page.title)
						.font(.headline)

					Text(page.reason.localizedDescription)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.navigationTitle("Failed to Import")
			.navigationSubtitle("\(pages.count) page\(pages.count == 1 ? "" : "s")")
			#if os(iOS)
				.navigationBarTitleDisplayMode(.inline)
			#endif
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						Button(role: .close) { dismiss() }
					}
				}
				.presentationDetents([.medium, .large])
		}
	}
}

// MARK: - View Extension

extension View {
	func roamImport() -> some View {
		modifier(RoamImportModifier())
	}
}

#Preview("RoamImportModifier") {
	let _ = previewData()

	VStack {}
		.frame(maxWidth: .infinity)
		.roamImport()
		.preview()
}

#Preview("FailedPagesSheet") {
	@Previewable @State var showing = true

	VStack {}
		.sheet(isPresented: $showing) {
			FailedPagesSheet(pages: [
				.init(title: "S", reason: .titleTooShort),
				.init(title: "AB", reason: .titleTooShort),
			])
		}
}
