import SQLiteData
import Foundation

/// Links between blocks (the [[wiki links]] and ((block refs)))
@Table
struct Backlink: Equatable, Hashable, Sendable {
	var fromBlock: Block.ID
	var toBlock: Block.ID
	var kind: Reference.Kind
	var sourceText: String
	var fromPageTitle: String
	var fromPageId: Page.ID
}

extension Backlink {
	@Selection
	struct GroupedByPage: Identifiable {
		let pageID: Page.ID
		let pageTitle: String
		@Column(as: [Block.ID].JSONRepresentation.self)
		var referencedBlockIDs: [Block.ID]

		var id: Page.ID {
			pageID
		}
	}

	static func groupedByPage(forBlock blockId: Block.ID) -> Select<GroupedByPage, Self, Void> {
		group(by: \.fromPageId)
			.where { $0.toBlock.eq(blockId) }
			.select {
				GroupedByPage.Columns(
					pageID: $0.fromPageId,
					pageTitle: $0.fromPageTitle,
					referencedBlockIDs: $0.fromBlock.jsonGroupArray()
				)
			}
	}

	static func unlinkedReferences(forPage pageId: Page.ID, title: String) -> some PartialSelectStatement<GroupedByPage> {
		Paragraph
			.where { $0.pageId.neq(pageId) }
			.where {
				$0.id.notIn(
					Reference
						.select(\.sourceBlockId)
						.where { $0.targetBlockId.eq(pageId) }
				)
			}
			.group(by: \.pageId)
			.join(BlockText.all) { $0.id.eq($1.blockID) }
			.where { _, blockTexts in blockTexts.match(title.quoted()) }
			.where { paragraphs, _ in $containsOutsideRefs(paragraphs.string, title) }
			.join(Page.all) { $0.pageId.eq($2.id) }
			.select { paragraphs, _, pages in
				GroupedByPage.Columns(
					pageID: pages.id,
					pageTitle: pages.title,
					referencedBlockIDs: paragraphs.id.jsonGroupArray()
				)
			}
	}
}

extension [Backlink.GroupedByPage] {
	var backlinkCount: Int {
		reduce(0) { $0 + $1.referencedBlockIDs.count }
	}
}
