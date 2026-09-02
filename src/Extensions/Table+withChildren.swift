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
		guard let block = try Model.find(id).fetchOne(db) else { return nil }

		let paragraphs = try Ancestor
			.where { $0.ancestorId.eq(id) }
			.join(Paragraph.all) { $0.blockId.eq($1.id) }
			.select { _, paragraphs in paragraphs }
			.fetchAll(db)

		return Model.WithChildren(block: block, tree: BlockTree(paragraphs: paragraphs))
	}
}
