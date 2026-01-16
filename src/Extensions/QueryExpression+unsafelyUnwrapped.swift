import SQLiteData

extension QueryExpression where QueryValue: _OptionalProtocol {
	var unsafelyUnwrapped: SQLQueryExpression<QueryValue.Wrapped> {
		SQLQueryExpression("\(self)", as: QueryValue.Wrapped.self)
	}
}
