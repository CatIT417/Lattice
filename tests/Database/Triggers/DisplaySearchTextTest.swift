import GRDB
import Testing
import Sharing
import Foundation
import SQLiteData
import CustomDump
@testable import LatticeDev
import DependenciesTestSupport

extension Tests {
	@Suite("Database/DisplaySearchText", .dependencies {
		$0.locale = Locale(identifier: "en_US")
		try $0.bootstrapDatabase()
	})
	struct DisplaySearchTextTest {
		@Dependency(\.defaultDatabase) var database
		@Dependency(\.defaultAppStorage) var defaults

		init() throws {
			try database.write { try RebuildSearchIndex.run(in: $0) }
		}

		func matches(_ query: String, in db: Database) throws -> [Block.ID] {
			try BlockText.matching(query)
				.join(Block.where(\.isVisible)) { $0.blockID.eq($1.id) }
				.select { _, blocks in blocks.id }
				.fetchAll(db)
		}
	}
}

extension Tests.DisplaySearchTextTest {
	@Test("Unlinked date mentions require a full date")
	func unlinkedDates() throws {
		try database.write { db in
			let page = try Page.createDailyNote(for: DayOfYear(day: 12, month: 2, year: 2026), in: db)
			let source = Block(title: "Notes")
			let full = Block(string: "February 12, 2026", parentId: source.id)
			let partial = Block(string: "February 12", parentId: source.id)
			let linked = Block(string: "[[2026-02-12]]", parentId: source.id)
			try Block.insert { [source, full, partial, linked] }.execute(db)
			let count = try Backlink.unlinkedReferenceCount(forPage: page.id, title: page.canonicalTitle).fetchOne(db)
			expectNoDifference(count, 1)
			let groups = try Backlink.unlinkedReferences(forPage: page.id, title: page.canonicalTitle).fetchAll(db)
			expectNoDifference(groups.flatMap(\.referencedBlockIDs), [full.id])
		}
	}

	@Test("Search finds displayed dates and keeps short terms", arguments: [
		"February 12", "on February 12", "12 February", "2026-02-12 Alice",
	])
	func dateQueries(query: String) throws {
		try database.write { db in
			let page = Block(title: "Notes")
			let match = Block(string: "Meet on [[2026-02-12]] with [[Alice]].", parentId: page.id)
			let other = Block(string: "Meet on [[2026-02-13]] with [[Alice]].", parentId: page.id)
			let code = Block(string: "Use `[[2026-02-12]]` as an example.", parentId: page.id)
			try Block.insert { [page, match, other, code] }.execute(db)
			let result = try matches(query, in: db)
			#expect(result.contains(match.id))
			#expect(!result.contains(other.id))
			#expect(!result.contains(code.id))
			expectNoDifference(result.filter { $0 == match.id }.count, 1)
		}
	}

	@Test("FTS phrases cross rendered reference boundaries")
	func phrasePositions() throws {
		try database.write { db in
			let page = Block(title: "Notes")
			let paragraph = Block(string: "Meet on [[2026-02-12]] with [[Alice]].", parentId: page.id)
			try Block.insert { [page, paragraph] }.execute(db)
			for phrase in ["on February 12", "2026 with Alice"] {
				let matches = try BlockText.where { $0.displayString.match(phrase) }.select(\.blockID).fetchAll(db)
				expectNoDifference(matches, [paragraph.id])
			}
		}
	}

	@Test("Locale rebuilds change only local search data")
	func localeRebuild() throws {
		let page = Block(title: "Notes")
		let paragraph = Block(string: "Meet on [[2026-02-12]] with [[Alice]].", parentId: page.id)
		let (before, references) = try database.write { db in
			try Block.insert { [page, paragraph] }.execute(db)
			return try (Block.order(by: \.id).fetchAll(db), Reference.order(by: \.sourceBlockId).fetchAll(db))
		}
		try withDependencies {
			$0.locale = Locale(identifier: "fr_FR")
		} operation: {
			try database.write { db in
				try RebuildSearchIndex.run(in: db)
				expectNoDifference(defaults.string(forKey: RebuildSearchIndex.localeKey), "en_US")
			}
			expectNoDifference(defaults.string(forKey: RebuildSearchIndex.localeKey), "fr_FR")
			try database.read { db in
				expectNoDifference(Page.title(for: "2026-02-12"), "12 février 2026")
				let row = try #require(try BlockText.where { $0.blockID.eq(paragraph.id) }.fetchOne(db))
				expectNoDifference(row.string, paragraph.string)
				expectNoDifference(row.displayString, "Meet on 12 février 2026 with Alice.")
				#expect(try matches("12 février", in: db).contains(paragraph.id))
				#expect(try matches("February 12", in: db).isEmpty)
				#expect(try matches("2026-02-12", in: db).contains(paragraph.id))
				try expectNoDifference(Block.order(by: \.id).fetchAll(db), before)
				try expectNoDifference(Reference.order(by: \.sourceBlockId).fetchAll(db), references)
			}

			try database.write { db in
				let changes = db.totalChangesCount
				try RebuildSearchIndex.run(in: db)
				expectNoDifference(db.totalChangesCount, changes)
			}
			try database.write { db in
				try Block.find(paragraph.id).update { $0.string = #bind("Next [[2026-02-13]]") }.execute(db)
			}
			try database.read { db in
				let updatedMatches = try matches("13 février", in: db)
				let previousMatches = try matches("12 février", in: db)
				#expect(updatedMatches.contains(paragraph.id))
				#expect(!previousMatches.contains(paragraph.id))
			}
		}
	}

	@Test("A failed rebuild preserves the index and saved locale, then succeeds on retry")
	func failedRebuild() throws {
		let page = Block(title: "Notes")
		let paragraph = Block(string: "Meet [[2026-02-12]]", parentId: page.id)
		let (before, indexBefore) = try database.write { db in
			try Block.insert { [page, paragraph] }.execute(db)
			return try (Block.order(by: \.id).fetchAll(db), BlockText.order(by: \.blockID).fetchAll(db))
		}

		#expect(throws: DatabaseError.self) {
			try withDependencies {
				$0.locale = Locale(identifier: "fr_FR")
			} operation: {
				try database.write { db in
					db.add(function: GRDB.DatabaseFunction($searchDisplayString.name, argumentCount: 1) { _ in
						throw DatabaseError(resultCode: .SQLITE_ERROR, message: "Test rebuild failure")
					})
					defer { db.add(function: $searchDisplayString) }
					try RebuildSearchIndex.run(in: db)
				}
			}
		}
		try database.read { db in
			try expectNoDifference(Block.order(by: \.id).fetchAll(db), before)
			try expectNoDifference(BlockText.order(by: \.blockID).fetchAll(db), indexBefore)
			#expect(try matches("February 12", in: db).contains(paragraph.id))
		}
		expectNoDifference(defaults.string(forKey: RebuildSearchIndex.localeKey), "en_US")
		try withDependencies {
			$0.locale = Locale(identifier: "fr_FR")
		} operation: {
			try database.write { try RebuildSearchIndex.run(in: $0) }
		}
		try database.read { db in
			let result = try matches("12 février", in: db)
			#expect(result.contains(paragraph.id))
		}
		expectNoDifference(defaults.string(forKey: RebuildSearchIndex.localeKey), "fr_FR")
	}

	@Test("FTS indexes missing date targets while the SQL sync flag is set")
	func remoteWrite() throws {
		let database = try makeDatabase()
		try database.write { db in
			try CreateBlocksTable.up(db)
			try CreateBlocksFTSTables.up(db)
		}
		try database.setupTriggers([SyncBlocksFTSTable.self])
		try database.write { db in
			db.add(function: GRDB.DatabaseFunction(SyncEngine.$isSynchronizing.name, argumentCount: 0) { _ in true })
			defer { db.add(function: SyncEngine.$isSynchronizing) }
			let page = Block(title: "Notes")
			let paragraph = Block(string: "Meet [[2026-02-12]]", parentId: page.id)
			try Block.insert { [page, paragraph] }.execute(db)
			#expect(try Block.where { $0.dailyNoteDate.isNot(nil) }.fetchCount(db) == 0)
			try expectNoDifference(BlockText.matching("February 12").select(\.blockID).fetchAll(db), [paragraph.id])
			try Block.find(paragraph.id).update { $0.string = #bind("Meet [[2026-02-13]]") }.execute(db)
			try expectNoDifference(BlockText.matching("February 13").select(\.blockID).fetchAll(db), [paragraph.id])
			#expect(try BlockText.matching("February 12").fetchCount(db) == 0)
			try Block.find(paragraph.id).delete().execute(db)
			#expect(try BlockText.matching("February 13").fetchCount(db) == 0)
		}
	}

	@Test("Short terms are literal and remain required", arguments: ["AI research", "% research", "_ research", "é research", "12 13"])
	func shortTerms(query: String) throws {
		try database.write { db in
			let page = Block(title: "Notes")
			let match = Block(string: query, parentId: page.id)
			let other = Block(string: "research 13", parentId: page.id)
			try Block.insert { [page, match, other] }.execute(db)
			try expectNoDifference(matches(query, in: db), [match.id])
		}
	}

	@MainActor @Test("Suggestions display a date and insert its canonical target")
	func dateSuggestions() throws {
		try database.write { db in
			let day = DayOfYear(day: 12, month: 2, year: 2026)
			_ = try Page.createDailyNote(for: day, in: db)
			_ = try Page.createDailyNote(for: DayOfYear(day: 13, month: 2, year: 2026), in: db)
			let suggestions = try ReferenceSuggestions.Item.matchingPages(for: "February 12", limit: 30).fetchAll(db)
			expectNoDifference(suggestions.map(\.canonicalTitle), ["2026-02-12"])
			let suggestion = try #require(suggestions.first)
			expectNoDifference(suggestion.title, "February 12, 2026")
			let context = try #require(ReferenceSuggestions.Context(in: "[[February 12]]", cursorOffset: 13))
			try expectNoDifference(context.replacing(with: suggestion.canonicalTitle).text, "[[2026-02-12]]")
		}
	}
}
