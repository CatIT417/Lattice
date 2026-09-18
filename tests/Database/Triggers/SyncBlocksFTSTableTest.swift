import Testing
import SQLiteData
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/SyncBlocksFTSTable", .dependencies { try $0.bootstrapDatabase() })
	struct SyncBlocksFTSTableTest {
		@Dependency(\.defaultDatabase) var database

		@Test("Page search follows insert, rename, and physical deletion")
		func pageSearchLifecycle() throws {
			try database.write { db in
				let page = Page(title: "Quantum Mechanics")
				try Page.insert { [page, Page(title: "Classical Physics")] }.execute(db)
				let initial = try #require(try BlockText.where { $0.blockID.eq(page.id) }.fetchOne(db))
				expectNoDifference(initial.canonicalTitle, "Quantum Mechanics")
				#expect(initial.string == nil)
				expectNoDifference(try BlockText.matching("Quantum").select(\.blockID).fetchAll(db), [page.id])

				try Block.find(page.id).update { $0.title = #bind("Relativity") }.execute(db)
				expectNoDifference(try BlockText.matching("Quantum").select(\.blockID).fetchAll(db), [])
				expectNoDifference(try BlockText.matching("Relativity").select(\.blockID).fetchAll(db), [page.id])

				try Block.find(page.id).delete().execute(db)
				#expect(try BlockText.where { $0.blockID.eq(page.id) }.fetchOne(db) == nil)
				expectNoDifference(try BlockText.matching("Relativity").select(\.blockID).fetchAll(db), [])
			}
		}

		@Test("Paragraph search follows insert and text replacement")
		func paragraphSearchLifecycle() throws {
			try database.write { db in
				let page = Page(title: "Notes")
				try Page.insert { page }.execute(db)
				let paragraph = Paragraph(string: "photosynthesis is fascinating", parentId: page.id, pageId: page.id, order: 0)
				try Paragraph.insert {
					paragraph
					Paragraph(string: "gravity pulls things down", parentId: page.id, pageId: page.id, order: 1)
				}.execute(db)
				let initial = try #require(try BlockText.where { $0.blockID.eq(paragraph.id) }.fetchOne(db))
				#expect(initial.canonicalTitle == nil)
				expectNoDifference(initial.string, paragraph.string)
				expectNoDifference(try BlockText.matching("photosynthesis").select(\.blockID).fetchAll(db), [paragraph.id])

				try Block.find(paragraph.id).update { $0.string = #bind("chlorophyll absorbs light") }.execute(db)
				expectNoDifference(try BlockText.matching("photosynthesis").select(\.blockID).fetchAll(db), [])
				expectNoDifference(try BlockText.matching("chlorophyll").select(\.blockID).fetchAll(db), [paragraph.id])
			}
		}
	}
}
