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
		childrenByParentId[parentId] ?? []
	}
}

extension EnvironmentValues {
	@Entry var blockTree: BlockTree?
}
