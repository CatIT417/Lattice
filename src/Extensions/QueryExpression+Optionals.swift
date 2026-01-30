import SQLiteData

extension QueryExpression where QueryValue: _OptionalProtocol {
	var unsafelyUnwrapped: SQLQueryExpression<QueryValue.Wrapped> {
		SQLQueryExpression("\(self)", as: QueryValue.Wrapped.self)
	}

	func map<T: _OptionalPromotable>(
		_ transform: (SQLQueryExpression<QueryValue.Wrapped>) -> some QueryExpression<T>,
		or default: some QueryExpression<T>
	) -> some QueryExpression<T> {
		Case(#sql("\(self) IS NULL"))
			.when(#sql("1"), then: `default`)
			.else(transform(SQLQueryExpression(queryFragment)))
	}
}

extension QueryExpression where QueryValue: _OptionalPromotable {
	var asOptional: SQLQueryExpression<QueryValue._Optionalized> {
		SQLQueryExpression("\(self)", as: QueryValue._Optionalized.self)
	}
}
