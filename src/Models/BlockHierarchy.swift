import Foundation
import SQLiteData

@Table("blockHierarchy")
struct BlockHierarchy: Equatable, Sendable {
	@Column(primaryKey: true) let blockId: Block.ID
	var pageId: Page.ID?
	var isVisible: Bool
}
