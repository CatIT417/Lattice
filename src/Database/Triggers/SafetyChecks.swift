import SQLiteData

struct SafetyChecks: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(before: .update(of: \.pageId, forEachRow: { _, _ in
			Select(#sql("RAISE(ABORT, 'You forgot to update the `parentId` field to the new page!')"))
		}, when: { old, new in
			old.pageId.neq(new.pageId) && old.pageId.eq(old.parentId) && new.pageId.neq(new.parentId)
		}))
		.execute(db)

		try Block.createTemporaryTrigger(before: .update(of: \.parentId, forEachRow: { _, _ in
			Select(#sql("RAISE(ABORT, 'You forgot to update the `pageId` field to the new page!')"))
		}, when: { old, new in
			old.parentId.neq(new.parentId) && old.parentId.eq(old.pageId) && new.parentId.neq(new.pageId) && Page.where { new.parentId.eq($0.id) }.exists()
		}))
		.execute(db)
	}
}
