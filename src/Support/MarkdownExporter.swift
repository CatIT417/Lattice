import SQLiteData

enum MarkdownExporter {
	static func exportPage(id: Page.ID) throws -> String {
		@Dependency(\.defaultDatabase) var database

		guard let result = try database.read({ db in
			try Page.withChildren(id: id).fetchOne(db)
		}) else { return "" }

		var lines: [String] = ["# \(result.block.title)", ""]
		renderChildren(of: result.block.id, tree: result.tree, depth: 0, into: &lines)

		return lines.joined(separator: "\n")
	}

	static func exportParagraph(id: Paragraph.ID) throws -> String {
		@Dependency(\.defaultDatabase) var database

		guard let result = try database.read({ db in
			try Paragraph.withChildren(id: id).fetchOne(db)
		}) else { return "" }

		var lines: [String] = []
		renderParagraph(result.block, depth: 0, into: &lines)
		renderChildren(of: result.block.id, tree: result.tree, depth: 1, into: &lines)

		return lines.joined(separator: "\n")
	}

	static func exportSelection(_ blockIDs: Set<Block.ID>) throws -> String {
		guard !blockIDs.isEmpty else { return "" }

		let paragraphs = try Paragraph.fetchInOrder(blockIDs)
		let tree = BlockTree(paragraphs: paragraphs)

		var lines: [String] = []
		for root in paragraphs where !blockIDs.contains(root.parentId) {
			renderParagraph(root, depth: 0, into: &lines)
			renderChildren(of: root.id, tree: tree, depth: 1, into: &lines)
		}

		return lines.joined(separator: "\n")
	}
}

// MARK: - Private

private extension MarkdownExporter {
	static func renderChildren(of parentId: Block.ID, tree: BlockTree, depth: Int, into lines: inout [String]) {
		for child in tree.children(of: parentId) {
			renderParagraph(child, depth: depth, into: &lines)
			renderChildren(of: child.id, tree: tree, depth: depth + 1, into: &lines)
		}
	}

	static func renderParagraph(_ paragraph: Paragraph, depth: Int, into lines: inout [String]) {
		let indent = String(repeating: "\t", count: depth)

		let prefix = switch paragraph.viewType {
			case .bullet: "- "
			case .document: ""
			case .numbered: "1. "
		}

		let headingMarker = switch paragraph.heading {
			case .h1: "# "
			case .h2: "## "
			case .h3: "### "
			case .none: ""
		}

		lines.append("\(indent)\(prefix)\(headingMarker)\(paragraph.string)")
	}
}
