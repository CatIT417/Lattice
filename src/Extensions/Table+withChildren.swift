import Foundation
import SQLiteData

protocol HasChildren: Table & PrimaryKeyedTable<UUID> where Self.QueryOutput == Self {}

struct _WithChildren<Model: Table> where Model.QueryOutput == Model {
	let block: Model
	let tree: BlockTree
}

extension _WithChildren: Sendable where Model: Sendable {}

extension HasChildren {
	typealias WithChildren = _WithChildren<Self>

	static func withChildren(id: Self.PrimaryKey) -> WithChildrenRequest<Self> {
		WithChildrenRequest(id: id)
	}

	static func withVisibleChildren(id: Self.PrimaryKey) -> WithChildrenRequest<Self> {
		WithChildrenRequest(id: id, includesCollapsed: false)
	}
}

struct WithChildrenRequest<Model: HasChildren>: FetchKeyRequest {
	let id: Model.PrimaryKey
	var includesCollapsed = true

	func fetch(_ db: Database) throws -> Model.WithChildren? {
		let resolvedID: UUID
		if Model.self == Page.self {
			guard let original = try Block.find(id).fetchOne(db), original.title != nil, original.deletedAt == nil,
			      let pageId = try BlockHierarchy.find(id).fetchOne(db)?.pageId else { return nil }
			resolvedID = pageId
		} else {
			resolvedID = id
		}
		guard let block = try Model.find(resolvedID).fetchOne(db) else { return nil }

		if !includesCollapsed {
			let rows = try Self.visibleParagraphs(rootID: resolvedID).fetchAll(db)
			return Model.WithChildren(
				block: block,
				tree: BlockTree(
					paragraphs: rows.map(\.0),
					parentsWithUnloadedChildren: Set(rows.filter(\.1).map { $0.0.id }),
					rootID: resolvedID
				)
			)
		}

		let paragraphs: [Paragraph]
		if Model.self == Page.self {
			paragraphs = try Paragraph.where { $0.pageId.eq(resolvedID) }.fetchAll(db)
		} else {
			paragraphs = try Ancestor
				.where { $0.ancestorId.eq(resolvedID) }
				.join(Paragraph.all) { $0.blockId.eq($1.id) }
				.select { _, paragraphs in paragraphs }
				.fetchAll(db)
		}

		return Model.WithChildren(block: block, tree: BlockTree(paragraphs: paragraphs))
	}

	static func visibleParagraphs(rootID: Block.ID) -> some Statement<(Paragraph, Bool)> {
		let roots = OutlineRoot(id: rootID).union(
			all: true,
			Block.where { $0.isPage && Model.self == Page.self }
				.join(OutlineRoot.all) { $0.mergedInto.eq($1.id) }
				.select { blocks, _ in OutlineRoot.Columns(id: blocks.id) }
		)

		let descendants = Block
			.where { $0.isParagraph && $0.parentId.in(OutlineRoot.select { $0.id.asOptional }) }
			.join(BlockHierarchy.all) { $0.id.eq($1.blockId) }
			.where { _, hierarchy in hierarchy.isVisible }
			.select { blocks, _ in OutlineParagraph.Columns(id: blocks.id, isOpen: blocks.isOpen) }
			.union(
				all: true,
				OutlineParagraph.where(\.isOpen)
					.join(Block.all) { $1.parentId.eq($0.id) }
					.where { _, blocks in blocks.isParagraph }
					.join(BlockHierarchy.all) { _, blocks, hierarchy in blocks.id.eq(hierarchy.blockId) }
					.where { _, _, hierarchy in hierarchy.isVisible }
					.select { _, blocks, _ in OutlineParagraph.Columns(id: blocks.id, isOpen: blocks.isOpen) }
			)

		return With {
			roots
			descendants
		} query: {
			Paragraph.where { $0.id.in(OutlineParagraph.select(\.id)) }
				.select { paragraphs in
					(
						paragraphs,
						Case<Bool, Bool>()
							.when(paragraphs.isOpen, then: false)
							.else(
								Block.where { $0.parentId.eq(paragraphs.id) && $0.isParagraph }
									.join(BlockHierarchy.all) { $0.id.eq($1.blockId) }
									.where { _, hierarchy in hierarchy.isVisible }
									.exists()
							)
					)
				}
		}
	}
}

@Selection private struct OutlineRoot {
	let id: Block.ID
}

@Selection private struct OutlineParagraph {
	let id: Block.ID
	let isOpen: Bool
}
