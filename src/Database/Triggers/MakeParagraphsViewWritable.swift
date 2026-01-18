import SQLiteData
import Foundation

final class MakeParagraphsViewWritable: Trigger {
	static func install(in database: Database) throws {
		try Paragraph.createTemporaryTrigger(insteadOf: .insert(forEachRow: { paragraph in
			Block.insert {
				Block.Columns(
					id: paragraph.id,
					string: #sql("\(paragraph.string)"),
					parentId: #sql("\(paragraph.parentId)"),
					pageId: #sql("\(paragraph.pageId)"),
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

		try Paragraph.createTemporaryTrigger(insteadOf: .update(forEachRow: { old, new in
			Block.find(old.id).update(set: { block in
				block.id = new.id
				block.string = #sql("\(new.string)")
				block.parentId = #sql("\(new.parentId)")
				block.pageId = #sql("\(new.pageId)")
				block.order = new.order
				block.heading = new.heading
				block.viewType = new.viewType
				block.textAlign = new.textAlign
				block.isOpen = new.isOpen
				block.updatedAt = new.updatedAt
			})
		})).execute(database)

		try Paragraph.createTemporaryTrigger(insteadOf: .delete(forEachRow: { paragraph in
			Block.find(paragraph.id).delete()
		})).execute(database)
	}
}
