import SQLiteData
import Foundation

final class CreateParagraphsView: DatabaseView {
	static func create(in db: Database) throws {
		try Paragraph.createTemporaryView(
			as: Block.where { $0.isParagraph }.select {
				Paragraph.Columns(
					id: $0.id,
					string: $0.string.unsafelyUnwrapped,
					parentId: $0.parentId.unsafelyUnwrapped,
					pageId: $0.pageId.unsafelyUnwrapped,
					order: $0.order,
					heading: $0.heading,
					viewType: $0.viewType,
					textAlign: $0.textAlign,
					isOpen: $0.isOpen,
					props: $0.props,
					createdAt: $0.createdAt,
					updatedAt: $0.updatedAt
				)
			}
		).execute(db)
	}
}
