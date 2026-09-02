import SwiftUI
import SQLiteData

struct PageWithBacklinks: View {
	let backlinks: Backlink.GroupedByPage

	@State private var isExpanded = true
	@FetchAll private var paragraphs: [Paragraph]

	init(backlinks: Backlink.GroupedByPage) {
		self.backlinks = backlinks
		_paragraphs = FetchAll(Paragraph.subtrees(rootedAt: backlinks.referencedBlockIDs))
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			DisclosureGroup(isExpanded: $isExpanded) {
				let referencedIDs = Set(backlinks.referencedBlockIDs)
				let referenced = paragraphs
					.filter { referencedIDs.contains($0.id) }
					.sorted(using: KeyPathComparator(\.order, order: .forward))

				if !referenced.isEmpty {
					LazyVStack(alignment: .leading, spacing: 8) {
						ForEach(referenced) { paragraph in
							ParagraphView(paragraph: paragraph)
								.padding(12)
								.environment(\.rootBlockID, paragraph.id)
								.background(.thinMaterial, in: .rect(cornerRadius: 12))
						}
					}
					.environment(\.blockTree, BlockTree(paragraphs: paragraphs))
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
