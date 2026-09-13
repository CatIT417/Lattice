import Testing
import GRDB
import CustomDump
import Foundation
import SQLiteData
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/SyncReferencesTable", .dependencies { try $0.bootstrapDatabase() })
	struct SyncReferencesTableTest {
		@Dependency(\.defaultDatabase) var database

		@Test("Repeated references have one key for each kind")
		func indexesKeys() throws {
			try database.write { db in
				let page = Block(title: "Source")
				let missing = UUID(900)
				let source = Block(string: "[[Target]] [[Target]] #[[Target]] ((\(missing))) ((bad-id))", parentId: page.id)
				try Block.insert { [page, source] }.execute(db)
				let references = try Reference.where { $0.sourceBlockId.eq(source.id) }.fetchAll(db)
				expectNoDifference(Set(references.map(\.targetKey)), ["Target", missing.uuidString])
				expectNoDifference(Set(references.map(\.kind)), [.pageLink, .tag, .blockRef])
				#expect(try Page.where { $0.title.eq("Target") }.fetchCount(db) == 1)
				#expect(try Backlink.fetchCount(db) == 2)
				try Block.find(source.id).update { $0.string = #bind("No references") }.execute(db)
				#expect(try Reference.fetchCount(db) == 0)
			}
		}

		@Test("A missing UUID target resolves on arrival without a source edit")
		func lateBlock() throws {
			try database.write { db in
				let page = Block(title: "Source")
				let target = Block(string: "Target", parentId: page.id)
				let source = Block(string: "((\(target.id.uuidString.lowercased())))", parentId: page.id)
				try Block.insert { [page, source] }.execute(db)
				let storedSource = try Block.find(source.id).fetchOne(db)
				let keys = try Reference.fetchAll(db)
				#expect(try Backlink.fetchCount(db) == 0)
				try Block.insert { target }.execute(db)
				#expect(try Backlink.fetchOne(db)?.toBlock == target.id)
				expectNoDifference(try Reference.fetchAll(db), keys)
				expectNoDifference(try Block.find(source.id).fetchOne(db), storedSource)
			}
		}

		@Test("An unresolved title resolves on arrival without another index pass")
		func latePage() throws {
			try database.write { db in
				let page = Block(title: "Source")
				let source = Block(string: "[[Late Page]] [[Still Missing]]", parentId: page.id)
				try Block.insert { [page, source] }.execute(db)
				try Block.where { $0.title.unsafelyUnwrapped.in(["Late Page", "Still Missing"]) }.delete().execute(db)
				let keys = try Reference.fetchAll(db)
				#expect(try Page.fetchCount(db) == 1)
				let target = Block(title: "Late Page")
				try Block.insert { target }.execute(db)
				#expect(try Backlink.fetchOne(db)?.toBlock == target.id)
				expectNoDifference(try Reference.fetchAll(db), keys)
				#expect(try Page.fetchCount(db) == 2)
			}
		}

		@Test("Local renames keep mixed references and UTF-16 ranges correct")
		func rename() throws {
			try database.write { db in
				let page = Block(title: "Source")
				let source = Block(string: "👨‍👩‍👧‍👦 [[Old]] #[[Old]]suffix #Old more text [[Other]]", parentId: page.id)
				try Block.insert { [page, source] }.execute(db)
				let target = try #require(try Page.where { $0.title.eq("Old") }.fetchOne(db))
				try Block.find(target.id).update { $0.title = #bind("New") }.execute(db)
				expectNoDifference(try Paragraph.find(source.id).fetchOne(db)?.string, "👨‍👩‍👧‍👦 [[New]] #[[New]]suffix #New more text [[Other]]")
				expectNoDifference(Set(try Reference.fetchAll(db).map(\.targetKey)), ["New", "Other"])
			}
		}

		@Test("Invalid references do not prevent paragraph saves")
		func invalidReferences() throws {
			try database.write { db in
				let page = Block(title: "Source")
				let text = "[[Bad [Title]] #[[Bad [Title]] [label]([[Bad [Title]]) [label](#[[Bad [Title]]) [[Bad]Title]] [[Valid]]"
				let source = Block(string: text, parentId: page.id)
				try Block.insert { [page, source] }.execute(db)
				expectNoDifference(try Paragraph.find(source.id).fetchOne(db)?.string, text)
				expectNoDifference(try Reference.fetchAll(db).map(\.targetKey), ["Valid"])
				#expect(try Page.fetchCount(db) == 2)
			}
		}

		@Test("Renaming either duplicate keeps one page and updates all known title references", arguments: [100, 101])
		func renameDuplicate(renamedID: Int) throws {
			try database.write { db in
				let keeper = Block(id: UUID(100), title: "Old Title")
				let loser = Block(id: UUID(101), title: "Old Title")
				let deleted = Block(id: UUID(99), title: "Old Title", deletedAt: Date(timeIntervalSince1970: 500))
				let first = Block(string: "First [[Old Title]]", parentId: keeper.id)
				let second = Block(string: "Second #[[Old Title]]", parentId: loser.id)
				try Block.insert { [keeper, loser, deleted, first, second] }.execute(db)
				try Block.find(UUID(renamedID)).update { $0.title = #bind("New Title") }.execute(db)
				#expect(try Page.fetchCount(db) == 1)
				#expect(try Page.fetchOne(db)?.id == keeper.id)
				#expect(try Page.fetchOne(db)?.title == "New Title")
				#expect(try Block.find(loser.id).fetchOne(db)?.mergedInto == keeper.id)
				#expect(try Block.find(deleted.id).fetchOne(db)?.title == "Old Title")
				expectNoDifference(try Paragraph.find(first.id).fetchOne(db)?.string, "First [[New Title]]")
				expectNoDifference(try Paragraph.find(second.id).fetchOne(db)?.string, "Second #[[New Title]]")
				#expect(try Paragraph.where { $0.pageId.eq(keeper.id) }.fetchCount(db) == 2)
				#expect(try Backlink.where { $0.toBlock.eq(keeper.id) }.fetchCount(db) == 2)
				try MergeDuplicatePages.run(in: db)
				#expect(try Page.fetchCount(db) == 1)
				#expect(try Backlink.where { $0.toBlock.eq(keeper.id) }.fetchCount(db) == 2)
			}
		}

		@Test("A rename merges all copies of its old title and leaves other duplicate groups alone")
		func renameOnlyMergesOldTitle() throws {
			try database.write { db in
				let pages = [
					Block(id: UUID(100), title: "Old Title"),
					Block(id: UUID(101), title: "Old Title"),
					Block(id: UUID(102), title: "Old Title"),
					Block(id: UUID(200), title: "Other Title"),
					Block(id: UUID(201), title: "Other Title"),
				]
				try Block.insert { pages }.execute(db)
				try Block.find(UUID(102)).update { $0.title = #bind("New Title") }.execute(db)
				expectNoDifference(try Page.order(by: \.id).select(\.id).fetchAll(db), [UUID(100), UUID(200), UUID(201)])
				#expect(try Page.find(UUID(100)).fetchOne(db)?.title == "New Title")
				#expect(try Block.find(UUID(101)).fetchOne(db)?.mergedInto == UUID(100))
				#expect(try Block.find(UUID(102)).fetchOne(db)?.mergedInto == UUID(100))
				#expect(try Block.find(UUID(101)).fetchOne(db)?.title == "Old Title")
				#expect(try Block.find(UUID(200)).fetchOne(db)?.mergedInto == nil)
				#expect(try Block.find(UUID(201)).fetchOne(db)?.mergedInto == nil)
			}
		}

		@Test("A failed reference rewrite rolls back the rename and its merge", arguments: [100, 101])
		func failedRenameRollsBackMerge(renamedID: Int) throws {
			try database.write { db in
				let keeper = Block(id: UUID(100), title: "Old Title")
				let loser = Block(id: UUID(101), title: "Old Title")
				let source = Block(string: "[[Old Title]]", parentId: loser.id)
				try Block.insert { [keeper, loser, source] }.execute(db)
				let blocks = try Block.order(by: \.id).fetchAll(db)
				let references = try Reference.fetchAll(db)
				let hierarchy = try BlockHierarchy.order(by: \.blockId).fetchAll(db)
				let function = SyncReferencesTable().$updatePageTitleInReferences
				db.add(function: GRDB.DatabaseFunction(function.name, argumentCount: 2) { _ in
					throw DatabaseError(message: "Reference rewriting failed.")
				})
				defer { db.add(function: function) }
				#expect(throws: DatabaseError.self) {
					try Block.find(UUID(renamedID)).update { $0.title = #bind("New Title") }.execute(db)
				}
				expectNoDifference(try Block.order(by: \.id).fetchAll(db), blocks)
				expectNoDifference(try Reference.fetchAll(db), references)
				expectNoDifference(try BlockHierarchy.order(by: \.blockId).fetchAll(db), hierarchy)
			}
		}

		@Test("Deleting a target preserves source text and a new page resolves the title")
		func deleteAndRecreate() throws {
			try database.write { db in
				let page = Block(title: "Source")
				let source = Block(string: "[[Target]] #Target", parentId: page.id)
				try Block.insert { [page, source] }.execute(db)
				let storedSource = try Block.find(source.id).fetchOne(db)
				let target = try #require(try Page.where { $0.title.eq("Target") }.fetchOne(db))
				let child = Block(string: "Old contents", parentId: target.id)
				try Block.insert { child }.execute(db)
				let keys = try Reference.fetchAll(db)
				try Page.find(target.id).delete().execute(db)
				#expect(try Backlink.fetchCount(db) == 0)
				expectNoDifference(try Block.find(source.id).fetchOne(db), storedSource)
				expectNoDifference(try Reference.fetchAll(db), keys)
				let replacement = try Page.findOrCreate(title: "Target", in: db)
				#expect(replacement.id != target.id)
				#expect(try Paragraph.where { $0.pageId.eq(replacement.id) }.fetchCount(db) == 0)
				#expect(try Block.find(target.id).fetchOne(db)?.deletedAt != nil)
				#expect(try Backlink.where { $0.toBlock.eq(replacement.id) }.fetchCount(db) == 2)
			}
		}

		@Test("Daily references use a date key and a replacement note starts empty", arguments: [false, true])
		func dailyReplacement(useISO: Bool) throws {
			try database.write { db in
				let day = DayOfYear(day: 5, month: 9, year: 2026)
				let page = Block(title: "Source")
				let source = Block(string: "[[\(useISO ? day.rawValue : day.title())]]", parentId: page.id)
				try Block.insert { [page, source] }.execute(db)
				let key = try #require(try Reference.fetchOne(db))
				#expect(key.kind == .pageLink)
				#expect(key.targetKey == day.rawValue)
				let first = try Page.createDailyNote(for: day, in: db)
				try Block.insert { Block(string: "Old", parentId: first.id) }.execute(db)
				try Page.find(first.id).delete().execute(db)
				let second = try Page.createDailyNote(for: day, in: db)
				#expect(second.id != first.id)
				#expect(try Paragraph.where { $0.pageId.eq(second.id) }.fetchCount(db) == 0)
				#expect(try Backlink.fetchOne(db)?.toBlock == second.id)
			}
		}
	}
}

extension Tests.SyncReferencesTableTest {
	@Test("Both date formats share a key and resolve when the daily note arrives")
	func dailyAliasesResolveOnArrival() throws {
		try database.write { db in
			let day = DayOfYear(day: 5, month: 9, year: 2026)
			let page = Block(title: "Source")
			let source = Block(string: "[[\(day.title())]] [[\(day.rawValue)]] #[[\(day.title())]] #\(day.rawValue)", parentId: page.id)
			try Block.insert { [page, source] }.execute(db)
			let target = try #require(try Page.where { $0.dailyNoteDate.eq(day) }.fetchOne(db))
			let keys = try Reference.order(by: \.kind).fetchAll(db)
			expectNoDifference(keys.map(\.targetKey), [day.rawValue, day.rawValue])
			expectNoDifference(Set(keys.map(\.kind)), [.pageLink, .tag])
			try Block.find(target.id).delete().execute(db)
			#expect(try Backlink.fetchCount(db) == 0)
			let replacement = Block(id: UUID(900), title: "Daily note", dailyNoteDate: day)
			let duplicate = Block(id: UUID(901), title: day.title(), dailyNoteDate: day)
			try Block.insert { [replacement, duplicate] }.execute(db)
			expectNoDifference(try Backlink.select(\.toBlock).fetchAll(db), [replacement.id, replacement.id])
			expectNoDifference(try Reference.order(by: \.kind).fetchAll(db), keys)
		}
	}

	@Test("A page title that is a UUID stays separate from a block reference")
	func uuidTitleAndBlockReference() throws {
		try database.write { db in
			let page = Block(title: "Source")
			let target = Block(id: UUID(900), string: "Target", parentId: page.id)
			let source = Block(string: "[[\(target.id)]] ((\(target.id)))", parentId: page.id)
			try Block.insert { [page, target, source] }.execute(db)
			let titleTarget = try #require(try Page.where { $0.title.eq(target.id.uuidString) }.fetchOne(db))
			#expect(try Backlink.where { $0.kind.eq(Reference.Kind.pageLink) }.fetchOne(db)?.toBlock == titleTarget.id)
			#expect(try Backlink.where { $0.kind.eq(Reference.Kind.blockRef) }.fetchOne(db)?.toBlock == target.id)
		}
	}
}
