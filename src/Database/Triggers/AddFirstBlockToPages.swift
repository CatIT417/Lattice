import SQLiteData

final class AddFirstBlockToPages: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { page in
			Paragraph.insert {
				Paragraph.Columns(string: "", parentId: page.id, pageId: page.id)
			}
		}, when: { block in
			block.title.isNot(nil) && Paragraph.where { $0.pageId == block.id }.count() == 0
		})).execute(db)
	}
}
