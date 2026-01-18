import SQLiteData

@Selection
struct Breadcrumb: Identifiable {
	let id: Block.ID
	let title: String?
	let string: String?

	var text: String {
		if let title { return title }
		if let string { return string }

		fatalError("Blocks are either pages or paragraphs")
	}

	var page: Destination.Pages {
		switch (title, string) {
			case (.some, .none): .page(id: id)
			case (.none, .some): .paragraph(id: id)
			default: fatalError("Blocks are either pages or paragraphs")
		}
	}

	static func forBlock(id: Block.ID) -> Select<Breadcrumb, Ancestor, Block> {
		Ancestor
			.where { $0.blockId == id }
			.order { $0.depth.desc() }
			.join(Block.all) { $0.ancestorId.eq($1.id) }
			.select { Breadcrumb.Columns(id: $1.id, title: $1.title, string: $1.string) }
			.asSelect()
	}
}
