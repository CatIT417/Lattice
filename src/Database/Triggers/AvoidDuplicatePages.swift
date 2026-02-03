import SQLiteData

final class AvoidDuplicatePages: Trigger {
	static var uses: [any ScalarDatabaseFunction] {
		[$unifyPagesWithSameTitle]
	}

	static func install(in db: Database) throws {
		try Block.createTemporaryTrigger(after: .insert(forEachRow: { page in
			Values($unifyPagesWithSameTitle(title: page.title.unsafelyUnwrapped))
		}, when: { block in
			block.title.isNot(nil) && Page.where { $0.title == block.title && $0.id != block.id }.exists()
		})).execute(db)

		try Block.createTemporaryTrigger(after: .update(forEachRow: { _, page in
			Values($unifyPagesWithSameTitle(title: page.title.unsafelyUnwrapped))
		}, when: { _, block in
			block.title.isNot(nil) && Page.where { $0.title == block.title && $0.id != block.id }.exists()
		})).execute(db)
	}
}

@DatabaseFunction(isDeterministic: false)
func unifyPagesWithSameTitle(title: String) throws {
	Task {
		@Dependency(\.defaultDatabase) var database

		withErrorReporting {
			try database.write { db in
				var pages = try Page.where { $0.title == title }.order { $0.createdAt.asc() }.fetchAll(db)
				guard pages.count > 1 else { return }

				let keeper = pages.removeFirst()

				for duplicatePage in pages {
					let affectedRecords = try Paragraph.where { $0.pageId.eq(duplicatePage.id) || $0.parentId.eq(duplicatePage.id) }.fetchAll(db)

					for block in affectedRecords {
						try Block.find(block.id).update {
							$0.pageId = keeper.id

							if block.parentId == duplicatePage.id {
								$0.parentId = keeper.id
							}
						}.execute(db)
					}

					try Page.find(duplicatePage.id).delete().execute(db)
				}
			}
		}
	}
}
