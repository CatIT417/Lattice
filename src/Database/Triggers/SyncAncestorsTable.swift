import SQLiteData
import Foundation

final class SyncAncestorsTable: Trigger {
	/// Registers the SQLite function used by the trigger.
	static var uses: [any ScalarDatabaseFunction] {
		[$rebuildAncestorsForSubtree]
	}

	/// Installs triggers that keep the ancestors table in sync with blocks.
	static func install(in database: Database) throws {
		// When inserting a new block
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { block in
			Self.insertParent(for: block)
			Self.propagateParentAncestors(for: block)
		}, when: {
			$0.parentId.isNot(nil)
		})).execute(database)

		// When moving a block (parent changes)
		try Block.createTemporaryTrigger(after: .update(of: \.parentId, forEachRow: { _, new in
			Values($rebuildAncestorsForSubtree(blockId: new.id))
		}, when: { $0.parentId.neq($1.parentId) })).execute(database)
	}

	/// Inserts the parent as the direct ancestor for a new block.
	private static func insertParent<AliasName>(for block: TableAlias<Block, AliasName>.TableColumns) -> InsertOf<Ancestor> {
		Ancestor.insert {
			Ancestor.Columns(
				blockId: block.id,
				ancestorId: block.parentId.unsafelyUnwrapped,
				depth: 1
			)
		}
	}

	/// Copy all ancestors of the parent, incrementing depth.
	private static func propagateParentAncestors<AliasName>(for block: TableAlias<Block, AliasName>.TableColumns) -> SQLQueryExpression<Any> {
		#sql("""
			INSERT INTO \(Ancestor.self) ("blockId", "ancestorId", "depth")
			SELECT \(block.id), \(Ancestor.ancestorId), \(Ancestor.depth) + 1
			FROM \(Ancestor.self)
			WHERE \(Ancestor.blockId) = \(block.parentId)
		""")
	}
}

/// Rebuilds all ancestor rows for a moved block and its descendants.
@DatabaseFunction
func rebuildAncestorsForSubtree(blockId: Block.ID) throws {
	@Dependency(\.defaultDatabase) var database

	withErrorReporting {
		try database.unsafeReentrantWrite { db in
			// Clear all ancestor rows for the moved subtree; we rebuild from blocks to avoid stale/partial ancestry.
			try #sql("""
				WITH RECURSIVE descendants("blockId") AS (
					SELECT \(bind: blockId)
					UNION ALL
					SELECT \(Block.id)
					FROM \(Block.self)
					JOIN descendants ON \(Block.parentId) = descendants."blockId"
				)
				DELETE FROM \(Ancestor.self)
				WHERE \(Ancestor.blockId) IN (SELECT "blockId" FROM descendants);
			""").execute(db)

			// Recompute ancestors by walking parentId chains; recursive CTE keeps depths consistent for every descendant.
			try #sql("""
				WITH RECURSIVE
					descendants("blockId") AS (
						SELECT \(bind: blockId)
						UNION ALL
						SELECT \(Block.id)
						FROM \(Block.self)
						JOIN descendants ON \(Block.parentId) = descendants."blockId"
					),
					ancestors("blockId", "ancestorId", "depth") AS (
						SELECT descendants."blockId", \(Block.parentId), 1
						FROM descendants
						JOIN \(Block.self) ON \(Block.id) = descendants."blockId"
						WHERE \(Block.parentId) IS NOT NULL
						UNION ALL
						SELECT ancestors."blockId", \(Block.parentId), ancestors."depth" + 1
						FROM ancestors
						JOIN \(Block.self) ON \(Block.id) = ancestors."ancestorId"
						WHERE \(Block.parentId) IS NOT NULL
					)
				INSERT INTO \(Ancestor.self) ("blockId", "ancestorId", "depth")
				SELECT "blockId", "ancestorId", "depth" FROM ancestors;
			""").execute(db)
		}
	}
}
