import SwiftUI

struct BlockTree {
	private let paragraphsById: [Block.ID: Paragraph]
	private let childrenByParentId: [Block.ID: [Paragraph]]

	init(paragraphs: [Paragraph]) {
		var indexed: [Block.ID: Paragraph] = [:]
		var grouped: [Block.ID: [Paragraph]] = [:]

		for p in paragraphs {
			indexed[p.id] = p
			grouped[p.parentId, default: []].append(p)
		}

		paragraphsById = indexed
		childrenByParentId = grouped.mapValues { $0.sorted(using: KeyPathComparator(\.order, order: .forward)) }
	}

	private init(childrenByParentId: [Block.ID: [Paragraph]], paragraphsById: [Block.ID: Paragraph]) {
		self.paragraphsById = paragraphsById
		self.childrenByParentId = childrenByParentId
	}

	func subset(only blocks: Set<Block.ID>) -> BlockTree {
		var indexed: [Block.ID: Paragraph] = [:]
		var result: [Block.ID: [Paragraph]] = [:]

		for blockId in blocks {
			copySubtree(of: blockId, into: &result, indexedBy: &indexed)
		}

		return BlockTree(childrenByParentId: result, paragraphsById: indexed)
	}

	func children(of parentId: Block.ID) -> [Paragraph] {
		childrenByParentId[parentId] ?? []
	}

	func hasChildren(_ parentId: Block.ID) -> Bool {
		childrenByParentId[parentId]?.isEmpty == false
	}

	func previousSibling(for paragraph: Paragraph) -> Paragraph? {
		children(of: paragraph.parentId).filter { $0.order < paragraph.order }.last
	}

	func previousBlockOnScreen(for paragraph: Paragraph) -> Block.ID? {
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
		if let nextSibling = children(of: paragraph.parentId).first(where: { $0.order > paragraph.order }) {
			return nextSibling.id
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
