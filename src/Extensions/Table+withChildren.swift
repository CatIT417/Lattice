import SQLiteData
import Foundation

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
}

struct WithChildrenRequest<Model: HasChildren>: FetchKeyRequest {
	let id: Model.PrimaryKey

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
}
