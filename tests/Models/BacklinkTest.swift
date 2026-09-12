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
	@Test("Block references and embeds resolve only visible paragraphs", arguments: [Reference.Kind.blockRef, .blockEmbed])
	func paragraphTargetsOnly(kind: Reference.Kind) throws {
		try database.write { db in
			let page = Block(title: "Target Page")
			let alias = Block(title: "Alias", mergedInto: page.id)
			let target = Block(string: "Target", parentId: page.id)
			let source = Block(string: "((\(target.id))) ((\(page.id))) ((\(alias.id)))", parentId: page.id)
			try Block.insert { [page, alias, target, source] }.execute(db)
			try Reference.update { $0.kind = #bind(kind) }.execute(db)
			let keys = try Reference.fetchAll(db)
			#expect(keys.count == 3)
			#expect(try Backlink.select(\.toBlock).fetchAll(db) == [target.id])
			try Paragraph.find(target.id).delete().execute(db)
			#expect(try Backlink.fetchCount(db) == 0)
			#expect(Set(try Reference.fetchAll(db)) == Set(keys))
		}
	}

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
