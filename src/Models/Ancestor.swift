import SQLiteData

@Table("blockAncestors")
struct Ancestor: Equatable, Hashable, Sendable {
	var blockId: Block.ID
	var ancestorId: Block.ID
	var depth: Int
}
