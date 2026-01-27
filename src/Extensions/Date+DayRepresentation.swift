import Foundation
import SQLiteData

fileprivate let formatter = tap(ISO8601DateFormatter()) { $0.formatOptions = [.withFullDate] }

public extension Date {
	var asDayRepresentation: String {
		formatter.string(from: self)
	}

	struct DayRepresentation: QueryRepresentable, QueryBindable, QueryDecodable, SQLiteType {
		struct InvalidDate: Error { let string: String }

		public var queryOutput: Date

		public static var typeAffinity: SQLiteTypeAffinity {
			String.typeAffinity
		}

		public var queryBinding: QueryBinding {
			.text(queryOutput.asDayRepresentation)
		}

		public init(decoder: inout some QueryDecoder) throws {
			let dateString = try String(decoder: &decoder)
			guard let date = formatter.date(from: dateString) else { throw InvalidDate(string: dateString) }

			self.init(queryOutput: date)
		}

		public init(queryOutput: Date) {
			self.queryOutput = queryOutput
		}
	}
}

public extension Date? {
	typealias DayRepresentation = Date.DayRepresentation?
}
