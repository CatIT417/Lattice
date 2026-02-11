import Testing
import SQLiteData
import Foundation

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/SafetyChecks")
	struct SafetyChecksTest {
		@Dependency(\.defaultDatabase) var database

		let page: Page
		let otherPage: Page

		init() throws {
			(page, otherPage) = try _database.wrappedValue.write { db in
				let firstPage = try #require(try Page.insert { Page(title: "Test Page") }.returning(\.self).fetchOne(db))
				let secondPage = try #require(try Page.insert { Page(title: "Other Page") }.returning(\.self).fetchOne(db))

				return (firstPage, secondPage)
			}
		}
	}
}

extension Tests.SafetyChecksTest {
	@Test("Updating pageId without parentId on a root Paragraph fails")
	func updatingPageIdWithoutParentIdFails() throws {
		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Root Paragraph", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		#expect(throws: DatabaseError.self) {
			try database.write { db in
				try Block.find(paragraph.id).update { $0.pageId = otherPage.id }.execute(db)
			}
		}
	}

	@Test("Updating parentId without pageId on a root Paragraph fails")
	func updatingParentIdWithoutPageIdFails() throws {
		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Root Paragraph", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		#expect(throws: DatabaseError.self) {
			try database.write { db in
				try Block.find(paragraph.id).update { $0.parentId = otherPage.id }.execute(db)
			}
		}
	}

	@Test("Updating parentId to another Paragraph doesn't fail")
	func canUpdateParentIdToNonRootBlock() throws {
		let (parent, child) = try database.write { db in
			let parent = try #require(try Paragraph.insert {
				Paragraph(string: "Parent Paragraph", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			let child = try #require(try Paragraph.insert {
				Paragraph(string: "Child Paragraph", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))

			return (parent, child)
		}

		try database.write { db in
			try Block.find(child.id).update { $0.parentId = parent.id }.execute(db)
		}
	}

	@Test("Updating pageId and parentId together succeeds")
	func updatingPageIdAndParentIdTogetherSucceeds() throws {
		let paragraph = try #require(database.write { db in
			try Paragraph.insert {
				Paragraph(string: "Root Paragraph", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db)
		})

		try database.write { db in
			try Block.find(paragraph.id).update {
				$0.pageId = otherPage.id
				$0.parentId = otherPage.id
			}.execute(db)
		}

		let updated = try #require(database.read { db in
			try Block.find(paragraph.id).fetchOne(db)
		})

		#expect(updated.pageId == otherPage.id)
		#expect(updated.parentId == otherPage.id)
	}
}
