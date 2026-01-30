import Foundation
import SQLiteData

fileprivate let currentTimestamp = #sql("current_timestamp", as: Date.UnixTimeRepresentation.self)

final class TouchTimestamps: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .update {
			$0.updatedAt = currentTimestamp
		}).execute(db)

		try Block.createTemporaryTrigger(after: .update(forEachRow: { _, block in
			Block.where { $0.id.eq(block.pageId.unsafelyUnwrapped) }.update { $0.updatedAt = currentTimestamp }
		}, when: { _, block in
			block.string.isNot(nil) && block.pageId.isNot(nil)
		})).execute(db)
	}
}
