import Foundation
import SQLiteData

/// Links between blocks (the [[wiki links]] and ((block refs)))
@Table
struct Backlink: Equatable, Hashable, Sendable {
	var fromBlock: Block.ID
	var toBlock: Block.ID
	var kind: Reference.Kind
	var sourceText: String
	@Column("fromPageTitle")
	var fromPageCanonicalTitle: String
	var fromPageId: Page.ID

	var fromPageTitle: String {
		Page.title(for: fromPageCanonicalTitle)
	}
}

extension Backlink {
	@Selection
	struct GroupedByPage: Identifiable {
		let pageID: Page.ID
		@Column("pageTitle")
		let canonicalPageTitle: String
		@Column(as: [Block.ID].JSONRepresentation.self)
		var referencedBlockIDs: [Block.ID]

		var pageTitle: String {
			Page.title(for: canonicalPageTitle)
		}

		var id: Page.ID {
			pageID
		}
	}

	static func groupedByPage(forBlock blockId: Block.ID) -> Select<GroupedByPage, Self, Void> {
		group(by: \.fromPageId)
			.order(by: \.fromBlock)
			.where { $0.toBlock.eq(blockId) }
			.select {
				GroupedByPage.Columns(
					pageID: $0.fromPageId,
					canonicalPageTitle: $0.fromPageCanonicalTitle,
					referencedBlockIDs: $0.fromBlock.jsonGroupArray(distinct: true)
				)
			}
	}

	static func unlinkedReferences(forPage pageId: Page.ID, title: String) -> some PartialSelectStatement<GroupedByPage> {
		let displayTitle = Page.title(for: title)
		return Paragraph
			.where { $0.pageId.neq(pageId) }
			.where {
				$0.id.notIn(
					Backlink
						.select(\.fromBlock)
						.where { $0.toBlock.eq(pageId) }
				)
			}
			.group(by: \.pageId)
			.join(BlockText.all) { $0.id.eq($1.blockID) }
			.where { _, blockTexts in blockTexts.match("(\(title.quoted())) OR (\(displayTitle.quoted()))") }
			.where { paragraphs, _ in $containsOutsideRefs(paragraphs.string, title) || $containsOutsideRefs(paragraphs.string, displayTitle) }
			.join(Page.all) { $0.pageId.eq($2.id) }
			.select { paragraphs, _, pages in
				GroupedByPage.Columns(
					pageID: pages.id,
					canonicalPageTitle: pages.canonicalTitle,
					referencedBlockIDs: paragraphs.id.jsonGroupArray()
				)
			}
	}

	static func unlinkedReferenceCount(forPage pageId: Page.ID, title: String) -> Select<Int, Paragraph, BlockText> {
		let displayTitle = Page.title(for: title)
		return Paragraph
			.where { $0.pageId.neq(pageId) }
			.where {
				$0.id.notIn(
					Backlink
						.select(\.fromBlock)
						.where { $0.toBlock.eq(pageId) }
				)
			}
			.join(BlockText.all) { $0.id.eq($1.blockID) }
			.where { _, blockTexts in blockTexts.match("(\(title.quoted())) OR (\(displayTitle.quoted()))") }
			.where { paragraphs, _ in $containsOutsideRefs(paragraphs.string, title) || $containsOutsideRefs(paragraphs.string, displayTitle) }
			.count()
	}
}

extension [Backlink.GroupedByPage] {
	var backlinkCount: Int {
		reduce(0) { $0 + $1.referencedBlockIDs.count }
	}
}
