import SQLiteData
import Foundation

protocol HasChildren: Table & PrimaryKeyedTable<UUID> where Self.QueryOutput == Self {}

struct _WithChildren<Model: Table> where Model.QueryOutput == Model {
	let block: Model
	let tree: BlockTree

	// just to make the decoder happy, holds no actual data
	private let content: [Paragraph] = []
}

extension HasChildren {
	typealias WithChildren = _WithChildren<Self>

	static func withChildren(id: Self.PrimaryKey) -> some SelectStatement<WithChildren, Self, (Ancestor, Paragraph)> {
		find(id)
			.group(by: \.primaryKey)
			.join(Ancestor.all) { $0.primaryKey.eq($1.ancestorId) }
			.join(Paragraph.all) { $1.blockId.eq($2.id) }
			.select { block, _, paragraph in
				WithChildren.Columns(block: block, content: paragraph.jsonGroupArray())
			}
			.asSelect()
	}
}

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
		Model._columnWidth + [Paragraph].JSONRepresentation._columnWidth
	}

	static var tableName: String { "" }

	struct TableColumns: TableDefinition {
		typealias QueryValue = _WithChildren

		let block = _TableColumn<QueryValue, Model>.for("block", keyPath: \_WithChildren.block)
		let content = TableColumn<QueryValue, [Paragraph].JSONRepresentation>("content", keyPath: \_WithChildren.content)

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

		init(block: some QueryExpression<Model>, content: some QueryExpression<[Paragraph].JSONRepresentation>) {
			var allColumns: [any QueryExpression] = []

			allColumns.append(contentsOf: block._allColumns)
			allColumns.append(contentsOf: content._allColumns)

			self.allColumns = allColumns
		}
	}
}
