import SQLiteData

final class CreateBacklinksView: DatabaseView {
	private enum TargetPage: AliasName {}
	private enum TargetParagraph: AliasName {}

	static func create(in db: Database) throws {
		func sources(for kinds: [Reference.Kind]) -> SelectOf<Reference, Paragraph, Page> {
			Reference.where { $0.kind.in(kinds) }
				.join(Paragraph.all) { $0.sourceBlockId.eq($1.id) }
				.join(Page.all) { $1.pageId.eq($2.id) }
		}

		let pages = sources(for: [.pageLink, .tag])
			.join(Page.as(TargetPage.self).all) { reference, _, _, targetPage in
				targetPage.id.eq(Page.where {
					$0.dailyNoteDate.eq(reference.targetKey.cast(as: DayOfYear.self)) || ($0.dailyNoteDate.is(nil) && $0.title.eq(reference.targetKey))
				}
				.select { $0.id.min().unsafelyUnwrapped })
			}
			.select { reference, paragraph, page, targetPage in
				Backlink.Columns(
					fromBlock: reference.sourceBlockId,
					toBlock: targetPage.id,
					kind: reference.kind,
					sourceText: paragraph.string,
					fromPageTitle: page.title,
					fromPageId: page.id
				)
			}

		let paragraphs = sources(for: [.blockRef, .blockEmbed])
			.join(Paragraph.as(TargetParagraph.self).all) { references, _, _, targets in
				targets.id.eq(#sql("\(references.targetKey)", as: Paragraph.ID.self))
			}
			.select { references, paragraphs, pages, targets in
				Backlink.Columns(
					fromBlock: references.sourceBlockId,
					toBlock: targets.id,
					kind: references.kind,
					sourceText: paragraphs.string,
					fromPageTitle: pages.title,
					fromPageId: pages.id
				)
			}

		try Backlink.createTemporaryView(as: pages.union(all: true, paragraphs)).execute(db)
	}
}
