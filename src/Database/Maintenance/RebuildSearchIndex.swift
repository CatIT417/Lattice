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
		try BlockText.insert {
			($0.blockID, $0.canonicalTitle, $0.string, $0.displayTitle, $0.displayString)
		} select: {
			Block.select {
				(
					$0.id,
					$0.title,
					$0.string,
					$searchDisplayTitle($0.title),
					$searchDisplayString($0.string)
				)
			}
		}
		.execute(db)
	}
}
