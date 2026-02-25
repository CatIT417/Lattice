import SQLiteData

@Table
struct BlockText: FTS5 {
	let blockID: Block.ID
	let title: String?
	let string: String?
}
