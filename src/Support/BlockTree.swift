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

	func previousBlock(for paragraph: Paragraph) -> Block.ID? {
		if let previousSibling = children(of: paragraph.parentId).filter({ $0.order < paragraph.order }).last {
			return previousSibling.id
		}

		if hasChildren(paragraph.id) { return nil }
		guard paragraph.parentId != paragraph.pageId else { return nil }

		return paragraph.parentId
	}
}

extension EnvironmentValues {
	@Entry var blockTree: BlockTree = .init(paragraphs: [])
}
