import Foundation
import SQLiteData

final class SeedDatabase: Seeder {
	static func seed() -> Records {
		seedDailies()
		seedQuickStart()
	}

	@SeedsBuilder private static func seedDailies() -> Records {
		let firstDaily = Page.createDailyNote(for: try! Date("1/1/2024 1:12AM", strategy: .dateTime))

		firstDaily
		Paragraph(string: "This is my first daily note! 🎉", parentId: firstDaily.id, pageId: firstDaily.id, order: 0)

		let currentDaily = Page.createDailyNote(for: Date())

		currentDaily
		Paragraph(string: "See the [[Lattice Quick Start]] page to get started!", parentId: currentDaily.id, pageId: currentDaily.id, order: 0)
	}

	@SeedsBuilder private static func seedQuickStart() -> Records {
		let page = Page(title: "Lattice Quick Start")

		page

		buildParagraphs([
			"What is Lattice?": [
				"Lattice is a tool for thinking, heavily inspired by [[Roam Research]]": [:],
				#"Unlike other "Roam Clones", every bullet is a block"#: [
					"It can be linked to, referenced, embed, etc.": [:],
					"This is my favourite part of Roam, and I can't believe everyone else just left it for Markdown": [:],
				],
				"You can install Lattice on your iPhone, iPad, or Mac": [
					"all your data seamlessly syncs using iCloud": [:],
					"at the same time, the app works fully offline, so you can jot down ideas anywhere, anytime (and they'll sync back once you're back online)": [:],
				],
				"Lattice is a native app, built with Swift, using [[UITextView]]/[[NSTextView]]": [
					"It's also open-source, and you can check out the code on [GitHub](https://github.com/m1guelpf/Lattice)": [:],
				],
			],
			"How Lattice works": [
				"Like I mentioned before, every bullet is a block": [
					"You can infinitely nest blocks inside other blocks": [:],
					"Click the bullet to the left of a block to navigate into it": [:],
					"You can also embed blocks inside other blocks to reference them (but we'll get to that later)": [:],
				],
				"Blocks can include references to [[Pages]] using `[[this syntax]]`.": [
					"Pages track all references to them across your entire database": [
						"This makes it easy to build a web of interconnected ideas, track common themes, etc.": [:],
					],
					#"You can also style them as #tags to make their "tagging" nature more obvious"#: [:],
				],
			],
			"Mastering Lattice": [
				"Press `Return` to create a new block after the current one": [:],
				"Press `Delete` at the start of a block to join it with the previous one": [:],
				"todo: add the rest of the shortcuts here": [:],
			],
			"More soon!": [
				#"Lattice is under active development, so you can expect many more features soon, as it slowly morphs into a proper "second brain""#: [:],
				"If this excites you, hit me up! [@m1guelpf](https://twitter.com/m1guelpf) on Twitter.": [:],
			],
		], parentId: page.id, pageId: page.id)
	}
}

fileprivate func buildParagraphs(_ tree: [String: Any], parentId: Block.ID, pageId: Page.ID) -> [any Table] {
	var records = [any Table]()

	for (order, (content, children)) in tree.enumerated() {
		let paragraph = Paragraph(string: content, parentId: parentId, pageId: pageId, order: order)
		records.append(paragraph)

		if let children = children as? [String: Any] {
			records.append(contentsOf: buildParagraphs(children, parentId: paragraph.id, pageId: pageId))
		}
	}

	return records
}
