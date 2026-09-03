import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Triggers/CleanupDerivedRows", .dependencies { try $0.bootstrapDatabase() })
	struct CleanupDerivedRowsTest {
		@Dependency(\.defaultDatabase) var database
	}
}

extension Tests.CleanupDerivedRowsTest {
	@Test("Deleting a block removes its ancestor rows and its references in both directions")
	func deletingBlockRemovesDerivedRows() throws {
		let (target, source) = try database.write { db in
			let page = try #require(try Page.insert { Page(title: "Cleanup Root") }.returning(\.self).fetchOne(db))
			let target = try #require(try Paragraph.insert {
				Paragraph(string: "Target", parentId: page.id, pageId: page.id, order: 0)
			}.returning(\.self).fetchOne(db))
			let source = try #require(try Paragraph.insert {
				Paragraph(string: "See ((\(target.id.uuidString))) on [[Cleanup Root]]", parentId: page.id, pageId: page.id, order: 1)
			}.returning(\.self).fetchOne(db))

			return (target, source)
		}

		let referencesBefore = try database.read { db in
			try Reference.where { $0.sourceBlockId.eq(source.id) }.fetchCount(db)
		}
		expectNoDifference(referencesBefore, 2)

		try database.write { db in
			try Paragraph.find(target.id).delete().execute(db)
		}

		let (targetAncestors, referencesToTarget, referencesFromSource) = try database.read { db in
			(
				try Ancestor.where { $0.blockId.eq(target.id) || $0.ancestorId.eq(target.id) }.fetchCount(db),
				try Reference.where { $0.targetBlockId.eq(target.id) }.fetchCount(db),
				try Reference.where { $0.sourceBlockId.eq(source.id) }.fetchCount(db)
			)
		}
		expectNoDifference(targetAncestors, 0)
		expectNoDifference(referencesToTarget, 0)
		expectNoDifference(referencesFromSource, 1)

		try database.write { db in
			try Paragraph.find(source.id).delete().execute(db)
		}

		let referencesAfter = try database.read { db in
			try Reference.where { $0.sourceBlockId.eq(source.id) }.fetchCount(db)
		}
		expectNoDifference(referencesAfter, 0)
	}
}
