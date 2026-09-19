import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport
import SQLite3

@testable import LatticeDev

extension Tests {
	@Suite("Support/RoamImporter", .dependencies {
		$0.uuid = .incrementing
		try $0.bootstrapDatabase()
	})
	struct RoamImporterTest {
		@Dependency(\.defaultDatabase) var database
	}
}

// MARK: - Daily Page Detection

extension Tests.RoamImporterTest {
	@Test("Daily dates use the Roam UID before the canonical title", arguments: [
		("01-18-2026", "2026-02-03", DayOfYear(day: 18, month: 1, year: 2026) as DayOfYear?),
		("abc123", "2026-01-18", DayOfYear(day: 18, month: 1, year: 2026)),
		("abc123", "My Regular Page", nil),
		("02-31-2024", "Not a real date", nil),
	])
	func dailyDate(uid: String, title: String, expected: DayOfYear?) {
		expectNoDifference(RoamImporter.parseDailyDate(uid: uid, title: title), expected)
	}
}

// MARK: - Title Validation

extension Tests.RoamImporterTest {
	@Test("Import reports invalid titles", arguments: [
		("AB", Page.TitleError.tooShort), (" AB ", .tooShort),
		("Bad [Title", .containsBrackets), ("Bad ]Title", .containsBrackets),
	])
	func invalidTitleFails(title: String, expected: Page.TitleError) throws {
		let json = """
		[
			{"uid": "p1", "title": "\(title)", "children": [{"uid": "b1", "string": "block"}]},
			{"uid": "p2", "title": "Valid Page", "children": [{"uid": "b2", "string": "block"}]}
		]
		"""

		let (valid, failed) = try prepare(from: json)

		try #require(valid.count == 1)
		#expect(valid[0].page.canonicalTitle == "Valid Page")
		try #require(failed.count == 1)
		#expect(failed[0].title == title)
		expectNoDifference(failed[0].reason.localizedDescription, expected.localizedDescription)
	}
}

// MARK: - Block Reference Rewriting

extension Tests.RoamImporterTest {
	@Test("Rewrites block references with mapped UUIDs after import")
	func rewriteBlockRefs() throws {
		let json = """
		[{
			"uid": "page1",
			"title": "Ref Test",
			"children": [
				{"uid": "target", "string": "Target block"},
				{"uid": "source", "string": "See ((target)) for details"}
			]
		}]
		"""

		let valid = try preparedPages(from: json)
		let preparedPage = try #require(valid.first)
		let rawSource = try #require(preparedPage.paragraphs.first { $0.string.contains("See") })
		#expect(rawSource.string == "See ((target)) for details")

		let _ = try RoamImporter.execute(pages: valid)
		let page = try requiredPage(title: "Ref Test")
		let blocks = try paragraphs(in: page.id)
		let source = try #require(blocks.first { $0.string.contains("See") })

		let target = try #require(blocks.first { $0.string == "Target block" })
		expectNoDifference(source.string, "See ((\(target.id.uuidString))) for details")
		expectNoDifference(try database.read { db in
			try Backlink.where { $0.fromBlock.eq(source.id) }.select(\.toBlock).fetchAll(db)
		}, [target.id])
	}

	@Test("Leaves unresolved block references as raw Roam UIDs")
	func unresolvedBlockRefs() throws {
		let json = """
		[{
			"uid": "page1",
			"title": "Unresolved",
			"children": [
				{"uid": "source", "string": "See ((unknown-uid)) here"}
			]
		}]
		"""

		let _ = try executeImport(from: json)
		let page = try requiredPage(title: "Unresolved")
		let block = try firstParagraph(in: page.id)

		#expect(block.string == "See ((unknown-uid)) here")
	}

	@Test("Cross-page references resolve in either import order", arguments: [false, true])
	func crossPageBlockRefs(sourceFirst: Bool) throws {
		let json = """
		[
			{"uid": "p1", "title": "Page One", "children": [{"uid": "target-block", "string": "Target"}]},
			{"uid": "p2", "title": "Page Two", "children": [{"uid": "ref-block", "string": "((target-block))"}]}
		]
		"""

		var valid = try preparedPages(from: json)
		let preparedPage = try #require(valid.first)
		let targetBlockId = try #require(preparedPage.paragraphs.first).id
		if sourceFirst { valid.reverse() }
		let _ = try RoamImporter.execute(pages: valid)

		let page = try requiredPage(title: "Page Two")
		let block = try firstParagraph(in: page.id)
		expectNoDifference(block.string, "((\(targetBlockId.uuidString)))")
		let references = try database.read { try Backlink.where { $0.fromBlock.eq(block.id) }.fetchAll($0) }
		expectNoDifference(references.map(\.toBlock), [targetBlockId])
	}

	@Test("Does not rewrite refs to blocks from skipped pages")
	func skippedPageRefsNotRewritten() throws {
		let json = """
		[
			{"uid": "p1", "title": "Skipped Page", "children": [{"uid": "skip-block", "string": "I will be skipped"}]},
			{"uid": "p2", "title": "Imported Page", "children": [{"uid": "ref-block", "string": "((skip-block))"}]}
		]
		"""

		let _ = try executeImport(from: json) { pages in
			pages[0].resolution = .skip
		}

		let page = try requiredPage(title: "Imported Page")
		let block = try firstParagraph(in: page.id)
		#expect(block.string == "((skip-block))")
	}

	@Test("Daily links use canonical titles even when content is skipped", arguments: [false, true])
	func rewritesDailyPageLinks(skip: Bool) throws {
		let latticeTitle = DayOfYear(day: 18, month: 1, year: 2026).rawValue
		let roamTitle = "Jan 18th, 2026"
		try #require(roamTitle != latticeTitle)

		let json = """
		[
			{"uid": "01-18-2026", "title": "\(roamTitle)", "children": [{"uid": "b1", "string": "Daily block"}]},
			{"uid": "p2", "title": "Other Page", "children": [
				{"uid": "b2", "string": "See [[\(roamTitle)]] and #[[\(roamTitle)]] for notes"}
			]}
		]
		"""

		let _ = try executeImport(from: json) { pages in
			if skip { pages[0].resolution = .skip }
		}

		let otherPage = try requiredPage(title: "Other Page")
		let block = try firstParagraph(in: otherPage.id)
		#expect(block.string == "See [[\(latticeTitle)]] and #[[\(latticeTitle)]] for notes")

		let orphan = try page(title: roamTitle)
		#expect(orphan == nil)
		let daily = try requiredPage(title: latticeTitle)
		expectNoDifference(try children(of: daily.id).map(\.string), skip ? [] : ["Daily block"])
	}

}

// MARK: - Import Execution

extension Tests.RoamImporterTest {
	@Test("Imports a new page with nested blocks")
	func importNewPage() throws {
		let json = """
		[{
			"uid": "page1",
			"title": "Import Test",
			"children": [
				{
					"uid": "b1",
					"string": "First",
					"children": [{"uid": "b2", "string": "Nested"}]
				},
				{"uid": "b3", "string": "Second"}
			]
		}]
		"""

		let result = try executeImport(from: json)
		try #require(result.imported.count == 1)
		#expect(result.imported[0].canonicalTitle == "Import Test")

		let page = try requiredPage(title: "Import Test")
		let rootChildren = try children(of: page.id)
		try #require(rootChildren.count == 2)
		#expect(rootChildren[0].string == "First")
		#expect(rootChildren[1].string == "Second")

		let nested = try children(of: rootChildren[0].id)
		try #require(nested.count == 1)
		#expect(nested[0].string == "Nested")
	}

	@Test("Bulk import respects the SQLite parameter limit and preserves nested order")
	func batchImport() throws {
		let existing = try database.write { db in
			let page = try Page.findOrCreate(title: "Batch Import", in: db)
			let alias = Block(title: page.canonicalTitle, mergedInto: page.id)
			let hidden = Block(string: "Hidden", parentId: alias.id, order: 10 * ParagraphOrder.gap, deletedAt: Date(timeIntervalSince1970: 100))
			try Block.insert { [alias, hidden] }.execute(db)
			return page
		}
		let roots = (0 ..< 60).map { index -> [String: Any] in
			["uid": "root-\(index)", "string": "Root \(index)", "children": [
				["uid": "first-\(index)", "string": "First \(index)"],
				["uid": "second-\(index)", "string": "Second \(index)"],
			]]
		}
		let data = try JSONSerialization.data(withJSONObject: [["uid": "page", "title": existing.canonicalTitle, "children": roots]])
		let prepared = try preparedPages(from: String(decoding: data, as: UTF8.self))
		let previousLimit = try database.write { db in
			return sqlite3_limit(db.sqliteConnection, SQLITE_LIMIT_VARIABLE_NUMBER, 260)
		}
		defer {
			try? database.write { db in
				_ = sqlite3_limit(db.sqliteConnection, SQLITE_LIMIT_VARIABLE_NUMBER, previousLimit)
			}
		}

		let result = try RoamImporter.execute(pages: prepared)
		expectNoDifference(result.imported.map(\.id), [existing.id])
		let children = try children(of: existing.id)
		expectNoDifference(children.map(\.string), (0 ..< 60).map { "Root \($0)" })
		try #require(children.count == 60)
		#expect(children[0].order > 10 * ParagraphOrder.gap)
		for (index, child) in children.enumerated() {
			let nested = try self.children(of: child.id)
			expectNoDifference(nested.map(\.string), ["First \(index)", "Second \(index)"])
			try #require(nested.count == 2)
			#expect(nested[0].order < nested[1].order)
			#expect(nested.allSatisfy { $0.pageId == existing.id })
		}
	}

	@Test("Import batches for the same page append in source order")
	func repeatedDestination() throws {
		let json = """
		[
			{"uid": "page1", "title": "Same Page", "children": [
				{"uid": "a", "string": "First"}, {"uid": "b", "string": "Second"}
			]},
			{"uid": "page2", "title": "Same Page", "children": [
				{"uid": "c", "string": "Third"}, {"uid": "d", "string": "Fourth"}
			]}
		]
		"""
		let result = try executeImport(from: json)
		try #require(result.imported.count == 2)
		#expect(result.imported[0].id == result.imported[1].id)
		expectNoDifference(try children(of: result.imported[0].id).map(\.string), ["First", "Second", "Third", "Fourth"])
	}

	@Test("New imports preserve page timestamps", arguments: [
		("page-ts-regular", "Timestamped Regular", "Timestamped Regular", false),
		("01-18-2026", "January 18th, 2026", "2026-01-18", true),
	])
	func importedPageTimestamps(uid: String, title: String, canonicalTitle: String, daily: Bool) throws {
		let json = """
		[{
			"uid": "\(uid)", "title": "\(title)",
			"create-time": 1700000000000, "edit-time": 1700000123000,
			"children": [{"uid": "b1", "string": "Block"}]
		}]
		"""
		let result = try executeImport(from: json)
		let page = try requiredPage(title: canonicalTitle)
		expectNoDifference(result.imported.map(\.id), [page.id])
		expectNoDifference(page.isDailyNote, daily)
		expectNoDifference(page.canonicalTitle, canonicalTitle)
		expectNoDifference(page.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
		expectNoDifference(page.updatedAt, Date(timeIntervalSince1970: 1_700_000_123))
	}

	@Test("Merges blocks into existing page")
	func mergeIntoExisting() throws {
		let existingPage = try #require(database.write { db in
			try Page.insert { Page(title: "Existing") }.returning(\.self).fetchOne(db)
		})
		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Original block", parentId: existingPage.id, pageId: existingPage.id, order: 0)
			}.execute(db)
		}

		let json = """
		[{"uid": "p1", "title": "Existing", "children": [{"uid": "b1", "string": "New block"}]}]
		"""

		let result = try executeImport(from: json) { pages in
			pages[0].resolution = .merge
		}

		try #require(result.imported.count == 1)
		#expect(result.imported[0].id == existingPage.id)

		let children = try children(of: existingPage.id)
		try #require(children.count == 2)
		#expect(children[0].string == "Original block")
		#expect(children[1].string == "New block")
	}

	@Test("Replacing page contents keeps its identity and records a local edit", .dependencies {
		$0.date = .constant(Date(timeIntervalSince1970: 1_000))
	})
	func replaceExisting() throws {
		let originalCreatedAt = Date(timeIntervalSince1970: 100)
		let originalUpdatedAt = Date(timeIntervalSince1970: 200)

		let existingPage = try #require(database.write { db in
			try Page.insert {
				Page(title: "Timestamp Conflict", createdAt: originalCreatedAt, updatedAt: originalUpdatedAt)
			}.returning(\.self).fetchOne(db)
		})
		let oldRoot = Paragraph(string: "Old block", parentId: existingPage.id, pageId: existingPage.id, order: 0)
		let oldChild = Paragraph(string: "Old child", parentId: oldRoot.id, pageId: existingPage.id, order: 0)
		try database.write { db in
			try Paragraph.insert { [oldRoot, oldChild] }.execute(db)
		}

		let importedCreatedTime = 1_800_000_000_000
		let importedEditedTime = 1_800_000_120_000
		let json = """
		[{
			"uid": "replace-ts",
			"title": "Timestamp Conflict",
			"create-time": \(importedCreatedTime),
			"edit-time": \(importedEditedTime),
			"children": [{"uid": "b1", "string": "Replacement"}]
		}]
		"""

		let result = try executeImport(from: json) { pages in
			pages[0].resolution = .replace
		}

		let page = try requiredPage(title: "Timestamp Conflict")
		expectNoDifference(result.imported.map(\.id), [existingPage.id])
		expectNoDifference(page.id, existingPage.id)
		expectNoDifference(try children(of: page.id).map(\.string), ["Replacement"])
		let remaining = try database.read { try Paragraph.where { $0.pageId.eq(page.id) }.fetchAll($0) }
		expectNoDifference(remaining.map(\.string), ["Replacement"])
		#expect(!remaining.contains { $0.id == oldRoot.id || $0.id == oldChild.id })
		expectNoDifference(page.createdAt, originalCreatedAt)
		expectNoDifference(page.updatedAt, Date(timeIntervalSince1970: 1_000))
	}

	@Test("Skips pages with skip resolution")
	func skipPage() throws {
		let json = """
		[{"uid": "p1", "title": "Skip Me", "children": [{"uid": "b1", "string": "block"}]}]
		"""

		let result = try executeImport(from: json) { pages in
			pages[0].resolution = .skip
		}

		#expect(result.imported.isEmpty)
		#expect(result.skipped == 1)
		#expect(try page(title: "Skip Me") == nil)
	}

	@Test("Preserves block style and distinct timestamps")
	func preservesBlockProperties() throws {
		let json = """
		[{
			"uid": "p1",
			"title": "Properties",
			"children": [
				{"uid": "h1", "string": "Heading", "heading": 2, "text-align": "right", "create-time": 1700000000000, "edit-time": 1700000123000},
				{"uid": "plain", "string": "Plain"}
			]
		}]
		"""

		let result = try executeImport(from: json)
		try #require(result.imported.count == 1)

		let page = try requiredPage(title: "Properties")
		let blocks = try children(of: page.id)
		try #require(blocks.count == 2)
		let block = blocks[0]
		#expect(blocks[1].heading == nil)
		expectNoDifference(blocks[1].textAlign, .left)
		#expect(block.heading == .h2)
		#expect(block.textAlign == .right)
		expectNoDifference(block.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
		expectNoDifference(block.updatedAt, Date(timeIntervalSince1970: 1_700_000_123))
	}
}

// MARK: - Helpers

extension Tests.RoamImporterTest {
	private func importer(from json: String) throws -> RoamImporter {
		let url = try writeJSON(json)
		defer { try? FileManager.default.removeItem(at: url) }
		return try RoamImporter(url: url)
	}

	private func prepare(from json: String) throws -> (valid: [RoamImporter.PreparedPage], failed: [RoamImporter.FailedPage]) {
		try importer(from: json).prepare()
	}

	private func preparedPages(from json: String) throws -> [RoamImporter.PreparedPage] {
		try prepare(from: json).valid
	}

	private func executeImport(
		from json: String,
		configure: ((inout [RoamImporter.PreparedPage]) -> Void)? = nil
	) throws -> RoamImporter.Result {
		var valid = try preparedPages(from: json)
		configure?(&valid)
		return try RoamImporter.execute(pages: valid)
	}

	private func page(title: String) throws -> Page? {
		try database.read { db in
			try Page.where { $0.canonicalTitle.eq(title) }.fetchOne(db)
		}
	}

	private func requiredPage(title: String) throws -> Page {
		try #require(try page(title: title))
	}

	private func requiredPage(day: DayOfYear) throws -> Page {
		try #require(database.read { db in
			try Page.where { $0.dailyNoteDate.eq(#bind(day)) }.fetchOne(db)
		})
	}

	private func paragraphs(in pageId: Page.ID) throws -> [Paragraph] {
		try database.read { db in
			try Paragraph.where { $0.pageId.eq(#bind(pageId)) }
				.order(by: \.order)
				.fetchAll(db)
		}
	}

	private func firstParagraph(in pageId: Page.ID) throws -> Paragraph {
		try #require(database.read { db in
			try Paragraph.where { $0.pageId.eq(#bind(pageId)) }.fetchOne(db)
		})
	}

	private func children(of parentId: Block.ID) throws -> [Paragraph] {
		try database.read { db in
			try Paragraph.where { $0.parentId.eq(#bind(parentId)) }
				.order(by: \.order)
				.fetchAll(db)
		}
	}

	private func writeJSON(_ json: String) throws -> URL {
		let url = URL.temporaryDirectory.appending(path: "\(UUID()).json")
		try json.write(to: url, atomically: true, encoding: .utf8)
		return url
	}
}
