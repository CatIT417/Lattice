import SwiftUI
import SQLiteData

struct PageWithBacklinks: View {
	struct Content {
		struct Input: Equatable {
			let paragraphs: [Paragraph]
			let referencedBlockIDs: [Block.ID]
		}

		var paragraphs: [Paragraph] = []
		var tree = BlockTree(paragraphs: [])

		init() {}

		init(input: Input) {
			var seen = Set<Block.ID>()
			let tree = BlockTree(paragraphs: input.paragraphs)

			self.tree = tree
			paragraphs = input.referencedBlockIDs
				.compactMap { id in
					guard seen.insert(id).inserted else { return nil }
					return tree.get(byID: id)
				}
				.sorted(using: KeyPathComparator(\.order, order: .forward))
		}
	}

	let backlinks: Backlink.GroupedByPage

	@State private var isExpanded = true
	@State private var content = Content()
	@FetchAll private var paragraphs: [Paragraph]

	init(backlinks: Backlink.GroupedByPage) {
		self.backlinks = backlinks
		_paragraphs = FetchAll(Paragraph.subtrees(rootedAt: backlinks.referencedBlockIDs))
	}

	var body: some View {
		let input = Content.Input(
			paragraphs: paragraphs,
			referencedBlockIDs: backlinks.referencedBlockIDs
		)

		VStack(alignment: .leading, spacing: 8) {
			DisclosureGroup(isExpanded: $isExpanded) {
				if !content.paragraphs.isEmpty {
					LazyVStack(alignment: .leading, spacing: 8) {
						ForEach(content.paragraphs) { paragraph in
							ParagraphView(paragraph: paragraph)
								.padding(12)
								.environment(\.rootBlockID, paragraph.id)
								.background(.thinMaterial, in: .rect(cornerRadius: 12))
						}
					}
					.environment(\.blockTree, content.tree)
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
		.onChange(of: input, initial: true) { _, input in
			content = Content(input: input)
		}
	}
}
