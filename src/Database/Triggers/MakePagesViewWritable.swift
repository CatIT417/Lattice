import SQLiteData
import Foundation

final class MakePagesViewWritable: Trigger {
	static func install(in database: Database) throws {
		try Page.createTemporaryTrigger(insteadOf: .insert(forEachRow: { page in
			Block.insert {
				Block.Columns(
					id: page.id,
					title: #sql("\(page.title)"),
					dailyNoteDate: page.dailyNoteDate,
					props: page.props,
					createdAt: page.createdAt,
					updatedAt: page.updatedAt
				)
			}
		})).execute(database)

		try Page.createTemporaryTrigger(insteadOf: .update(forEachRow: { old, new in
			Block.find(old.id).update { block in
				block.id = new.id
				block.title = #sql("\(new.title)")
				block.props = new.props
				block.updatedAt = new.updatedAt
				block.dailyNoteDate = new.dailyNoteDate
			}
		})).execute(database)

		try Page.createTemporaryTrigger(insteadOf: .delete(forEachRow: { page in
			Block.find(page.id).delete()
		})).execute(database)
	}
}
