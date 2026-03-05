import SQLiteData
import LinkPresentation

extension LPLinkMetadata {
	struct Archived: QueryDecodable, QueryRepresentable, QueryBindable, SQLiteType {
		var queryOutput: LPLinkMetadata

		var queryBinding: QueryBinding {
			do {
				return try .blob([UInt8](NSKeyedArchiver.archivedData(withRootObject: queryOutput, requiringSecureCoding: true)))
			} catch {
				return .invalid(error)
			}
		}

		static var typeAffinity: SQLiteTypeAffinity {
			[UInt8].typeAffinity
		}

		init(queryOutput: LPLinkMetadata) {
			self.queryOutput = queryOutput
		}

		init(decoder: inout some QueryDecoder) throws {
			guard let data = try decoder.decode(Data.self),
			      let metadata = try NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data)
			else { throw QueryDecodingError.missingRequiredColumn }

			queryOutput = metadata
		}
	}
}
