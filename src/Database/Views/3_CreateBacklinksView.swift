import SQLiteData

final class CreateBacklinksView: DatabaseView {
	static func create(in db: Database) throws {
		let joined = Reference
			.join(Block.all) { $0.sourceBlockId == $1.id }
			.leftJoin(Page.all) { $1.pageId == $2.id }

		let selection = joined
			.select { reference, block, page in
				Backlink.Columns(
					fromBlock: reference.sourceBlockId,
					toBlock: reference.targetBlockId,
					kind: reference.kind,
					sourceText: block.string,
					fromPageTitle: page.title,
					fromPageId: page.id
				)
			}

		try Backlink.createTemporaryView(
			as: selection
		).execute(db)
	}
}
