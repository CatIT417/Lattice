import GRDB
import Foundation
import SQLiteData

fileprivate nonisolated let logger = Logger(category: "Maintenance")

/// Watch for pages with duplicate titles and merge them into a single page.
@MainActor final class DuplicatePagesWatcher {
	private var cancellable: AnyDatabaseCancellable?
	private var pendingMerge: Task<Void, Never>?

	func start() {
		guard cancellable == nil else { return }
		@Dependency(\.defaultDatabase) var database

		cancellable = ValueObservation
			.tracking { db in try MergeDuplicatePages.duplicateTitles.fetchAll(db) }
			.start(in: database, scheduling: .async(onQueue: .main), onError: { reportIssue($0) }) { [weak self] titles in
				guard !titles.isEmpty else { return }

				Task { @MainActor in self?.queueMerge() }
			}
	}

	private func queueMerge() {
		pendingMerge?.cancel()
		pendingMerge = Task { @MainActor in
			try? await Task.sleep(for: .seconds(1))
			guard !Task.isCancelled else { return }

			@Dependency(\.defaultDatabase) var database

			let merges = await withErrorReporting {
				try await MergeDuplicatePages.run()
			} ?? []

			if !merges.isEmpty {
				logger.info("merged \(merges.count) duplicate page(s)")
			}
		}
	}
}
