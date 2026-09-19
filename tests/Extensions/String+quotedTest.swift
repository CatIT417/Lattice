import Testing
import Foundation
import CustomDump
import SQLiteData

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/String+quoted")
	struct StringQuotedTest {
		@Test("FTS queries treat quotes and operators as literal input", arguments: [
			("Quantum Mechanics", "Quantum alone"),
			("say \"hello\"", "say goodbye"),
			("alpha OR omega", "alpha alone"),
			("alpha NOT omega", "alpha alone"),
			("alpha:omega", "alpha alone"),
			(" \n\t ", "Other text"),
		])
		func quotedSearch(input: String, other: String) throws {
			let database = try makeDatabase()
			try database.write { db in
				try CreateBlocksTable.up(db)
				try CreateBlocksFTSTables.up(db)
				let match = Block(id: UUID(100), title: input)
				try Block.insert { [match, Block(id: UUID(101), title: other)] }.execute(db)
				try RebuildSearchIndex.populate(in: db)
				expectNoDifference(try BlockText.where { $0.match(input.quoted()) }.select(\.blockID).fetchAll(db), input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [match.id])
			}
		}
	}
}
