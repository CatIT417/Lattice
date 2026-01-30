import SQLiteData
import Foundation

final class MakePagesViewWritable: Trigger {
	static func install(in database: Database) throws {
		try Page.createTemporaryTrigger(insteadOf: .insert(forEachRow: { page in
			Block.insert {
				Block.Columns(
					id: page.id,
					title: page.title.asOptional,
					dailyNoteDate: page.dailyNoteDate,
					props: page.props,
					createdAt: page.createdAt,
					updatedAt: page.updatedAt
				)
			}
		})).execute(database)

		// We intentionally do not support updates to pages via the view.
		// Updates should be done on the Block table directly.

		try Page.createTemporaryTrigger(insteadOf: .delete(forEachRow: { page in
			Block.find(page.id).delete()
		})).execute(database)
	}
}
