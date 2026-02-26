import SwiftUI
import SQLiteData

struct UnlinkedReferencesSection: View {
	let pageId: Page.ID
	let title: String

	@State private var isExpanded = false
	@FetchAll private var pagesWithUnlinkedRefs: [Backlink.GroupedByPage]

	init(forPage pageId: Page.ID, title: String) {
		self.pageId = pageId
		self.title = title
		_pagesWithUnlinkedRefs = FetchAll(Backlink.unlinkedReferences(forPage: pageId, title: title), animation: .default)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if !pagesWithUnlinkedRefs.isEmpty {
				DisclosureGroup(isExpanded: $isExpanded) {
					VStack(alignment: .leading, spacing: 12) {
						ForEach(pagesWithUnlinkedRefs) { page in
							PageWithBacklinks(backlinks: page)
						}
					}
				} label: {
					Text("\(pagesWithUnlinkedRefs.backlinkCount) Unlinked References")
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
	}
}
