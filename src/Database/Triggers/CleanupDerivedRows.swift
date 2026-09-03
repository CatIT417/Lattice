import SQLiteData

/// Removes the derived rows of a physically deleted block.
///
/// This replaces the foreign-key cascades `blockAncestors` and `blockReferences` used to have, and runs for local and
/// synced deletes alike.
final class CleanupDerivedRows: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .delete(forEachRow: { block in
			Ancestor.where { $0.blockId.eq(block.id) || $0.ancestorId.eq(block.id) }.delete()
			Reference.where { $0.sourceBlockId.eq(block.id) || $0.targetBlockId.eq(block.id) }.delete()
		}))
		.execute(db)
	}
}
