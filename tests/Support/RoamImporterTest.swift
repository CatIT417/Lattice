import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

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

// MARK: - JSON Parsing

extension Tests.RoamImporterTest {
	@Test("Parses a regular page with nested blocks")
	func parseRegularPage() throws {
		let json = """
		[{
			"uid": "abc123",
			"title": "Test Page",
			"children": [
				{
					"uid": "block1",
					"string": "First block",
					"children": [
						{"uid": "block2", "string": "Nested block"}
					]
				},
				{"uid": "block3", "string": "Second block"}
			]
		}]
		"""

		let importer = try importer(from: json)

		#expect(importer.roamPages.count == 1)
		#expect(importer.roamPages[0].title == "Test Page")
		#expect(importer.roamPages[0].children?.count == 2)
		#expect(importer.roamPages[0].children?[0].children?.count == 1)
	}

	@Test("Parses block heading and text-align fields")
	func parseBlockFields() throws {
		let json = """
		[{
			"uid": "page1",
			"title": "Fields Page",
			"children": [
				{"uid": "h1block", "string": "Heading", "heading": 1, "text-align": "center"},
				{"uid": "plain", "string": "Plain"}
			]
		}]
		"""

		let importer = try importer(from: json)
		let blocks = try #require(importer.roamPages[0].children)

		#expect(blocks[0].heading == 1)
		#expect(blocks[0].textAlign == "center")
		#expect(blocks[1].heading == nil)
		#expect(blocks[1].textAlign == nil)
	}
}

// MARK: - Daily Page Detection

extension Tests.RoamImporterTest {
	@Test("Detects daily page from Roam UID (MM-DD-YYYY)")
	func dailyPageFromUID() {
		let result = RoamImporter.parseDailyDate(uid: "01-18-2026", title: "January 18th, 2026")
		expectNoDifference(result, DayOfYear(day: 18, month: 1, year: 2026))
	}

	@Test("Falls back to title parsing when UID is not a date")
	func dailyPageFromTitle() {
		let result = RoamImporter.parseDailyDate(uid: "abc123", title: "January 18th, 2026")
		expectNoDifference(result, DayOfYear(day: 18, month: 1, year: 2026))
	}

	@Test("Returns nil for non-daily pages")
	func nonDailyPage() {
		let result = RoamImporter.parseDailyDate(uid: "abc123", title: "My Regular Page")
		#expect(result == nil)
	}

	@Test("Rejects impossible dates like Feb 31")
	func impossibleDate() {
		let result = RoamImporter.parseDailyDate(uid: "02-31-2024", title: "Not a real date")
		#expect(result == nil)
	}
}

// MARK: - Title Validation

extension Tests.RoamImporterTest {
	@Test("Marks pages with title < 3 chars as failed")
	func shortTitleFails() throws {
		let json = """
		[
			{"uid": "p1", "title": "AB", "children": [{"uid": "b1", "string": "block"}]},
			{"uid": "p2", "title": "Valid Page", "children": [{"uid": "b2", "string": "block"}]}
		]
		"""

		let (valid, failed) = try prepare(from: json)

		#expect(valid.count == 1)
		#expect(valid[0].page.title == "Valid Page")
		#expect(failed.count == 1)
		#expect(failed[0].title == "AB")
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
		let rawSource = try #require(valid[0].paragraphs.first { $0.string.contains("See") })
		#expect(rawSource.string == "See ((target)) for details")

		let _ = try RoamImporter.execute(pages: valid)
		let page = try requiredPage(title: "Ref Test")
		let blocks = try paragraphs(in: page.id)
		let source = try #require(blocks.first { $0.string.contains("See") })

		#expect(!source.string.contains("((target))"))
		#expect(source.string.contains("See (("))
		#expect(source.string.contains(")) for details"))
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

	@Test("Rewrites cross-page block references")
	func crossPageBlockRefs() throws {
		let json = """
		[
			{"uid": "p1", "title": "Page One", "children": [{"uid": "target-block", "string": "Target"}]},
			{"uid": "p2", "title": "Page Two", "children": [{"uid": "ref-block", "string": "((target-block))"}]}
		]
		"""

		let valid = try preparedPages(from: json)
		let targetBlockId = valid[0].paragraphs[0].id
		let _ = try RoamImporter.execute(pages: valid)

		let page = try requiredPage(title: "Page Two")
		let block = try firstParagraph(in: page.id)
		#expect(block.string == "((\(targetBlockId.uuidString)))")
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

	@Test("Rewrites page links when daily note title differs from Lattice format")
	func rewritesDailyPageLinks() throws {
		let latticeTitle = DayOfYear(day: 18, month: 1, year: 2026).title()
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

		let _ = try executeImport(from: json)

		let otherPage = try requiredPage(title: "Other Page")
		let block = try firstParagraph(in: otherPage.id)
		#expect(block.string == "See [[\(latticeTitle)]] and #[[\(latticeTitle)]] for notes")

		let orphan = try page(title: roamTitle)
		#expect(orphan == nil)
	}

	@Test("Rewrites page links even when the daily note page is skipped")
	func rewritesDailyPageLinksWhenSkipped() throws {
		let latticeTitle = DayOfYear(day: 18, month: 1, year: 2026).title()
		let roamTitle = "Jan 18th, 2026"
		try #require(roamTitle != latticeTitle)

		let json = """
		[
			{"uid": "01-18-2026", "title": "\(roamTitle)", "children": [{"uid": "b1", "string": "Daily block"}]},
			{"uid": "p2", "title": "Other Page", "children": [
				{"uid": "b2", "string": "Link to [[\(roamTitle)]]"}
			]}
		]
		"""

		let _ = try executeImport(from: json) { pages in
			pages[0].resolution = .skip
		}

		let otherPage = try requiredPage(title: "Other Page")
		let block = try firstParagraph(in: otherPage.id)
		#expect(block.string == "Link to [[\(latticeTitle)]]")
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
		#expect(result.imported.count == 1)
		#expect(result.imported[0].title == "Import Test")

		let page = try requiredPage(title: "Import Test")
		let rootChildren = try children(of: page.id)
		#expect(rootChildren.count == 2)
		#expect(rootChildren[0].string == "First")
		#expect(rootChildren[1].string == "Second")

		let nested = try children(of: rootChildren[0].id)
		#expect(nested.count == 1)
		#expect(nested[0].string == "Nested")
	}

	@Test("Imports a daily note page")
	func importDailyNote() throws {
		let json = """
		[{
			"uid": "01-18-2026",
			"title": "January 18th, 2026",
			"children": [{"uid": "b1", "string": "Daily block"}]
		}]
		"""

		let valid = try preparedPages(from: json)
		#expect(valid[0].page.isDailyNote)

		let result = try RoamImporter.execute(pages: valid)
		#expect(result.imported.count == 1)

		let page = try requiredPage(day: DayOfYear(day: 18, month: 1, year: 2026))
		#expect(page.title == "January 18th, 2026")
	}

	@Test("Persists regular page timestamps on new import")
	func persistsRegularPageTimestamps() throws {
		let createdTime = 1_700_000_000_000
		let editedTime = 1_700_000_123_000
		let json = """
		[{
			"uid": "page-ts-regular",
			"title": "Timestamped Regular",
			"create-time": \(createdTime),
			"edit-time": \(editedTime),
			"children": [{"uid": "b1", "string": "Block"}]
		}]
		"""

		let _ = try executeImport(from: json)
		let page = try requiredPage(title: "Timestamped Regular")

		expectNoDifference(page.createdAt, date(milliseconds: createdTime))
		expectNoDifference(page.updatedAt, date(milliseconds: editedTime))
	}

	@Test("Persists daily note timestamps on new import")
	func persistsDailyNoteTimestamps() throws {
		let createdTime = 1_710_000_000_000
		let editedTime = 1_710_000_123_000
		let json = """
		[{
			"uid": "01-18-2026",
			"title": "January 18th, 2026",
			"create-time": \(createdTime),
			"edit-time": \(editedTime),
			"children": [{"uid": "b1", "string": "Daily block"}]
		}]
		"""

		let _ = try executeImport(from: json)
		let page = try requiredPage(day: DayOfYear(day: 18, month: 1, year: 2026))

		expectNoDifference(page.createdAt, date(milliseconds: createdTime))
		expectNoDifference(page.updatedAt, date(milliseconds: editedTime))
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

		#expect(result.imported.count == 1)
		#expect(result.imported[0].id == existingPage.id)

		let children = try children(of: existingPage.id)
		#expect(children.count == 2)
		#expect(children[0].string == "Original block")
		#expect(children[1].string == "New block")
	}

	@Test("Replaces existing page content")
	func replaceExisting() throws {
		let existingPage = try #require(database.write { db in
			try Page.insert { Page(title: "Replace Me") }.returning(\.self).fetchOne(db)
		})
		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Old block", parentId: existingPage.id, pageId: existingPage.id, order: 0)
			}.execute(db)
		}

		let json = """
		[{"uid": "p1", "title": "Replace Me", "children": [{"uid": "b1", "string": "Replacement"}]}]
		"""

		let result = try executeImport(from: json) { pages in
			pages[0].resolution = .replace
		}

		#expect(result.imported.count == 1)
		let children = try children(of: existingPage.id)
		#expect(children.count == 1)
		#expect(children[0].string == "Replacement")
	}

	@Test("Keeps existing page timestamps on replace conflicts")
	func keepsExistingPageTimestampsOnReplace() throws {
		let originalCreatedAt = Date(timeIntervalSince1970: 100)
		let originalUpdatedAt = Date(timeIntervalSince1970: 200)

		let existingPage = try #require(database.write { db in
			try Page.insert {
				Page(title: "Timestamp Conflict", createdAt: originalCreatedAt, updatedAt: originalUpdatedAt)
			}.returning(\.self).fetchOne(db)
		})
		try database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Old block", parentId: existingPage.id, pageId: existingPage.id, order: 0)
			}.execute(db)
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

		let _ = try executeImport(from: json) { pages in
			pages[0].resolution = .replace
		}

		let page = try requiredPage(title: "Timestamp Conflict")
		expectNoDifference(page.createdAt, originalCreatedAt)
		expectNoDifference(page.updatedAt, originalUpdatedAt)
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

	@Test("Preserves heading and text alignment")
	func preservesBlockProperties() throws {
		let json = """
		[{
			"uid": "p1",
			"title": "Properties",
			"children": [
				{"uid": "h1", "string": "Heading", "heading": 2, "text-align": "right"}
			]
		}]
		"""

		let result = try executeImport(from: json)
		#expect(result.imported.count == 1)

		let page = try requiredPage(title: "Properties")
		let block = try firstParagraph(in: page.id)
		#expect(block.heading == .h2)
		#expect(block.textAlign == .right)
	}
}

// MARK: - Helpers

extension Tests.RoamImporterTest {
	private func importer(from json: String) throws -> RoamImporter {
		try RoamImporter(url: writeJSON(json))
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
			try Page.where { $0.title.eq(title) }.fetchOne(db)
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

	private func date(milliseconds: Int) -> Date {
		Date(timeIntervalSince1970: Double(milliseconds) / 1000)
	}

	private func writeJSON(_ json: String) throws -> URL {
		let url = URL.temporaryDirectory.appending(path: "\(UUID()).json")
		try json.write(to: url, atomically: true, encoding: .utf8)
		return url
	}
}
