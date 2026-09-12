import SQLiteData

struct SafetyChecks: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(before: .update(of: \.parentId, forEachRow: { _, _ in
			Select(#sql("RAISE(ABORT, 'A block cannot move under itself or a descendant.')"))
		}, when: { old, new in
			!SyncEngine.$isSynchronizing && old.parentId.isNot(new.parentId)
				&& (new.parentId.eq(new.id.asOptional)
					|| new.parentId.unsafelyUnwrapped.in(Ancestor.where { $0.ancestorId.eq(new.id) }.select(\.blockId)))
		}))
		.execute(db)

		try Block.createTemporaryTrigger(before: .insert(forEachRow: { _ in
			Select(#sql("RAISE(ABORT, 'A block cannot be its own parent.')"))
		}, when: { new in
			!SyncEngine.$isSynchronizing && new.parentId.eq(new.id.asOptional)
		}))
		.execute(db)
	}
}
