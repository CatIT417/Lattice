import SwiftUI
import SQLiteData

struct LinkedReferencesSection: View {
	let blockId: Block.ID

	@State private var isExpanded = true
	@FetchAll private var pagesWithBacklinks: [Backlink.GroupedByPage]

	init(forBlockID blockId: Block.ID) {
		self.blockId = blockId
		_pagesWithBacklinks = FetchAll(Backlink.groupedByPage(forBlock: blockId), animation: .default)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if !pagesWithBacklinks.isEmpty {
				DisclosureGroup(isExpanded: $isExpanded) {
					VStack(alignment: .leading, spacing: 12) {
						ForEach(pagesWithBacklinks) { page in
							PageWithBacklinks(backlinks: page)
						}
					}
				} label: {
					Text("\(pagesWithBacklinks.backlinkCount) Linked References")
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

#Preview {
	let blockId = previewData { db in
		try Backlink
			.group(by: \.toBlock)
			.order(by: { $0.toBlock.count().asc() })
			.fetchOne(db)?.toBlock
	}

	if let blockId {
		ScrollView {
			VStack {
				LinkedReferencesSection(forBlockID: blockId)
			}
			.padding()
		}
		.preview()
	} else {
		ProgressView()
	}
}
