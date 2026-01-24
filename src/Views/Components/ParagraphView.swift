import SwiftUI
import SQLiteData
import Dependencies

struct ParagraphView: View {
	var paragraph: Paragraph

	@Environment(\.blockTree) var blockTree
	@Dependency(\.defaultDatabase) var database
	@Environment(\.blockCoordinator) var blockCoordinator
	@Environment(\.fontResolutionContext) var fontContext

	var fontForHeading: Font {
		switch paragraph.heading {
			case .h1: .title
			case .h2: .title2
			case .h3: .title3
			case .none: .body
		}
	}

	var body: some View {
		let font = fontForHeading.resolve(in: fontContext).ctFont

		VStack(alignment: .leading, spacing: 4) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				if paragraph.viewType != .document {
					NavigationButton(push: .paragraph(id: paragraph.id)) {
						bulletView
					}
					.buttonStyle(.plain)
					.alignmentGuide(.firstTextBaseline) { _ in
						CTFontGetXHeight(font)
					}
					#if os(macOS)
					.pointerStyle(.link)
					#endif
				}

				EditableText(
					blockId: paragraph.id,
					text: paragraph.string,
					onSave: saveChanges,
					onReturn: createNewBlock(withText:),
					tryDeleteBlock: mergeIntoPrevious(appendingContent:),
					onMoveUp: moveToPreviousBlock(fromCursorPosition:),
					onMoveDown: moveToNextBlock(fromCursorPosition:)
				)
				.font(fontForHeading)
				.frame(minHeight: CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font), alignment: .topLeading)
			}

			ChildrenRenderer(parentID: paragraph.id)
		}
	}

	private func saveChanges(_ newText: String) {
		withErrorReporting {
			try database.write { db in
				try Paragraph.find(paragraph.id)
					.update { $0.string = newText }
					.execute(db)
			}
		}
	}

	private func createNewBlock(withText text: String? = nil) {
		let newBlockId = UUID()

		let isRootParagraph = blockTree.isRoot(paragraph.id)

		// IF we press return on an empty block with no children,
		// AND the parent is not at the top level in the current page,
		// THEN we move it up a level instead of creating a new block.
		if paragraph.string.isEmpty, text?.isEmpty ?? true, !isRootParagraph, !paragraph.parentIsPage, !blockTree.isRoot(paragraph.parentId) {
			return outdentBlock()
		}

		withErrorReporting {
			try database.write { db in
				try Paragraph.insert {
					Paragraph(
						id: newBlockId,
						string: text ?? "",
						parentId: isRootParagraph ? paragraph.id : paragraph.parentId,
						pageId: paragraph.pageId,
						order: isRootParagraph ? 0 : paragraph.order + 1,
						viewType: paragraph.viewType
					)
				}.execute(db)
			}
		}

		blockCoordinator?.request(for: newBlockId, at: 0, startingInMode: .raw)
	}

	private func outdentBlock() {
		withErrorReporting {
			try database.write { db in
				guard let parentBlock = try Paragraph.find(paragraph.parentId).fetchOne(db) else {
					return
				}

				try Paragraph.find(paragraph.id)
					.update {
						$0.parentId = parentBlock.parentId
						$0.order = parentBlock.order + 1
					}
					.execute(db)
			}
		}

		// Keep focus on same block
		blockCoordinator?.request(for: paragraph.id, at: 0, startingInMode: .raw)
	}

	private func mergeIntoPrevious(appendingContent content: String) -> Bool {
		guard !blockTree.hasChildren(paragraph.id), let previousParagraphID = blockTree.previousBlockOnScreen(for: paragraph), let previousParagraph = withErrorReporting(catching: {
			try database.read { db in
				try Paragraph.find(previousParagraphID).fetchOne(db)
			}
		}) else { return false }

		withErrorReporting {
			try database.write { db in
				try Paragraph.find(previousParagraphID)
					.update { $0.string += content }
					.execute(db)

				try Paragraph.find(paragraph.id).delete().execute(db)
			}
		}

		blockCoordinator?.request(
			for: previousParagraphID,
			at: previousParagraph.string.count,
			expectsNewText: true,
			startingInMode: .raw
		)

		return true
	}

	private func moveToPreviousBlock(fromCursorPosition position: Int) -> Bool {
		guard let previousBlockId = blockTree.previousBlockOnScreen(for: paragraph), let previousParagraph = withErrorReporting(catching: {
			try database.read { db in
				try Paragraph.find(previousBlockId).fetchOne(db)
			}
		}) else { return false }

		blockCoordinator?.request(
			for: previousBlockId,
			at: position >= paragraph.string.count ? previousParagraph.string.count : min(position, previousParagraph.string.count),
			startingInMode: .raw
		)
		return true
	}

	private func moveToNextBlock(fromCursorPosition position: Int) -> Bool {
		guard let nextBlockId = blockTree.nextBlockOnScreen(for: paragraph), let nextParagraph = withErrorReporting(catching: {
			try database.read { db in
				try Paragraph.find(nextBlockId).fetchOne(db)
			}
		}) else { return false }

		blockCoordinator?.request(
			for: nextBlockId,
			at: position >= paragraph.string.count ? nextParagraph.string.count : min(position, nextParagraph.string.count),
			startingInMode: .raw
		)
		return true
	}

	@ViewBuilder private var bulletView: some View {
		switch paragraph.viewType {
			case .bullet:
				Circle()
					.fill(Color.primary)
					.frame(width: 6, height: 6)
			case .numbered:
				Text("\(paragraph.order + 1).")
					.foregroundStyle(.secondary)
			case .document: EmptyView()
		}
	}
}

#Preview {
	let paragraph = previewData { try Paragraph.fetchOne($0) }

	ParagraphView(paragraph: paragraph!)
		.preview()
}

#Preview("Empty") {
	let paragraph = previewData { try Paragraph.fetchOne($0) }

	ParagraphView(paragraph: Paragraph(string: "", parentId: paragraph!.id, pageId: paragraph!.pageId, order: 0))
		.preview()
}
