import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/Migrations/LocalGraphIndexes", .dependencies { try $0.bootstrapDatabase() })
	struct LocalGraphMigrationTest {
		@Dependency(\.defaultDatabase) var database

		@Test("A fresh database indexes blocks before their parents and targets arrive")
		func freshDatabase() throws {
			try database.write { db in
				#expect(try db.indexes(on: "blocks").contains { $0.columns == ["parentId", "order", "id"] })
				expectNoDifference(try db.columns(in: "blockReferences").map(\.name), ["sourceBlockId", "kind", "targetKey"])
				expectNoDifference(try db.primaryKey("blockReferences").columns, ["sourceBlockId", "kind", "targetKey"])
				#expect(try db.indexes(on: "blockReferences").contains { $0.columns == ["kind", "targetKey", "sourceBlockId"] })

				let page = Block(id: UUID(100), title: "Source")
				let target = Block(id: UUID(101), title: "Target")
				let lateTarget = Block(id: UUID(102), string: "Late target", parentId: target.id)
				let child = Block(id: UUID(103), string: "[[Target]] [[Target]] #Target ((\(lateTarget.id)))", parentId: page.id, order: -8)
				try Block.insert { [target, child] }.execute(db)
				let storedChild = try Block.find(child.id).fetchOne(db)
				let references = try Reference.fetchAll(db)
				#expect(references.count == 3)
				#expect(try Block.fetchCount(db) == 2)
				#expect(try BlockHierarchy.find(child.id).fetchOne(db)?.pageId == nil)
				#expect(try Backlink.fetchCount(db) == 0)

				try Block.insert { page }.execute(db)
				#expect(try Paragraph.find(child.id).fetchOne(db)?.pageId == page.id)
				#expect(try Ancestor.where { $0.blockId.eq(child.id) }.fetchCount(db) == 1)
				#expect(try Backlink.fetchCount(db) == 2)

				try Block.insert { lateTarget }.execute(db)
				#expect(try Backlink.fetchCount(db) == 3)
				expectNoDifference(try Block.find(child.id).fetchOne(db), storedChild)
				expectNoDifference(Set(try Reference.fetchAll(db)), Set(references))
			}
		}
	}
}
