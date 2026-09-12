import Foundation
import SQLiteData

final class CreateParagraphsView: DatabaseView {
	private enum Parent: AliasName {}
	private enum ParentHierarchy: AliasName {}
	static func create(in db: Database) throws {
		try Paragraph.createTemporaryView(
			as: Block.where(\.isParagraph)
				.join(BlockHierarchy.all) { $0.id.eq($1.blockId) }
				.where { _, hierarchy in hierarchy.isVisible }
				.select { blocks, hierarchy in
					Paragraph.Columns(
						id: blocks.id,
						string: blocks.string.unsafelyUnwrapped,
						parentId: Block.as(Parent.self)
							.where { blocks.parentId.eq($0.id) && $0.title.isNot(nil) }
							.join(BlockHierarchy.as(ParentHierarchy.self).all) { $0.id.eq($1.blockId) }
							.select { _, parentHierarchies in parentHierarchies.pageId }
							?? blocks.parentId.unsafelyUnwrapped,
						pageId: hierarchy.pageId.unsafelyUnwrapped,
						order: blocks.order,
						heading: blocks.heading,
						viewType: blocks.viewType,
						textAlign: blocks.textAlign,
						isOpen: blocks.isOpen,
						props: blocks.props,
						createdAt: blocks.createdAt,
						updatedAt: blocks.updatedAt
					)
				}
		)
		.execute(db)
	}
}
