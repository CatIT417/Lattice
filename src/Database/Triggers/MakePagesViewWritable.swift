import Foundation
import SQLiteData

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
		}))
		.execute(database)

		// We intentionally do not support updates to pages via the view.
		// Updates should be done on the Block table directly.

		// Deleting a page takes its whole subtree, simulating a "delete cascade".
		try Page.createTemporaryTrigger(insteadOf: .delete(forEachRow: { page in
			Block.where { $0.isInSubtree(rootedAt: page.id) || $0.pageId.eq(page.id.asOptional) }.delete()
		}))
		.execute(database)
	}
}
