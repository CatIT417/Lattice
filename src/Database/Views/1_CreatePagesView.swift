import SQLiteData

final class CreatePagesView: DatabaseView {
	static func create(in db: Database) throws {
		try Page.createTemporaryView(
			as: Block.where { $0.isPage }.select {
				Page.Columns(
					id: $0.id,
					title: $0.title.unsafelyUnwrapped,
					dailyNoteDate: $0.dailyNoteDate,
					props: $0.props,
					createdAt: $0.createdAt,
					updatedAt: $0.updatedAt
				)
			}
		).execute(db)
	}
}
