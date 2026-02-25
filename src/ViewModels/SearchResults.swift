import SwiftUI
import Foundation
import SQLiteData

@Observable @MainActor
final class SearchResults {
	@ObservationIgnored @FetchAll(Block.none, animation: .default) var results: [Block]

	var searchText: String = "" {
		didSet {
			if oldValue != searchText {
				updateQuery()
			}
		}
	}

	var hasEmptyQuery: Bool {
		searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	var hasShortQuery: Bool {
		let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		return !trimmed.isEmpty && trimmed.count < 3
	}

	var hasResults: Bool {
		!results.isEmpty
	}

	var isLoading: Bool {
		$results.isLoading
	}

	private var searchTask: Task<Void, any Error>?

	init() {}

	private func updateQuery() {
		@Dependency(\.continuousClock) var clock

		searchTask?.cancel()
		searchTask = Task {
			try await clock.sleep(for: .seconds(0.3))

			_ = await withErrorReporting {
				guard !hasEmptyQuery, !hasShortQuery else {
					return try await $results.load(Block.none, animation: .default)
				}

				return try await $results.load(
					Block
						.join(BlockText.all) { $0.id.eq($1.blockID) }
						.where { $1.match(searchText.trimmingCharacters(in: .whitespacesAndNewlines).quoted()) }
						.order { $1.bm25([\.title: 3]) }
						.select { block, _ in block },
					animation: .default
				)
			}
		}
	}
}
