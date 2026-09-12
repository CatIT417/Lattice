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

	@Selection
	fileprivate struct PathRow {
		let id: Block.ID
		let title: String?
		let string: String?
		let isPage: Bool
		let depth: Int
	}

	static func forBlock(id: Block.ID) -> some PartialSelectStatement<Breadcrumb> {
		let page = BlockHierarchy
			.where { $0.blockId.eq(id) && $0.isVisible }
			.join(Page.all) { $0.pageId.eq($1.id) }
			.select { _, pages in
				PathRow.Columns(id: pages.id, title: pages.title.asOptional, string: String?.none, isPage: true, depth: 0)
			}
		let parents = Ancestor
			.where { $0.blockId.eq(id) }
			.join(Paragraph.all) { $0.ancestorId.eq($1.id) }
			.select { ancestors, paragraphs in
				PathRow.Columns(id: paragraphs.id, title: String?.none, string: paragraphs.string.asOptional, isPage: false, depth: ancestors.depth)
			}
		return With {
			page.union(all: true, parents)
		} query: {
			PathRow
				.order { ($0.isPage.desc(), $0.depth.desc()) }
				.select { Breadcrumb.Columns(id: $0.id, title: $0.title, string: $0.string) }
		}
	}
}
