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
}

extension [Backlink.GroupedByPage] {
	var backlinkCount: Int {
		reduce(0) { $0 + $1.referencedBlockIDs.count }
	}
}
