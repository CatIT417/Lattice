import SQLiteData

final class AvoidDuplicatePages: Trigger {
	static var uses: [any ScalarDatabaseFunction] {
		[$moveBlocksToExistingPage]
	}

	static func install(in db: Database) throws {
		// TODO: Revise this to make sure there are no edge cases with syncronization
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { page in
			Values($moveBlocksToExistingPage(title: page.title.unsafelyUnwrapped, id: page.id))
		}, when: { block in
			block.title.isNot(nil) && Page.where { $0.title == block.title && $0.id != block.id }.exists()
		})).execute(db)
	}
}

@DatabaseFunction
func moveBlocksToExistingPage(title: String, id: Block.ID) throws {
	Task {
		@Dependency(\.defaultDatabase) var database

		withErrorReporting {
			try database.write { db in
				guard let existingPage = try Page.where({ $0.title == title && $0.id != id }).fetchOne(db) else { return }

				let affectedRecords = try Paragraph.where { $0.pageId.eq(id) || $0.parentId.eq(id) }.fetchAll(db)
				guard !affectedRecords.isEmpty else { return }

				for block in affectedRecords {
					try Paragraph.find(block.id).update {
						$0.pageId = existingPage.id

						if block.parentId == id {
							$0.parentId = existingPage.id
						}
					}.execute(db)
				}

				try Page.find(id).delete().execute(db)
			}
		}
	}
}
