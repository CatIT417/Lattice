import SQLiteData
import Foundation

/// Links between blocks (the [[wiki links]] and ((block refs)))
@Table
struct Backlink: Equatable, Hashable, Sendable {
	var fromBlock: Block.ID
	var toBlock: Block.ID
	var kind: Reference.Kind
	var sourceText: String?
	var fromPageTitle: String?
	var fromPageId: Page.ID?
}
