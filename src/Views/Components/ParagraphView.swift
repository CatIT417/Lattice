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
					handleAction: handleAction
				)
				.font(fontForHeading)
				.frame(minHeight: CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font), alignment: .topLeading)
			}

			ChildrenRenderer(parentID: paragraph.id)
		}
	}

	private func handleAction(_ action: EditableText.Action) -> Bool {
		switch action {
			case let .textChanged(text): saveChanges(text)
			case let .indent(cursor): indentBlock(cursorPosition: cursor)
			case let .outdent(cursor): outdentBlock(cursorPosition: cursor)
			case let .blockBreak(remainingText): createNewBlock(withText: remainingText)
			case let .mergeIntoPrevious(content): mergeIntoPrevious(appendingContent: content)
			#if os(iOS)
			case let .moveBlock(delta, cursorPosition): changeOrder(cursorPosition: cursorPosition, delta: delta)
			#elseif os(macOS)
			case let .moveCursorDown(cursor): moveToNextBlock(fromCursorPosition: cursor)
			case let .moveCursorUp(cursor): moveToPreviousBlock(fromCursorPosition: cursor)
			#endif
		}
	}

	private func saveChanges(_ newText: String) -> Bool {
		withErrorReporting {
			try database.write { db in
				try Paragraph.find(paragraph.id)
					.update { $0.string = newText }
					.execute(db)
			}
		}

		return true
	}

	private func changeOrder(cursorPosition: Int, delta: Int) -> Bool {
		let siblings = blockTree.children(of: paragraph.parentId)
		guard paragraph.order + delta >= 0, paragraph.order + delta < siblings.count else {
			return false
		}

		withErrorReporting {
			try database.write { db in
				try Paragraph.find(paragraph.id)
					.update { $0.order += delta }
					.execute(db)
			}
		}

		blockCoordinator?.request(for: paragraph.id, at: cursorPosition, startingInMode: .raw)
		return true
	}

	/// Returns true if a new block was created, false if focus stays on this block (e.g., outdent)
	private func createNewBlock(withText text: String? = nil) -> Bool {
		let isRootParagraph = blockTree.isRoot(paragraph.id)

		// IF we press return on an empty block with no children,
		// AND the parent is not at the top level in the current page,
		// THEN we move it up a level instead of creating a new block.
		if paragraph.string.isEmpty, text?.isEmpty ?? true, !isRootParagraph, !paragraph.parentIsPage, !blockTree.isRoot(paragraph.parentId) {
			_ = outdentBlock()
			return false
		}

		let newBlockId = UUID()

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
		return true
	}

	@discardableResult
	private func outdentBlock(cursorPosition: Int? = nil) -> Bool {
		guard !blockTree.isRoot(paragraph.id), !paragraph.parentIsPage, !blockTree.isRoot(paragraph.parentId) else {
			return false
		}

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

		blockCoordinator?.request(for: paragraph.id, at: cursorPosition ?? 0, startingInMode: .raw)
		return true
	}

	private func indentBlock(cursorPosition: Int) -> Bool {
		guard let previousSibling = blockTree.previousSibling(for: paragraph) else {
			return false
		}

		let maxOrder = withErrorReporting(catching: {
			try database.read { db in
				try Paragraph
					.where { $0.parentId == previousSibling.id }
					.order { $0.order.desc() }
					.fetchOne(db)?
					.order
			}
		}) ?? nil

		withErrorReporting {
			try database.write { db in
				try Paragraph.find(paragraph.id)
					.update {
						$0.parentId = previousSibling.id
						$0.order = (maxOrder ?? -1) + 1
					}
					.execute(db)
			}
		}

		blockCoordinator?.request(for: paragraph.id, at: cursorPosition, startingInMode: .raw)
		return true
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
