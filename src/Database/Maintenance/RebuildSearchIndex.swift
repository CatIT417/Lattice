import Sharing
import Foundation
import SQLiteData

enum RebuildSearchIndex {
	static let localeKey = "searchIndexLocale"

	static func run(in db: Database) throws {
		@Dependency(\.locale) var locale
		@Dependency(\.defaultAppStorage) var defaults

		guard defaults.string(forKey: localeKey) != locale.identifier else { return }

		try populate(in: db)

		db.afterNextTransaction { _ in
			@Dependency(\.defaultAppStorage) var defaults
			defaults.set(locale.identifier, forKey: localeKey)
		}
	}

	static func populate(in db: Database) throws {
		try BlockText.delete().execute(db)
		try BlockSearchID.delete().execute(db)

		try BlockSearchID.insert { $0.blockID } select: { Block.select(\.id) }.execute(db)
		try BlockText.insert {
			($0.rowid, $0.blockID, $0.canonicalTitle, $0.string, $0.displayTitle, $0.displayString)
		} select: {
			Block.join(BlockSearchID.all) { $0.id.eq($1.blockID) }.select { blocks, blockSearchIDs in
				(blockSearchIDs.id, blocks.id, blocks.title, blocks.string, $searchDisplayTitle(blocks.title), $searchDisplayString(blocks.string))
			}
		}
		.execute(db)
	}
}
