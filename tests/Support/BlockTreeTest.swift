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

	@Test("Paragraph lookup returns the paragraph with the given ID")
	func getsParagraphByID() {
		let pageID = UUID()
		let paragraph = Paragraph(string: "Block", parentId: pageID, pageId: pageID, order: 0)
		let tree = BlockTree(paragraphs: [paragraph])

		expectNoDifference(paragraph, tree.get(byID: paragraph.id))
		#expect(tree.get(byID: UUID()) == nil)
	}

	@Test("Subset lookup returns copied descendants")
	func subsetGetsDescendantsByID() {
		let pageID = UUID()
		let parent = Paragraph(string: "Parent", parentId: pageID, pageId: pageID, order: 0)
		let child = Paragraph(string: "Child", parentId: parent.id, pageId: pageID, order: 0)
		let tree = BlockTree(paragraphs: [parent, child]).subset(only: [parent.id])

		expectNoDifference(child, tree.get(byID: child.id))
	}
}
