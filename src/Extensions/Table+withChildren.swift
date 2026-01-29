import SQLiteData
import Foundation

protocol HasChildren: Table & PrimaryKeyedTable<UUID> where Self.QueryOutput == Self {}

struct _WithChildren<Model: Table> where Model.QueryOutput == Model {
	let block: Model
	let tree: BlockTree

	// just to make the decoder happy, holds no actual data
	private let content: [TableAlias<Paragraph, ParagraphAlias>] = []
}

extension HasChildren {
	typealias WithChildren = _WithChildren<Self>

	static func withChildren(id: Self.PrimaryKey) -> Select<WithChildren, Self, (Ancestor?, TableAlias<Paragraph, ParagraphAlias>?)> {
		find(id)
			.group(by: \.primaryKey)
			.leftJoin(Ancestor.all) { $0.primaryKey.eq($1.ancestorId) }
			.leftJoin(Paragraph.as(ParagraphAlias.self).all) { $1.blockId.eq($2.id) }
			.select { block, _, paragraph in
				WithChildren.Columns(block: block, content: paragraph.optionalJSONGroupArray(filter: paragraph.id.isNot(nil)))
			}
			.asSelect()
	}
}

extension _WithChildren: Sendable where Model: Sendable {}

extension _WithChildren {
	init(decoder: inout some QueryDecoder) throws {
		guard let block = try decoder.decode(Model.self) else { throw QueryDecodingError.missingRequiredColumn }
		guard let content = try decoder.decode([Paragraph].JSONRepresentation.self) else { throw QueryDecodingError.missingRequiredColumn }

		self.block = block
		tree = BlockTree(paragraphs: content)
	}
}

extension _WithChildren: Table, _Selection, PartialSelectStatement {
	typealias From = Never
	typealias QueryValue = Self

	static var columns: TableColumns {
		TableColumns()
	}

	static var _columnWidth: Int {
		Model._columnWidth + [TableAlias<Paragraph, ParagraphAlias>].JSONRepresentation._columnWidth
	}

	static var tableName: String { "" }

	struct TableColumns: TableDefinition {
		typealias QueryValue = _WithChildren

		let block = _TableColumn<QueryValue, Model>.for("block", keyPath: \_WithChildren.block)
		let content = TableColumn<QueryValue, [TableAlias<Paragraph, ParagraphAlias>].JSONRepresentation>("content", keyPath: \_WithChildren.content)

		static var allColumns: [any TableColumnExpression] {
			var allColumns: [any TableColumnExpression] = []

			allColumns.append(contentsOf: _WithChildren.columns.block._allColumns)
			allColumns.append(contentsOf: _WithChildren.columns.content._allColumns)

			return allColumns
		}

		static var writableColumns: [any WritableTableColumnExpression] {
			var writableColumns: [any WritableTableColumnExpression] = []

			writableColumns.append(contentsOf: _WithChildren.columns.block._writableColumns)
			writableColumns.append(contentsOf: _WithChildren.columns.content._writableColumns)

			return writableColumns
		}

		var queryFragment: QueryFragment { "\(block), \(content)" }
	}

	struct Selection: StructuredQueriesCore.TableExpression {
		typealias QueryValue = _WithChildren

		let allColumns: [any QueryExpression]

		init(block: some QueryExpression<Model>, content: some QueryExpression<[TableAlias<Paragraph, ParagraphAlias>].JSONRepresentation>) {
			var allColumns: [any QueryExpression] = []

			allColumns.append(contentsOf: block._allColumns)
			allColumns.append(contentsOf: content._allColumns)

			self.allColumns = allColumns
		}
	}
}

public extension TableDefinition where QueryValue: _OptionalProtocol & Codable {
	func optionalJSONGroupArray<Wrapped: Codable>(
		distinct isDistinct: Bool = false,
		order: (some QueryExpression)? = Bool?.none,
		filter: some QueryExpression<Bool>
	) -> some QueryExpression<[Wrapped].JSONRepresentation> where QueryValue == Wrapped? {
		AggregateFunctionExpression(
			"json_group_array",
			distinct: isDistinct,
			QueryValue.columns.jsonObject(filtering: filter),
			order: order,
			filter: filter
		)
	}
}

public extension Optional.TableColumns where QueryValue: Codable {
	func jsonObject(filtering filter: some QueryExpression<Bool>) -> some QueryExpression<_CodableJSONRepresentation<Wrapped>?> {
		Case().when(filter, then: Wrapped.columns.jsonObject())
	}
}
