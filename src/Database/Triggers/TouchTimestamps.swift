import Foundation
import SQLiteData

fileprivate let currentTimestamp = #sql("current_timestamp", as: Date.UnixTimeRepresentation.self)

final class TouchTimestamps: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .update {
			$0.updatedAt = currentTimestamp
		}).execute(db)
	}
}
