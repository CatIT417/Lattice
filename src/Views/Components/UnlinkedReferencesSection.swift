import SwiftUI
import SQLiteData

struct UnlinkedReferencesSection: View {
	private struct QueryID: Equatable {
		let pageId: Page.ID
		let title: String
	}

	let pageId: Page.ID
	let title: String

	@State private var isExpanded = false
	@State private var initialCount: Int?
	@State private var initialCountQueryID: QueryID?
	@State private var hasLoadedReferences = false
	@FetchAll(Backlink.GroupedByPage.none) private var pagesWithUnlinkedRefs: [Backlink.GroupedByPage]
	@Dependency(\.defaultDatabase) private var database

	init(forPage pageId: Page.ID, title: String) {
		self.pageId = pageId
		self.title = title
	}

	private var queryID: QueryID {
		QueryID(pageId: pageId, title: title)
	}

	private var count: Int? {
		guard initialCountQueryID == queryID else { return nil }
		return hasLoadedReferences ? pagesWithUnlinkedRefs.backlinkCount : initialCount
	}

	private var subscriptionID: QueryID? {
		guard isExpanded, let count, count > 0 else { return nil }
		return queryID
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if let count, count > 0 {
				DisclosureGroup(isExpanded: $isExpanded) {
					VStack(alignment: .leading, spacing: 12) {
						ForEach(pagesWithUnlinkedRefs) { page in
							PageWithBacklinks(backlinks: page)
						}
					}
				} label: {
					Text("\(count) Unlinked References")
					#if os(iOS)
						.font(.subheadline.weight(.semibold))
					#elseif os(macOS)
						.font(.title3.weight(.semibold))
					#endif
						.foregroundStyle(.secondary)
				}
				.disclosureGroupStyle(LeftLabelSectionDisclosureStyle(hidesArrowOnHover: true))
			}
		}
		.task(id: queryID) {
			let currentQueryID = queryID
			isExpanded = false
			initialCount = nil
			initialCountQueryID = nil
			hasLoadedReferences = false

			let count = await withErrorReporting {
				try await database.read { db in
					try Backlink.unlinkedReferenceCount(
						forPage: currentQueryID.pageId,
						title: currentQueryID.title
					).fetchOne(db) ?? 0
				}
			}

			guard !Task.isCancelled else { return }
			initialCount = count
			initialCountQueryID = currentQueryID
		}
		.task(id: subscriptionID) {
			guard let currentQueryID = subscriptionID else { return }

			await withErrorReporting {
				let subscription = try await $pagesWithUnlinkedRefs.load(
					Backlink.unlinkedReferences(
						forPage: currentQueryID.pageId,
						title: currentQueryID.title
					),
					animation: .default
				)
				try Task.checkCancellation()
				hasLoadedReferences = true
				try await subscription.task
			}
		}
		.onChange(of: count) { _, count in
			guard hasLoadedReferences, count == 0 else { return }
			isExpanded = false
		}
	}
}
