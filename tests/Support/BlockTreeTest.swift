import Testing
import Dependencies
import Foundation
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Support/BlockTree")
	struct BlockTreeTest {}
}

extension Tests.BlockTreeTest {
	@Test("Children are sorted by rank and then ID")
	func childrenAreSortedByOrder() {
		let pageID = UUID(100)
		let first = Paragraph(id: UUID(1), string: "First", parentId: pageID, pageId: pageID, order: 0)
		let tied = Paragraph(id: UUID(2), string: "Tied", parentId: pageID, pageId: pageID, order: 0)
		let last = Paragraph(id: UUID(3), string: "Last", parentId: pageID, pageId: pageID, order: 2)
		let tree = BlockTree(paragraphs: [last, tied, first])
		expectNoDifference(tree.children(of: pageID), [first, tied, last])
	}

	@Test("A subset copies descendants and excludes unrelated branches")
	func subsetGetsDescendantsByID() {
		let pageID = UUID(100)
		let parent = Paragraph(string: "Parent", parentId: pageID, pageId: pageID, order: 0)
		let child = Paragraph(string: "Child", parentId: parent.id, pageId: pageID, order: 0)
		let grandchild = Paragraph(string: "Grandchild", parentId: child.id, pageId: pageID, order: 0)
		let other = Paragraph(string: "Other", parentId: pageID, pageId: pageID, order: 1)
		let tree = BlockTree(paragraphs: [parent, child, grandchild, other]).subset(only: [parent.id])

		expectNoDifference(tree.children(of: parent.id), [child])
		expectNoDifference(tree.children(of: child.id), [grandchild])
		expectNoDifference(tree.get(byID: child.id), child)
		expectNoDifference(tree.get(byID: grandchild.id), grandchild)
		#expect(tree.get(byID: parent.id) == nil)
		#expect(tree.get(byID: other.id) == nil)
		#expect(tree.children(of: pageID).isEmpty)
	}
}
