import SQLiteData

final class SyncBlocksFTSTable: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert { block in
			BlockText.insert {
				BlockText.Columns(blockID: block.id, title: block.title, string: block.string)
			}
		}).execute(db)

		try Block.createTemporaryTrigger(after: .update {
			($0.title, $0.string)
		} forEachRow: { _, block in
			BlockText.where { $0.blockID.eq(block.id) }.update {
				$0.title = block.title
				$0.string = block.string
			}
		}).execute(db)

		try Block.createTemporaryTrigger(after: .delete { block in
			BlockText.where { $0.blockID.eq(block.id) }.delete()
		}).execute(db)
	}
}
