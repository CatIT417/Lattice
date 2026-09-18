import SwiftUI

struct BlockTree {
	private let rootID: Block.ID?
	private let paragraphsById: [Block.ID: Paragraph]
	private let parentsWithUnloadedChildren: Set<Block.ID>
	private let childrenByParentId: [Block.ID: [Paragraph]]

	init(paragraphs: [Paragraph], parentsWithUnloadedChildren: Set<Block.ID> = [], rootID: Block.ID? = nil) {
		self.rootID = rootID
		self.parentsWithUnloadedChildren = parentsWithUnloadedChildren

		var indexed: [Block.ID: Paragraph] = [:]
		var grouped: [Block.ID: [Paragraph]] = [:]
		for p in paragraphs {
			indexed[p.id] = p
			grouped[p.parentId, default: []].append(p)
		}

		paragraphsById = indexed
		childrenByParentId = grouped.mapValues { $0.sorted(by: Paragraph.ordered) }
	}

	private init(childrenByParentId: [Block.ID: [Paragraph]], paragraphsById: [Block.ID: Paragraph], parentsWithUnloadedChildren: Set<Block.ID>, rootID: Block.ID?) {
		self.rootID = rootID
		self.paragraphsById = paragraphsById
		self.childrenByParentId = childrenByParentId
		self.parentsWithUnloadedChildren = parentsWithUnloadedChildren
	}

	func subset(only blocks: Set<Block.ID>) -> BlockTree {
		var indexed: [Block.ID: Paragraph] = [:]
		var result: [Block.ID: [Paragraph]] = [:]

		for blockId in blocks {
			copySubtree(of: blockId, into: &result, indexedBy: &indexed)
		}

		return BlockTree(
			childrenByParentId: result,
			paragraphsById: indexed,
			parentsWithUnloadedChildren: parentsWithUnloadedChildren.intersection(blocks.union(indexed.keys)),
			rootID: rootID
		)
	}

	func children(of parentId: Block.ID) -> [Paragraph] {
		childrenByParentId[parentId] ?? []
	}

	func hasChildren(_ parentId: Block.ID) -> Bool {
		childrenByParentId[parentId]?.isEmpty == false || parentsWithUnloadedChildren.contains(parentId)
	}

	func previousSibling(for paragraph: Paragraph) -> Paragraph? {
		let siblings = children(of: paragraph.parentId)
		guard let index = siblings.firstIndex(where: { $0.id == paragraph.id }), index > 0 else { return nil }
		return siblings[index - 1]
	}

	func previousBlockOnScreen(for paragraph: Paragraph) -> Block.ID? {
		guard paragraph.id != rootID else { return nil }

		if let previousSibling = previousSibling(for: paragraph) {
			return deepestLastChild(of: previousSibling.id) ?? previousSibling.id
		}

		guard paragraph.parentId != paragraph.pageId else { return nil }
		return paragraph.parentId
	}

	func get(byID id: Block.ID) -> Paragraph? {
		paragraphsById[id]
	}

	func nextBlockOnScreen(for paragraph: Paragraph) -> Block.ID? {
		if let firstChild = children(of: paragraph.id).first {
			return firstChild.id
		}

		return nextSiblingOrAncestorSibling(for: paragraph)
	}

	func descendantIDs(of parentId: Block.ID) -> Set<Block.ID> {
		var result = Set<Block.ID>()
		collectDescendantIDs(of: parentId, into: &result)
		return result
	}

	private func collectDescendantIDs(of parentId: Block.ID, into result: inout Set<Block.ID>) {
		guard let children = childrenByParentId[parentId] else { return }

		for child in children {
			result.insert(child.id)
			collectDescendantIDs(of: child.id, into: &result)
		}
	}

	private func copySubtree(
		of parentId: Block.ID,
		into result: inout [Block.ID: [Paragraph]],
		indexedBy indexed: inout [Block.ID: Paragraph]
	) {
		guard let children = childrenByParentId[parentId] else { return }

		result[parentId] = children
		for child in children {
			indexed[child.id] = child
			copySubtree(of: child.id, into: &result, indexedBy: &indexed)
		}
	}

	private func deepestLastChild(of parentId: Block.ID) -> Block.ID? {
		guard let lastChild = children(of: parentId).last else { return nil }
		return deepestLastChild(of: lastChild.id) ?? lastChild.id
	}

	private func nextSiblingOrAncestorSibling(for paragraph: Paragraph) -> Block.ID? {
		let siblings = children(of: paragraph.parentId)
		if let index = siblings.firstIndex(where: { $0.id == paragraph.id }), index + 1 < siblings.count {
			return siblings[index + 1].id
		}

		guard paragraph.parentId != paragraph.pageId else { return nil }

		if let parentParagraph = get(byID: paragraph.parentId) {
			return nextSiblingOrAncestorSibling(for: parentParagraph)
		}

		return nil
	}
}

extension EnvironmentValues {
	@Entry var blockTree: BlockTree = .init(paragraphs: [])
}
