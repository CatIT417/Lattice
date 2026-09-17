import SQLiteData

final class SyncBlocksFTSTable: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert { block in
			BlockSearchID.insert { $0.blockID } select: { Select(block.id) }
			BlockText.insert {
				($0.rowid, $0.blockID, $0.canonicalTitle, $0.string, $0.displayTitle, $0.displayString)
			} select: {
				BlockSearchID.where { $0.blockID.eq(block.id) }.select {
					($0.id, block.id, block.title, block.string, $searchDisplayTitle(block.title), $searchDisplayString(block.string))
				}
			}
		})
		.execute(db)

		try Block.createTemporaryTrigger(after: .update {
			($0.title, $0.string, $0.dailyNoteDate)
		} forEachRow: { _, block in
			BlockText.where { $0.rowid.in(BlockSearchID.where { $0.blockID.eq(block.id) }.select(\.id)) }.update {
				$0.string = block.string
				$0.canonicalTitle = block.title
				$0.displayTitle = $searchDisplayTitle(block.title)
				$0.displayString = $searchDisplayString(block.string)
			}
		})
		.execute(db)

		try Block.createTemporaryTrigger(after: .delete { block in
			BlockText.where { $0.rowid.in(BlockSearchID.where { $0.blockID.eq(block.id) }.select(\.id)) }.delete()
			BlockSearchID.where { $0.blockID.eq(block.id) }.delete()
		})
		.execute(db)
	}
}
