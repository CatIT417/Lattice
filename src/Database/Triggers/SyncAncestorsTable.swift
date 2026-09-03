import Foundation
import SQLiteData

final class SyncAncestorsTable: Trigger {
	/// Registers the SQLite function used by the trigger.
	static var uses: [any ScalarDatabaseFunction] {
		[$rebuildAncestorsForSubtree]
	}

	/// Installs triggers that keep the ancestors table in sync with blocks.
	static func install(in database: Database) throws {
		// When inserting a new block. If the parent has not arrived yet, only the depth-1 row is written.
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { block in
			Self.insertParent(for: block)
			Self.propagateParentAncestors(for: block)
		}, when: { block in
			block.parentId.isNot(nil) && !Self.hasChildren(block)
		}))
		.execute(database)

		try Block.createTemporaryTrigger(after: .insert(forEachRow: { block in
			Select($rebuildAncestorsForSubtree(blockId: block.id))
		}, when: { block in
			Self.hasChildren(block)
		}))
		.execute(database)

		// When moving a block (parent changes)
		try Block.createTemporaryTrigger(after: .update(of: \.parentId, forEachRow: { _, new in
			Select($rebuildAncestorsForSubtree(blockId: new.id))
		}, when: { $0.parentId.neq($1.parentId) }))
			.execute(database)
	}

	private static func hasChildren<AliasName>(_ block: TableAlias<Block, AliasName>.TableColumns) -> some QueryExpression<Bool> {
		Paragraph.where { $0.parentId.eq(block.id) }.exists()
	}

	/// Inserts the parent as the direct ancestor for a new block.
	private static func insertParent<AliasName>(for block: TableAlias<Block, AliasName>.TableColumns) -> InsertOf<Ancestor> {
		Ancestor.insert(or: .ignore) {
			Ancestor.Columns(
				blockId: block.id,
				ancestorId: block.parentId.unsafelyUnwrapped,
				depth: 1
			)
		}
	}

	/// Copy all ancestors of the parent, incrementing depth.
	private static func propagateParentAncestors<AliasName>(for block: TableAlias<Block, AliasName>.TableColumns) -> InsertOf<Ancestor> {
		Ancestor.insert(or: .ignore) {
			($0.blockId, $0.ancestorId, $0.depth)
		} select: {
			Ancestor
				.where { $0.blockId.eq(block.parentId.unsafelyUnwrapped) }
				.select { (block.id, $0.ancestorId, $0.depth + 1) }
		}
	}
}

/// Rebuilds all ancestor rows for a block and its descendants.
@DatabaseFunction
func rebuildAncestorsForSubtree(blockId: Block.ID) {
	@Dependency(\.defaultDatabase) var database

	let descendants: QueryFragment = """
		descendants("blockId") AS (
			SELECT \(bind: blockId)
			UNION
			SELECT \(Block.id)
			FROM \(Block.self)
			JOIN descendants ON \(Block.parentId) = descendants."blockId"
		)
	"""

	withErrorReporting {
		try database.unsafeReentrantWrite { db in
			// Clear all ancestor rows for the subtree; we rebuild from blocks to avoid stale/partial ancestry.
			try #sql("""
				WITH RECURSIVE \(descendants)
				DELETE FROM \(Ancestor.self)
				WHERE \(Ancestor.blockId) IN (SELECT "blockId" FROM descendants);
			""").execute(db)

			// Recompute ancestors by walking parentId chains; recursive CTE keeps depths consistent for every descendant.
			// `path` is the comma-delimited chain walked so far (ids never contain commas).
			try #sql("""
				WITH RECURSIVE
					\(descendants),
					ancestors("blockId", "ancestorId", "depth", "path") AS (
						SELECT descendants."blockId", \(Block.parentId), 1, ',' || descendants."blockId" || ',' || \(Block.parentId) || ','
						FROM descendants
						JOIN \(Block.self) ON \(Block.id) = descendants."blockId"
						WHERE \(Block.parentId) IS NOT NULL
						UNION ALL
						SELECT ancestors."blockId", \(Block.parentId), ancestors."depth" + 1, ancestors."path" || \(Block.parentId) || ','
						FROM ancestors
						JOIN \(Block.self) ON \(Block.id) = ancestors."ancestorId"
						WHERE \(Block.parentId) IS NOT NULL AND instr(ancestors."path", ',' || \(Block.parentId) || ',') = 0
					)
				INSERT OR IGNORE INTO \(Ancestor.self) ("blockId", "ancestorId", "depth")
				SELECT "blockId", "ancestorId", "depth" FROM ancestors;
			""").execute(db)
		}
	}
}
