import SQLiteData
import Foundation

final class CreateParagraphsView: DatabaseView {
	static func create(in db: Database) throws {
		try Paragraph.createTemporaryView(
			as: Block.where { $0.string.isNot(nil) }.select {
				Paragraph.Columns(
					id: $0.id,
					string: $0.string.unsafelyUnwrapped,
					parentId: $0.parentId.unsafelyUnwrapped,
					pageId: $0.pageId.unsafelyUnwrapped,
					order: $0.order,
					viewType: $0.viewType,
					textAlign: $0.textAlign,
					isOpen: $0.isOpen,
					createdAt: $0.createdAt,
					updatedAt: $0.createdAt
				)
			}
		).execute(db)
	}
}
