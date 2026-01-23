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

	func previousBlockOnScreen(for paragraph: Paragraph) -> Block.ID? {
		if let previousSibling = children(of: paragraph.parentId).filter({ $0.order < paragraph.order }).last {
			return deepestLastChild(of: previousSibling.id) ?? previousSibling.id
		}

		guard paragraph.parentId != paragraph.pageId else { return nil }
		return paragraph.parentId
	}

	private func deepestLastChild(of parentId: Block.ID) -> Block.ID? {
		guard let lastChild = children(of: parentId).last else { return nil }
		return deepestLastChild(of: lastChild.id) ?? lastChild.id
	}
}

extension EnvironmentValues {
	@Entry var blockTree: BlockTree = .init(paragraphs: [])
}
