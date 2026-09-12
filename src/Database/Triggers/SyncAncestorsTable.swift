import Foundation
import SQLiteData

struct SyncAncestorsTable: Trigger {
	static var uses: [any ScalarDatabaseFunction] { [Self().$rebuildAncestorsForSubtree] }

	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert { block in
			Select(Self().$rebuildAncestorsForSubtree(blockId: block.id))
		})
		.execute(db)

		try Block.createTemporaryTrigger(after: .update {
			($0.string, $0.title, $0.dailyNoteDate, $0.parentId, $0.order, $0.heading,
			 $0.viewType, $0.textAlign, $0.isOpen, $0.props, $0.deletedAt, $0.mergedInto)
		} forEachRow: { old, new in
			Select(Self().$rebuildAncestorsForSubtree(blockId: new.id)).where {
				old.parentId.isNot(new.parentId) || old.deletedAt.isNot(new.deletedAt) || old.mergedInto.isNot(new.mergedInto)
			}

			Block.where {
				!SyncEngine.$isSynchronizing && (
					$0.id.eq(new.id) || $0.id.asOptional.in(BlockHierarchy.find(new.id).select(\.pageId))
				)
			}
			.update { $0.updatedAt = $now() }
		})
		.execute(db)

		try Block.createTemporaryTrigger(after: .delete { block in
			Select(Self().$rebuildAncestorsForSubtree(blockId: block.id))
		})
		.execute(db)
	}

	@DatabaseFunction
	func rebuildAncestorsForSubtree(blockId: Block.ID) throws {
		@Dependency(\.defaultDatabase) var database
		try database.unsafeReentrantWrite { try Self.rebuildHierarchy(rootedAt: blockId, in: $0) }
	}
}

fileprivate extension SyncAncestorsTable {
	@Selection struct AffectedBlock {
		let id: Block.ID
	}

	@Selection struct HierarchyAncestry {
		let blockId: Block.ID
		let ancestorId: Block.ID
		let depth: Int
		let path: String
	}

	@Selection struct HierarchyChain {
		let blockId: Block.ID
		let pageId: Page.ID?
		let nextId: Block.ID?
		let isDeleted: Bool
	}

	static func rebuildHierarchy(rootedAt root: Block.ID, in db: Database) throws {
		// The root block and all its descendants (including pages merged into it)
		let affectedBlocks = AffectedBlock(id: root).union(
			Block
				.join(AffectedBlock.all) { blocks, affectedBlocks in
					blocks.parentId.eq(affectedBlocks.id) || blocks.mergedInto.eq(affectedBlocks.id)
				}
				.select { blocks, _ in AffectedBlock.Columns(id: blocks.id) }
		)

		// Delete all existing `ancestor` and `blockHierarchy` records for the affected blocks
		try With { affectedBlocks } query: { Ancestor.where { $0.blockId.in(AffectedBlock.select(\.id)) }.delete() }.execute(db)
		try With { affectedBlocks } query: { BlockHierarchy.where { $0.blockId.in(AffectedBlock.select(\.id)) }.delete() }.execute(db)

		// One row for each (affectedBlock, ancestor) pair with the distance (depth) between them
		// e.g. for Page->P1->P2->P3 where root is P2: (P2, P1, 1), (P2, Page, 2), (P3, P2, 1), (P3, P1, 2), (P3, Page, 3)
		let ancestry = Block
			.where { $0.title.is(nil) && $0.parentId.isNot(nil) && $0.parentId.neq($0.id) }
			.join(AffectedBlock.all) { blocks, affectedBlocks in blocks.id.eq(affectedBlocks.id) }
			.select { blocks, _ in
				HierarchyAncestry.Columns(
					blockId: blocks.id,
					ancestorId: blocks.parentId.unsafelyUnwrapped,
					depth: 1,
					path: "," + blocks.id.cast(as: String.self) + "," + blocks.parentId.unsafelyUnwrapped.cast(as: String.self) + ","
				)
			}
			.union(
				all: true,
				HierarchyAncestry
					.join(Block.all) { ancestors, blocks in blocks.id.eq(ancestors.ancestorId) }
					.where { ancestors, blocks in
						blocks.title.is(nil) && blocks.parentId.isNot(nil) && ancestors.path.instr("," + blocks.parentId.unsafelyUnwrapped.cast(as: String.self) + ",").eq(0)
					}
					.select { ancestors, blocks in
						HierarchyAncestry.Columns(
							blockId: ancestors.blockId,
							ancestorId: blocks.parentId.unsafelyUnwrapped,
							depth: ancestors.depth + 1,
							path: ancestors.path + blocks.parentId.unsafelyUnwrapped.cast(as: String.self) + ","
						)
					}
			)

		// Persist the ancestry records calculated above to the `ancestor` table (skipping the `path` column)
		try With {
			affectedBlocks
			ancestry
		} query: {
			Ancestor.insert { ($0.blockId, $0.ancestorId, $0.depth) } select: {
				HierarchyAncestry.select { ($0.blockId, $0.ancestorId, $0.depth) }
			}
		}.execute(db)

		// Build a chain that goes from each affected block to its root page following parentId and mergedInto links.
		// The chain is marked as deleted if any block in the chain is deleted.
		let chain = Block
			.join(AffectedBlock.all) { blocks, affectedBlocks in blocks.id.eq(affectedBlocks.id) }
			.select { blocks, _ in
				HierarchyChain.Columns(
					blockId: blocks.id,
					pageId: Case<Bool, Block.ID>().when(blocks.isPage, then: blocks.id),
					nextId: Case<Bool, Block.ID>()
						.when(blocks.isPage, then: blocks.mergedInto)
						.when(true, then: blocks.parentId),
					isDeleted: blocks.deletedAt.isNot(nil)
				)
			}
			.union(
				HierarchyChain
					.join(Block.all) { chains, blocks in chains.nextId.eq(blocks.id) }
					.select { chains, blocks in
						HierarchyChain.Columns(
							blockId: chains.blockId,
							pageId: Case<Bool, Block.ID>().when(blocks.isPage, then: blocks.id),
							nextId: Case<Bool, Block.ID>()
								.when(blocks.isPage, then: blocks.mergedInto)
								.when(true, then: blocks.parentId),
							isDeleted: chains.isDeleted || blocks.deletedAt.isNot(nil)
						)
					}
			)

		// Create a `blockHierarchy` record for each affected block that points to its root page (if any) and whether the chain is deleted.
		// Blocks whose chains cannot resolve to a page (e.g. when mid-sync) remain hidden.
		try With {
			affectedBlocks
			chain
		} query: {
			BlockHierarchy.insert { ($0.blockId, $0.pageId, $0.isVisible) } select: {
				Block
					.join(AffectedBlock.all) { blocks, affectedBlocks in blocks.id.eq(affectedBlocks.id) }
					.leftJoin(HierarchyChain.all) { blocks, _, chains in
						chains.blockId.eq(blocks.id) && chains.nextId.is(nil) && chains.pageId.isNot(nil)
					}
					.select { blocks, _, chains in
						(blocks.id, chains.pageId.unsafelyUnwrapped, chains.pageId.isNot(nil) && chains.isDeleted.is(false) && blocks.mergedInto.is(nil))
					}
			}
		}.execute(db)
	}
}
