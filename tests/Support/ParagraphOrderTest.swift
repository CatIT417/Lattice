import Testing
import SQLiteData
import Foundation
import CustomDump
import DependenciesTestSupport
import SQLite3

@testable import LatticeDev

extension Tests {
	@Suite("Support/ParagraphOrder", .dependencies { try $0.bootstrapDatabase() })
	struct ParagraphOrderTest {
		@Dependency(\.defaultDatabase) var database

		@Test("Adjacent rank reads stay bounded as a sibling group grows", arguments: [false, true])
		func boundedRankReads(withRedirect: Bool) throws {
			try database.write { db in
				let page = Block(id: UUID(1), title: "Page")
				let alias = Block(id: UUID(2), title: "Page", mergedInto: page.id)
				try Block.insert { [page] + (withRedirect ? [alias] : []) }.execute(db)
				let rows = (0 ..< 512).map { index in
					Block(id: UUID(100 + index), string: String(repeating: "Text ", count: 100),
						parentId: withRedirect && index.isMultiple(of: 2) ? alias.id : page.id,
						order: index * ParagraphOrder.gap)
				}
				func readSteps() throws -> Int {
					var steps = 0
					try withUnsafeMutablePointer(to: &steps) { counter in
						sqlite3_progress_handler(db.sqliteConnection, 1, { context in
							context!.assumingMemoryBound(to: Int.self).pointee += 1
							return 0
						}, counter)
						defer { sqlite3_progress_handler(db.sqliteConnection, 0, nil, nil) }
						_ = try ParagraphOrder(parentId: page.id, in: db).appendRanks(count: 512, in: db)
						_ = try ParagraphOrder(parentId: page.id, in: db).rank(in: db)
						_ = try ParagraphOrder(parentId: page.id, in: db).rank(before: rows[16].id, in: db)
						_ = try ParagraphOrder(parentId: page.id, in: db).rank(after: rows[16].id, in: db)
					}
					return steps
				}
				try Block.insert { Array(rows.prefix(32)) }.execute(db)
				let small = try readSteps()
				try Block.insert { Array(rows.dropFirst(32)) }.execute(db)
				let large = try readSteps()
				#expect(large < small * 3)
				#expect(try ParagraphOrder(parentId: page.id, in: db).rank(in: db) == 512 * ParagraphOrder.gap)
			}
		}

		@Test("Insertion at either end stays bounded when siblings share a rank", arguments: [false, true])
		func boundedEqualRankInsertion(withRedirect: Bool) throws {
			try database.write { db in
				let page = Block(id: UUID(1), title: "Page")
				let alias = Block(id: UUID(2), title: "Page", mergedInto: page.id)
				try Block.insert { [page] + (withRedirect ? [alias] : []) }.execute(db)
				let rows = (0 ..< 512).map { index in
					Block(id: UUID(100 + index), string: "Text",
						parentId: withRedirect && index.isMultiple(of: 2) ? alias.id : page.id, order: 0)
				}
				func readSteps(count: Int) throws -> Int {
					var steps = 0
					try withUnsafeMutablePointer(to: &steps) { counter in
						sqlite3_progress_handler(db.sqliteConnection, 1, { context in
							context!.assumingMemoryBound(to: Int.self).pointee += 1
							return 0
						}, counter)
						defer { sqlite3_progress_handler(db.sqliteConnection, 0, nil, nil) }
						for anchor in [nil, rows[count - 1].id] {
							let rank = try ParagraphOrder(parentId: page.id, in: db).rank(after: anchor, in: db)
							expectNoDifference(rank, anchor == nil ? -ParagraphOrder.gap : ParagraphOrder.gap)
						}
					}
					return steps
				}
				try Block.insert { Array(rows.prefix(32)) }.execute(db)
				let small = try readSteps(count: 32)
				try Block.insert { Array(rows.dropFirst(32)) }.execute(db)
				let large = try readSteps(count: 512)
				#expect(large < small * 3)
			}
		}

		@Test("Batch append keeps hidden and redirect children before the new rows",
			arguments: [nil, 4 * ParagraphOrder.gap, Int.max - ParagraphOrder.gap, Int.max] as [Int?])
		func batchAppend(lastRank: Int?) throws {
			try database.write { db in
				let page = Block(id: UUID(1), title: "Page")
				guard let lastRank else {
					try Block.insert { page }.execute(db)
					let ordering = try ParagraphOrder(parentId: page.id, in: db)
					expectNoDifference(try ordering.appendRanks(count: 0, in: db), [])
					let ranks = try ordering.appendRanks(count: 3, in: db)
					expectNoDifference(ranks.count, 3)
					#expect(zip(ranks, ranks.dropFirst()).allSatisfy { $0 < $1 })
					return
				}
				let alias = Block(id: UUID(2), title: "Page", mergedInto: page.id)
				let first = Block(id: UUID(100), string: "First", parentId: page.id, order: lastRank - ParagraphOrder.gap)
				let hidden = Block(id: UUID(101), string: "Hidden", parentId: alias.id, order: lastRank, deletedAt: Date(timeIntervalSince1970: 100))
				try Block.insert { [page, alias, first, hidden] }.execute(db)
				let ranks = try ParagraphOrder(parentId: page.id, in: db).appendRanks(count: 3, in: db)
				let added = ranks.enumerated().map {
					Block(id: UUID(200 + $0.offset), string: "New", parentId: page.id, order: $0.element)
				}
				try Block.insert { added }.execute(db)
				expectNoDifference(try Block.where(\.isParagraph).order { ($0.order, $0.id) }.select(\.id).fetchAll(db),
					[first.id, hidden.id] + added.map(\.id))
				#expect(zip(ranks, ranks.dropFirst()).allSatisfy { $0 < $1 })
				#expect(try Block.find(hidden.id).fetchOne(db)?.deletedAt == hidden.deletedAt)
				#expect(try Block.find(hidden.id).fetchOne(db)?.parentId == alias.id)
				if lastRank == 4 * ParagraphOrder.gap {
					#expect(try Block.find(first.id).fetchOne(db)?.order == first.order)
					#expect(try Block.find(hidden.id).fetchOne(db)?.order == hidden.order)
				}
			}
		}

		@Test("Reordering skips hidden siblings and includes redirect children")
		func adjacentVisibleSiblings() throws {
			try database.write { db in
				let page = Block(id: UUID(1), title: "Page")
				let alias = Block(id: UUID(2), title: "Page", mergedInto: page.id)
				let first = Block(id: UUID(100), string: "First", parentId: page.id, order: 0)
				let hidden = Block(id: UUID(101), string: "Hidden", parentId: page.id, order: 0, deletedAt: Date())
				let second = Block(id: UUID(102), string: "Second", parentId: alias.id, order: 0)
				let last = Block(id: UUID(103), string: "Last", parentId: page.id, order: ParagraphOrder.gap)
				try Block.insert { [page, alias, first, hidden, second, last] }.execute(db)
				#expect(try ParagraphOrder.move(first.id, direction: .down, in: db))
				expectNoDifference(try Paragraph.order { ($0.order, $0.id) }.select(\.id).fetchAll(db), [second.id, first.id, last.id])
				#expect(try ParagraphOrder.move(last.id, direction: .up, in: db))
				#expect(try ParagraphOrder.move(last.id, direction: .up, in: db))
				expectNoDifference(try Paragraph.order { ($0.order, $0.id) }.select(\.id).fetchAll(db), [last.id, second.id, first.id])
				#expect(try Block.find(hidden.id).fetchOne(db)?.deletedAt != nil)
				#expect(try !ParagraphOrder.move(last.id, direction: .up, in: db))
				#expect(try !ParagraphOrder.move(first.id, direction: .down, in: db))
			}
		}

		@Test("Rank repair retains hidden rows and excludes the moving row")
		func repairWithHiddenSiblings() throws {
			try database.write { db in
				let page = Block(title: "Page")
				let hidden = Block(id: UUID(100), string: "Hidden", parentId: page.id, order: 0, deletedAt: Date())
				let first = Block(id: UUID(101), string: "First", parentId: page.id, order: 0)
				let moving = Block(id: UUID(102), string: "Moving", parentId: page.id, order: 0)
				try Block.insert { [page, hidden, first, moving] }.execute(db)
				let ordering = try ParagraphOrder(parentId: page.id, in: db)
				let rank = try ordering.rank(before: first.id, excluding: moving.id, in: db)
				try Block.find(moving.id).update { $0.order = #bind(rank) }.execute(db)
				expectNoDifference(try Block.where { $0.parentId.eq(page.id) }.order { ($0.order, $0.id) }.select(\.id).fetchAll(db), [hidden.id, moving.id, first.id])
				#expect(try Paragraph.find(hidden.id).fetchOne(db) == nil)
			}
		}

		@Test("The lower block can move above another block with the same rank", arguments: [2, 3])
		func moveEqualRanks(count: Int) throws {
			try database.write { db in
				let page = Block(title: "Page")
				let siblings = (0 ..< count).map { Block(id: UUID(100 + $0), string: "\($0)", parentId: page.id, order: 0) }
				try Block.insert { [page] + siblings }.execute(db)
				#expect(try ParagraphOrder.move(siblings.last!.id, direction: .up, in: db))
				var expected = siblings.map(\.id)
				expected.swapAt(count - 1, count - 2)
				expectNoDifference(try Paragraph.order { ($0.order, $0.id) }.fetchAll(db).map(\.id), expected)
			}
		}

		@Test("Insert after a visible sibling retains hidden and redirect children", arguments: [0, 1, 2])
		func insertAfter(slot: Int) throws {
			try database.write { db in
				let page = Block(id: UUID(1), title: "Page")
				let alias = Block(id: UUID(2), title: "Page", mergedInto: page.id)
				let hiddenFirst = Block(id: UUID(100), string: "Hidden first", parentId: page.id, order: 0, deletedAt: Date())
				let first = Block(id: UUID(101), string: "First", parentId: page.id, order: 0)
				let hiddenMiddle = Block(id: UUID(102), string: "Hidden middle", parentId: alias.id, order: 0, deletedAt: Date())
				let second = Block(id: UUID(103), string: "Second", parentId: alias.id, order: 0)
				let hiddenLast = Block(id: UUID(104), string: "Hidden last", parentId: page.id, order: ParagraphOrder.gap, deletedAt: Date())
				try Block.insert { [page, alias, hiddenFirst, first, hiddenMiddle, second, hiddenLast] }.execute(db)
				let ordering = try ParagraphOrder(parentId: page.id, in: db)
				let anchor = [nil, first.id, second.id][slot]
				let rank = try ordering.rank(after: anchor, in: db)
				let inserted = Block(id: UUID(200), string: "Inserted", parentId: page.id, order: rank)
				try Block.insert { inserted }.execute(db)

				var expected = [hiddenFirst.id, first.id, hiddenMiddle.id, second.id, hiddenLast.id]
				expected.insert(inserted.id, at: [1, 3, 5][slot])
				expectNoDifference(try Block.where(\.isParagraph).order { ($0.order, $0.id) }.select(\.id).fetchAll(db), expected)
				#expect(try Paragraph.count().fetchOne(db) == 3)
				#expect(try Block.find(hiddenMiddle.id).fetchOne(db)?.parentId == alias.id)
			}
		}

		@Test("Outdent allocates a rank after the parent in its displayed sibling group")
		func outdentAfterParent() throws {
			try database.write { db in
				let page = Block(id: UUID(1), title: "Page")
				let alias = Block(id: UUID(2), title: "Page", mergedInto: page.id)
				let parent = Block(id: UUID(100), string: "Parent", parentId: alias.id, order: 0)
				let next = Block(id: UUID(101), string: "Next", parentId: page.id, order: 0)
				let child = Block(id: UUID(102), string: "Child", parentId: parent.id, order: 0)
				try Block.insert { [page, alias, parent, next, child] }.execute(db)
				let ordering = try ParagraphOrder(parentId: page.id, in: db)
				let rank = try ordering.rank(after: parent.id, excluding: child.id, in: db)
				try Block.find(child.id).update {
					$0.parentId = #bind(page.id)
					$0.order = #bind(rank)
				}.execute(db)
				expectNoDifference(try Paragraph.where { $0.parentId.eq(page.id) }.order { ($0.order, $0.id) }.select(\.id).fetchAll(db),
					[parent.id, child.id, next.id])
			}
		}

		@Test("Ranks handle both integer limits without overflow")
		func integerLimits() throws {
			#expect(ParagraphOrder.between(Int.min, Int.max) == -1)
			#expect(ParagraphOrder.between(Int.max, nil) == nil)
			#expect(ParagraphOrder.between(nil, Int.min) == nil)
			#expect(ParagraphOrder.between(2, 2) == nil)
			#expect(ParagraphOrder.between(2, 3) == nil)
			try database.write { db in
				let page = Block(title: "Page")
				let first = Block(string: "First", parentId: page.id, order: Int.min)
				let last = Block(string: "Last", parentId: page.id, order: Int.max)
				try Block.insert { [page, first, last] }.execute(db)
				let order = try ParagraphOrder(parentId: page.id, in: db).rank(in: db)
				let appended = Block(string: "Appended", parentId: page.id, order: order)
				try Block.insert { appended }.execute(db)
				expectNoDifference(try Paragraph.order { ($0.order, $0.id) }.fetchAll(db).map(\.id), [first.id, last.id, appended.id])
			}
		}

		@Test("Repeated insertions preserve the requested sequence after rank repair")
		func repeatedInsertions() throws {
			try database.write { db in
				let page = Block(title: "Page")
				try Block.insert { page }.execute(db)
				var expected: [Block.ID] = []
				for index in 0 ..< 150 {
					let slot = index < 80 ? 0 : (index * 37) % (expected.count + 1)
					let anchor = slot < expected.count ? expected[slot] : nil
					let order = try ParagraphOrder(parentId: page.id, in: db).rank(before: anchor, in: db)
					let block = Block(string: "\(index)", parentId: page.id, order: order)
					try Block.insert { block }.execute(db)
					expected.insert(block.id, at: slot)
					expectNoDifference(try Paragraph.order { ($0.order, $0.id) }.fetchAll(db).map(\.id), expected)
				}
			}
		}
	}
}
