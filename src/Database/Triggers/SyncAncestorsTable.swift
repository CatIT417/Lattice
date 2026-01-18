import SQLiteData
import Foundation

final class SyncAncestorsTable: Trigger {
	static func install(in database: Database) throws {
		// When inserting a new block
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { new in
			Self.insertParent(blockId: new.id, parentId: new.parentId.unsafelyUnwrapped)
			Self.propagateParentAncestors(blockId: new.id, parentId: new.parentId)
		}, when: {
			$0.parentId.isNot(nil)
		})).execute(database)

		// When moving a block (parent changes)
		try Block.createTemporaryTrigger(after: .update(of: \.parentId, forEachRow: { old, new in
			// Delete old ancestry
			Ancestor.where { $0.blockId == old.id }.delete()

			// Rebuild (same as insert logic)
			Self.insertParent(blockId: new.id, parentId: new.parentId.unsafelyUnwrapped)
			Self.propagateParentAncestors(blockId: new.id, parentId: new.parentId)
		}, when: { $0.parentId != $1.parentId })).execute(database)
	}

	private static func insertParent<T1: QueryExpression<Block.ID>, T2: QueryExpression<Block.ID>>(blockId: T1, parentId: T2) -> InsertOf<Ancestor> {
		Ancestor.insert {
			Ancestor.Columns(
				blockId: blockId,
				ancestorId: parentId,
				depth: 1
			)
		}
	}

	/// Copy all ancestors of parent, incrementing depth
	private static func propagateParentAncestors<T1: TableColumnExpression, T2: TableColumnExpression>(blockId: T1, parentId: T2) -> SQLQueryExpression<Any> {
		#sql("""
			INSERT INTO \(Ancestor.self) ("blockId", "ancestorId", "depth")
			SELECT \(blockId), \(Ancestor.ancestorId), \(Ancestor.depth) + 1
			FROM \(Ancestor.self)
			WHERE \(Ancestor.blockId) = \(parentId)
		""")
	}
}
