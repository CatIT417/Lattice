import SQLiteData
import Foundation

final class MakeParagraphsViewWritable: Trigger {
	static func install(in database: Database) throws {
		try Paragraph.createTemporaryTrigger(insteadOf: .insert(forEachRow: { paragraph in
			Block.insert {
				Block.Columns(
					id: paragraph.id,
					string: paragraph.string.asOptional,
					parentId: paragraph.parentId.asOptional,
					pageId: paragraph.pageId.asOptional,
					order: paragraph.order,
					heading: paragraph.heading,
					viewType: paragraph.viewType,
					textAlign: paragraph.textAlign,
					isOpen: paragraph.isOpen,
					props: paragraph.props,
					createdAt: paragraph.createdAt,
					updatedAt: paragraph.updatedAt
				)
			}
		})).execute(database)

		// We intentionally do not support updates to paragraphs via the view.
		// Updates should be done on the Block table directly.

		try Paragraph.createTemporaryTrigger(insteadOf: .delete(forEachRow: { paragraph in
			Block.find(paragraph.id).delete()
		})).execute(database)
	}
}
