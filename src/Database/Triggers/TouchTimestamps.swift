import Foundation
import SQLiteData

final class TouchTimestamps: Trigger {
	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .update {
			$0.updatedAt = $now()
		}).execute(db)

		try Block.createTemporaryTrigger(after: .update(forEachRow: { _, block in
			Block.where { $0.id.eq(block.pageId.unsafelyUnwrapped) }.update { $0.updatedAt = $now() }
		}, when: { _, block in
			block.string.isNot(nil) && block.pageId.isNot(nil)
		})).execute(db)
	}
}
