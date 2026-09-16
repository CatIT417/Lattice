import SQLiteData

final class SyncBlocksFTSTable: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert { block in
			BlockText.insert {
				BlockText.Columns(
					blockID: block.id,
					canonicalTitle: block.title,
					string: block.string,
					displayTitle: $searchDisplayTitle(block.title),
					displayString: $searchDisplayString(block.string)
				)
			}
		})
		.execute(db)

		try Block.createTemporaryTrigger(after: .update {
			($0.title, $0.string, $0.dailyNoteDate)
		} forEachRow: { _, block in
			BlockText.where { $0.blockID.eq(block.id) }.update {
				$0.string = block.string
				$0.canonicalTitle = block.title
				$0.displayTitle = $searchDisplayTitle(block.title)
				$0.displayString = $searchDisplayString(block.string)
			}
		})
		.execute(db)

		try Block.createTemporaryTrigger(after: .delete { block in
			BlockText.where { $0.blockID.eq(block.id) }.delete()
		})
		.execute(db)
	}
}
