import SQLiteData

struct SafetyTriggers: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(before: .update(of: \.pageId, forEachRow: { _, _ in
			Values(#sql("RAISE(ABORT, 'You forgot to update the `parentId` field to the new page!')"))
		}, when: { old, new in
			old.pageId != new.pageId && old.pageId == old.parentId && new.pageId != new.parentId
		})).execute(db)

		try Block.createTemporaryTrigger(before: .update(of: \.parentId, forEachRow: { _, _ in
			Values(#sql("RAISE(ABORT, 'You forgot to update the `pageId` field to the new page!')"))
		}, when: { old, new in
			old.parentId != new.parentId && old.pageId == old.parentId && new.pageId != new.parentId
		})).execute(db)
	}
}
