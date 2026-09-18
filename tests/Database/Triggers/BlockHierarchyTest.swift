import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport

@testable import LatticeDev

extension Tests {
	@Suite("Database/BlockHierarchy", .dependencies { try $0.bootstrapDatabase() })
	struct BlockHierarchyTest {
		@Dependency(\.defaultDatabase) var database

		@Test("A late parent resolves the entire subtree")
		func lateParent() throws {
			try database.write { db in
				let page = Block(title: "Page")
				let parent = Block(string: "Parent", parentId: page.id)
				let child = Paragraph(string: "Child", parentId: parent.id, pageId: page.id, order: 0)
				try Paragraph.insert { child }.execute(db)
				let storedChild = try Block.find(child.id).fetchOne(db)
				#expect(try BlockHierarchy.find(child.id).fetchOne(db)?.pageId == nil)
				#expect(try Paragraph.fetchCount(db) == 0)
				try Block.insert { [page, parent] }.execute(db)
				expectNoDifference(try Paragraph.find(child.id).fetchOne(db)?.pageId, page.id)
				expectNoDifference(try Ancestor.where { $0.blockId.eq(child.id) }.order(by: \.depth).fetchAll(db), [
					Ancestor(blockId: child.id, ancestorId: parent.id, depth: 1),
					Ancestor(blockId: child.id, ancestorId: page.id, depth: 2),
				])
				let tree = try #require(try Page.withChildren(id: page.id).fetch(db)?.tree)
				expectNoDifference(tree.children(of: parent.id).map(\.id), [child.id])
				expectNoDifference(try Block.find(child.id).fetchOne(db), storedChild)
			}
		}

		@Test("A move out of a deleted page survives in either operation order", arguments: [false, true])
		func moveAndDelete(deleteFirst: Bool) throws {
			try database.write { db in
				let page = Block(title: "Deleted page")
				let destination = Block(title: "Destination")
				let target = Block(title: "Target")
				let parent = Block(string: "Parent", parentId: page.id)
				let child = Block(string: "[[Target]]", parentId: parent.id)
				let stays = Block(string: "[[Target]]", parentId: page.id)
				try Block.insert { [page, destination, target, parent, child, stays] }.execute(db)
				let storedChild = try Block.find(child.id).fetchOne(db)
				let storedStays = try Block.find(stays.id).fetchOne(db)
				if deleteFirst {
					try Page.find(page.id).delete().execute(db)
					#expect(try Backlink.fetchCount(db) == 0)
				}
				try Block.find(parent.id).update { $0.parentId = #bind(destination.id) }.execute(db)
				if !deleteFirst { try Page.find(page.id).delete().execute(db) }
				#expect(try Paragraph.find(parent.id).fetchOne(db)?.pageId == destination.id)
				#expect(try Paragraph.find(child.id).fetchOne(db)?.pageId == destination.id)
				#expect(try Paragraph.find(stays.id).fetchOne(db) == nil)
				expectNoDifference(try Block.find(child.id).fetchOne(db), storedChild)
				expectNoDifference(try Block.find(stays.id).fetchOne(db), storedStays)
				#expect(try Backlink.fetchCount(db) == 1)
				#expect(try Backlink.fetchOne(db)?.fromPageId == destination.id)
			}
		}

		@Test("Restoring a page retains a child's explicit deletion marker")
		func restoreDoesNotClearChildDeletion() throws {
			try database.write { db in
				let page = Block(title: "Page")
				let first = Block(string: "First", parentId: page.id)
				let second = Block(string: "Second", parentId: page.id)
				try Block.insert { [page, first, second] }.execute(db)
				try Paragraph.find(first.id).delete().execute(db)
				try Page.find(page.id).delete().execute(db)
				try Block.find(page.id).update { $0.deletedAt = #bind(Date?.none) }.execute(db)
				expectNoDifference(try Paragraph.fetchAll(db).map(\.id), [second.id])
				#expect(try Block.find(first.id).fetchOne(db)?.deletedAt != nil)
			}
		}

		@Test("A redirect resolves late children before maintenance moves them")
		func lateRedirectChild() throws {
			try database.write { db in
				let page = Block(id: UUID(100), title: "Page")
				let loser = Block(id: UUID(101), title: "Page")
				try Block.insert { [page, loser] }.execute(db)
				try MergeDuplicatePages.run(in: db)
				let child = Block(string: "Late child", parentId: loser.id)
				try Block.insert { child }.execute(db)
				#expect(try Paragraph.find(child.id).fetchOne(db)?.pageId == page.id)
				#expect(try Paragraph.find(child.id).fetchOne(db)?.parentId == page.id)
				#expect(try Block.find(child.id).fetchOne(db)?.parentId == loser.id)
				#expect(try MergeDuplicatePages.hasPendingWork(in: db))
				try MergeDuplicatePages.run(in: db)
				#expect(try Block.find(child.id).fetchOne(db)?.parentId == page.id)
				#expect(try !MergeDuplicatePages.hasPendingWork(in: db))
				let before = try Block.order(by: \.id).fetchAll(db)
				let changes = db.totalChangesCount
				try MergeDuplicatePages.run(in: db)
				#expect(db.totalChangesCount == changes)
				expectNoDifference(try Block.order(by: \.id).fetchAll(db), before)
			}
		}

		@Test("A local edit can use a child whose redirect has not been moved yet")
		func editBeforeRedirectMaintenance() throws {
			try database.write { db in
				let page = Block(title: "Page")
				let alias = Block(title: "Page", mergedInto: page.id)
				let first = Block(string: "First", parentId: page.id, order: 0)
				let late = Block(string: "Late", parentId: alias.id, order: ParagraphOrder.gap)
				try Block.insert { [page, alias, first, late] }.execute(db)
				expectNoDifference(try Breadcrumb.forBlock(id: late.id).fetchAll(db).map(\.id), [page.id])
			}
		}

		@Test("Physical parent deletion hides retained children until the parent returns")
		func physicalParentDeletion() throws {
			try database.write { db in
				let page = Block(title: "Page")
				let parent = Block(string: "Parent", parentId: page.id)
				let child = Block(string: "[[Page]]", parentId: parent.id)
				try Block.insert { [page, parent, child] }.execute(db)
				let keys = try Reference.fetchAll(db)
				try Block.find(parent.id).delete().execute(db)
				#expect(try Block.find(child.id).fetchOne(db) != nil)
				#expect(try BlockHierarchy.find(parent.id).fetchOne(db) == nil)
				#expect(try BlockHierarchy.find(child.id).fetchOne(db)?.pageId == nil)
				#expect(try Backlink.fetchCount(db) == 0)
				try Block.insert { parent }.execute(db)
				#expect(try Paragraph.find(child.id).fetchOne(db)?.pageId == page.id)
				#expect(try Backlink.fetchCount(db) == 1)
				expectNoDifference(try Reference.fetchAll(db), keys)
			}
		}

		@Test("A late redirect target resolves children and references to those children")
		func redirectChain() throws {
			try database.write { db in
				let target = Block(title: "Target")
				let middle = Block(title: "Middle", mergedInto: target.id)
				let alias = Block(title: "Alias", mergedInto: middle.id)
				let host = Block(title: "Source")
				let child = Block(string: "Child", parentId: alias.id)
				let source = Block(string: "((\(child.id)))", parentId: host.id)
				try Block.insert { [host, source, child, alias, middle] }.execute(db)
				#expect(try Paragraph.find(child.id).fetchOne(db) == nil)
				#expect(try Backlink.fetchCount(db) == 0)
				let keys = try Reference.fetchAll(db)
				try Block.insert { target }.execute(db)
				#expect(try Paragraph.find(child.id).fetchOne(db)?.pageId == target.id)
				#expect(try Backlink.fetchOne(db)?.toBlock == child.id)
				#expect(try Page.withChildren(id: alias.id).fetch(db)?.block.id == target.id)
				try Page.find(target.id).delete().execute(db)
				try MergeDuplicatePages.run(in: db)
				#expect(try Paragraph.find(child.id).fetchOne(db) == nil)
				#expect(try Page.withChildren(id: alias.id).fetch(db) == nil)
				#expect(try Backlink.fetchCount(db) == 0)
				expectNoDifference(try Reference.fetchAll(db), keys)
			}
		}

		@Test("A deletion marker on an intermediate redirect hides its children")
		func deletedRedirect() throws {
			try database.write { db in
				let page = Block(title: "Page")
				let middle = Block(title: "Middle", deletedAt: Date(timeIntervalSince1970: 500), mergedInto: page.id)
				let alias = Block(title: "Alias", mergedInto: middle.id)
				let child = Block(string: "Hidden child", parentId: alias.id)
				let visible = Block(string: "Visible child", parentId: page.id)
				try Block.insert { [child, alias, middle, page, visible] }.execute(db)
				expectNoDifference(try BlockHierarchy.find(child.id).fetchOne(db),
					BlockHierarchy(blockId: child.id, pageId: page.id, isVisible: false))
				expectNoDifference(try Paragraph.fetchAll(db).map(\.id), [visible.id])
				let before = try BlockHierarchy.order(by: \.blockId).fetchAll(db)
				try SyncAncestorsTable().rebuildAncestorsForSubtree(blockId: page.id)
				expectNoDifference(try BlockHierarchy.order(by: \.blockId).fetchAll(db), before)
				try Block.find(middle.id).update { $0.deletedAt = #bind(Date?.none) }.execute(db)
				expectNoDifference(try BlockHierarchy.find(child.id).fetchOne(db),
					BlockHierarchy(blockId: child.id, pageId: page.id, isVisible: true))
			}
		}

		@Test("Cycles with deletion markers remain unresolved", arguments: [false, true])
		func cyclesRemainUnresolved(redirects: Bool) throws {
			try database.write { db in
				let first = Block(
					id: UUID(100), string: redirects ? nil : "First", title: redirects ? "First" : nil,
					parentId: redirects ? nil : UUID(101), deletedAt: Date(timeIntervalSince1970: 500),
					mergedInto: redirects ? UUID(101) : nil
				)
				let second = Block(
					id: UUID(101), string: redirects ? nil : "Second", title: redirects ? "Second" : nil,
					parentId: redirects ? nil : first.id, mergedInto: redirects ? first.id : nil
				)
				let child = Block(string: "Child", parentId: second.id)
				try Block.insert { [child, first, second] }.execute(db)
				let expected = [child, first, second]
					.map { BlockHierarchy(blockId: $0.id, pageId: nil, isVisible: false) }
					.sorted { $0.blockId.uuidString < $1.blockId.uuidString }
				expectNoDifference(try BlockHierarchy.order(by: \.blockId).fetchAll(db), expected)
				try SyncAncestorsTable().rebuildAncestorsForSubtree(blockId: first.id)
				expectNoDifference(try BlockHierarchy.order(by: \.blockId).fetchAll(db), expected)
				#expect(try Paragraph.fetchCount(db) == 0)
			}
		}

		@Test("A failed hierarchy write rolls back the primary mutation")
		func indexFailureRollsBackWrite() throws {
			try database.write { db in
				let page = Block(title: "Page")
				try Block.insert { page }.execute(db)
				let before = try Block.order(by: \.id).fetchAll(db)
				let hierarchy = try BlockHierarchy.order(by: \.blockId).fetchAll(db)
				try BlockHierarchy.createTemporaryTrigger(before: .insert(forEachRow: { _ in
					Select(#sql("RAISE(ABORT, 'Injected hierarchy failure')"))
				}, when: { new in
					Block.where { $0.id.eq(new.blockId) && $0.deletedAt.isNot(nil) }.exists()
				})).execute(db)
				do {
					try Block.find(page.id).update { $0.deletedAt = #bind(Date(timeIntervalSince1970: 500)) }.execute(db)
					Issue.record("The hierarchy write must fail.")
				} catch let error as DatabaseError {
					#expect(error.message?.contains("Injected hierarchy failure") == true)
				}
				expectNoDifference(try Block.order(by: \.id).fetchAll(db), before)
				expectNoDifference(try BlockHierarchy.order(by: \.blockId).fetchAll(db), hierarchy)
			}
		}

		@Test("A cache rebuild does not change primary rows or their timestamps")
		func rebuildIsLocal() throws {
			try database.write { db in
				let page = Block(title: "Page")
				let child = Block(string: "Child", parentId: page.id)
				try Block.insert { [page, child] }.execute(db)
				let before = try Block.order(by: \.id).fetchAll(db)
				let hierarchy = try BlockHierarchy.order(by: \.blockId).fetchAll(db)
				let ancestors = try Ancestor.order { ($0.blockId, $0.depth) }.fetchAll(db)
				let metadata = try SyncMetadata.order(by: \.recordPrimaryKey).fetchAll(db)
				#expect(metadata.count == 2)
				try SyncAncestorsTable().rebuildAncestorsForSubtree(blockId: page.id)
				try SyncAncestorsTable().rebuildAncestorsForSubtree(blockId: page.id)
				expectNoDifference(try Block.order(by: \.id).fetchAll(db), before)
				expectNoDifference(try BlockHierarchy.order(by: \.blockId).fetchAll(db), hierarchy)
				expectNoDifference(try Ancestor.order { ($0.blockId, $0.depth) }.fetchAll(db), ancestors)
				expectNoDifference(try SyncMetadata.order(by: \.recordPrimaryKey).fetchAll(db), metadata)
			}
		}
	}
}
