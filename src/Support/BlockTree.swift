import SwiftUI

struct BlockTree {
	private let childrenByParentId: [Block.ID: [Paragraph]]

	init(paragraphs: [Paragraph]) {
		var grouped: [Block.ID: [Paragraph]] = [:]
		for p in paragraphs {
			grouped[p.parentId, default: []].append(p)
		}
		childrenByParentId = grouped
	}

	func children(of parentId: Block.ID) -> [Paragraph] {
		childrenByParentId[parentId]?.sorted(using: KeyPathComparator(\.order, order: .forward)) ?? []
	}

	func isRoot(_ id: Block.ID) -> Bool {
		!childrenByParentId.values.contains { $0.contains { $0.id == id } }
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

	func nextBlockOnScreen(for paragraph: Paragraph) -> Block.ID? {
		if let firstChild = children(of: paragraph.id).first {
			return firstChild.id
		}

		return nextSiblingOrAncestorSibling(for: paragraph)
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

		if let parentParagraph = childrenByParentId.values.lazy.flatMap({ $0 }).first(where: { $0.id == paragraph.parentId }) {
			return nextSiblingOrAncestorSibling(for: parentParagraph)
		}

		return nil
	}
}

extension EnvironmentValues {
	@Entry var blockTree: BlockTree = .init(paragraphs: [])
}
