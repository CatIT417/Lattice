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
				guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
					return try await $results.load(Block.none, animation: .default)
				}

				return try await $results.load(
					Block.where {
						for term in searchText.split(separator: " ") {
							$0.title.map({ $0.contains(term) }, or: false) || $0.string.map({ $0.contains(term) }, or: false)
						}
					}.order {
						($0.title.isNot(nil).desc(), $0.order)
					},
					animation: .default
				)
			}
		}
	}
}
