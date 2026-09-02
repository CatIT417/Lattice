import Testing
import Foundation
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Support/BlockTree")
	struct BlockTreeTest {}
}

extension Tests.BlockTreeTest {
	@Test("Children come back sorted by order regardless of input order")
	func childrenAreSortedByOrder() {
		let pageID = UUID()
		let now = Date()
		let paragraphs = [2, 0, 1].map { order in
			Paragraph(id: UUID(), string: "Block \(order)", parentId: pageID, pageId: pageID, order: order, createdAt: now, updatedAt: now)
		}

		let tree = BlockTree(paragraphs: paragraphs)

		expectNoDifference([0, 1, 2], tree.children(of: pageID).map(\.order))
	}
}
