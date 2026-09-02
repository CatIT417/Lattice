import Testing
import SQLiteData
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Models/Backlink", .dependencies { try $0.bootstrapDatabase() })
	struct BacklinkTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.BacklinkTest {
	@Test("Unlinked reference count matches the grouped query")
	func unlinkedReferenceCountMatchesGroupedQuery() throws {
		let target = Page(title: "Target Page")
		let firstSource = Page(title: "First Source")
		let secondSource = Page(title: "Second Source")

		try database.write { db in
			try Page.insert {
				target
				firstSource
				secondSource
			}.execute(db)

			try Paragraph.insert {
				Paragraph(string: "A plain Target Page mention", parentId: firstSource.id, pageId: firstSource.id, order: 0)
				Paragraph(string: "A linked [[Target Page]] mention", parentId: firstSource.id, pageId: firstSource.id, order: 1)
				Paragraph(string: "[[Notes About Target Page]]", parentId: firstSource.id, pageId: firstSource.id, order: 2)
				Paragraph(string: "Another Target Page mention", parentId: secondSource.id, pageId: secondSource.id, order: 0)
				Paragraph(string: "Target Page on itself", parentId: target.id, pageId: target.id, order: 0)
			}.execute(db)
		}

		let groupedReferences = try database.read { db in
			try Backlink.unlinkedReferences(forPage: target.id, title: target.title).fetchAll(db)
		}
		let count = try database.read { db in
			try Backlink.unlinkedReferenceCount(forPage: target.id, title: target.title).fetchOne(db)
		}

		#expect(count == 2)
		#expect(count == groupedReferences.backlinkCount)
	}
}
