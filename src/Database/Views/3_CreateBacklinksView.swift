import SQLiteData

final class CreateBacklinksView: DatabaseView {
	static func create(in db: Database) throws {
		let joined = Reference
			.join(Paragraph.all) { $0.sourceBlockId.eq($1.id) }
			.join(Page.all) { $1.pageId.eq($2.id) }

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
