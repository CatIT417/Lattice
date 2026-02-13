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

private struct PageWithBacklinks: View {
	let backlinks: Backlink.GroupedByPage

	@State private var isExpanded = true
	@FetchOne private var pageWithContent: Page.WithChildren?

	init(backlinks: Backlink.GroupedByPage) {
		self.backlinks = backlinks
		_pageWithContent = FetchOne(Page.withChildren(id: backlinks.pageID))
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			DisclosureGroup(isExpanded: $isExpanded) {
				if let pageWithContent {
					let paragraphs = Set(backlinks.referencedBlockIDs).compactMap {
						pageWithContent.tree.get(byID: $0)
					}.sorted(using: KeyPathComparator(\.order, order: .forward))

					if !paragraphs.isEmpty {
						LazyVStack(alignment: .leading, spacing: 8) {
							ForEach(paragraphs) { paragraph in
								ParagraphView(paragraph: paragraph)
									.padding(12)
									.environment(\.rootBlockID, paragraph.id)
									.background(.thinMaterial, in: .rect(cornerRadius: 12))
							}
						}
						.environment(\.blockTree, pageWithContent.tree.subset(only: Set(backlinks.referencedBlockIDs)))
					}
				}
			} label: {
				NavigationButton(push: .page(id: backlinks.pageID)) {
					Text(backlinks.pageTitle)
					#if os(iOS)
						.font(.subheadline)
					#elseif os(macOS)
						.font(.title3)
					#endif
				}
				.buttonStyle(.plain)
				#if os(macOS)
					.pointerStyle(.link)
				#endif
			}
			.disclosureGroupStyle(LeftLabelSectionDisclosureStyle(hidesArrowOnHover: false))
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
