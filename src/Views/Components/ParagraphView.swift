import SwiftUI
import SQLiteData
import Dependencies

struct ParagraphView: View {
	var paragraph: Paragraph

	@State private var isHovering = false

	@Dependency(\.uuid) var uuid
	@Dependency(\.platform) var platform
	@Environment(\.blockTree) var blockTree
	@Environment(\.rootBlockID) var rootBlockID
	@Dependency(\.defaultDatabase) var database
	@Dependency(\.blockCoordinator) var blockCoordinator
	@Environment(\.fontResolutionContext) var fontContext
	#if os(iOS)
	@Dependency(\.blockSelectionCoordinator) var selectionCoordinator
	#endif

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
				NavigationButton(push: .paragraph(id: paragraph.id)) {
					ParagraphBullet(paragraph: paragraph)
				}
				.buttonStyle(.plain)
				.alignmentGuide(.firstTextBaseline) { [xHeight = CTFontGetXHeight(font)] _ in
					xHeight
				}
				.overlay(alignment: .leadingFirstTextBaseline) {
					if platform.hasPointer, blockTree.hasChildren(paragraph.id), paragraph.id != rootBlockID {
						Button(action: toggleIsOpen) {
							Image(systemName: "triangle.fill")
								.resizable()
								.frame(width: 8, height: 8)
								.rotationEffect(.degrees(paragraph.isOpen ? 180 : 90))
						}
						.buttonStyle(.plain)
						.foregroundStyle(.primary)
						.animation(.easeOut(duration: 0.2)) {
							$0.opacity(isHovering ? 1 : 0)
						}
						.transition(.opacity)
						.offset(x: -16)
						.allowsHitTesting(isHovering)
						#if os(macOS)
							.pointerStyle(.link)
						#else
							.alignmentGuide(.firstTextBaseline) { [xHeight = CTFontGetXHeight(font)] _ in
								xHeight
							}
						#endif
					}
				}
				#if os(macOS)
				.pointerStyle(.link)
				.contextMenu { ParagraphMenu(paragraph: paragraph) }
				#endif

				if let todoState = paragraph.string.todoState, blockCoordinator.activelyEditingBlock != paragraph.id {
					Button(action: { toggleTodoState(todoState) }) {
						Image(systemName: todoState == .done ? "checkmark.square.fill" : "square")
							.foregroundStyle(.primary)
							.contentTransition(.symbolEffect(.replace))
					}
					#if os(macOS)
					.pointerStyle(.link)
					#else
					.hoverEffect(.lift)
					#endif
					.buttonStyle(.plain)
					.padding(.trailing, -4)
				}

				EditableText(
					blockId: paragraph.id,
					text: paragraph.string,
					alignment: paragraph.textAlign,
					handleAction: handleAction
				)
				.font(fontForHeading)
				.frame(maxWidth: .infinity, minHeight: CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font), alignment: .topLeading)

				if !paragraph.isOpen, paragraph.id != rootBlockID, !platform.hasPointer {
					Spacer(minLength: 2)

					Button(action: toggleIsOpen) {
						Image(systemName: "arrowtriangle.right.fill")
							.imageScale(.small)
					}
					.foregroundStyle(.primary)
					.transition(
						.asymmetric(
							insertion: .rotate(angle: .degrees(90)).combined(with: .opacity).animation(.easeOut(duration: 0.2)),
							removal: .rotate(angle: .degrees(90)).combined(with: .opacity).animation(.easeIn(duration: 0.2))
						)
					)
				}
			}
			.contentShape(Rectangle().inset(.leading, by: -15))
			.hovering($isHovering.animation())
			#if os(iOS)
				.padding(.horizontal, 10)
				.contextMenu { ParagraphMenu(paragraph: paragraph) }
				.background(
					RoundedRectangle(cornerRadius: 6)
						.fill(selectionCoordinator.isHighlighted(paragraph.id) ? Color.blue.opacity(0.2) : .clear)
				)
				.padding(.horizontal, -10)
				.onSwipeLeft {
					let descendantIDs = blockTree.descendantIDs(of: paragraph.id)
					withAnimation(selectionCoordinator.animation) {
						selectionCoordinator.handleSwipe(on: paragraph.id, descendantIDs: descendantIDs)
					}
				}
			#endif

			if paragraph.isOpen || paragraph.id == rootBlockID {
				ChildrenRenderer(parentID: paragraph.id, showIndentLine: true, onIndentLineTapped: toggleIsOpen)
			}
		}
	}

	private func handleAction(_ action: EditableText.Action) -> Bool {
		switch action {
			case let .textChanged(text): saveChanges(text)
			case let .indent(cursor, text): indentBlock(cursorPosition: cursor, currentText: text)
			case let .outdent(cursor, text): outdentBlock(cursorPosition: cursor, currentText: text)
			case let .blockBreak(currentText, remainingText): createNewBlock(currentText: currentText, withText: remainingText)
			case let .mergeIntoPrevious(content): mergeIntoPrevious(appendingContent: content)
			#if os(iOS)
			case let .moveBlock(delta, cursorPosition, text): changeOrder(cursorPosition: cursorPosition, delta: delta, currentText: text)
			#endif
			case let .moveCursorDown(visualX): moveToNextBlock(visualX: visualX)
			case let .moveCursorUp(visualX): moveToPreviousBlock(visualX: visualX)
		}
	}

	private func toggleTodoState(_ current: TodoState) {
		withErrorReporting {
			try database.write { db in
				try Block.find(paragraph.id)
					.update { $0.string = $0.string.withTodoState(current.toggled) }
					.execute(db)
			}
		}
	}

	private func saveChanges(_ newText: String) -> Bool {
		withErrorReporting {
			try database.write { db in
				try Block.find(paragraph.id)
					.update { $0.string = #bind(newText) }
					.execute(db)
			}
		}

		return true
	}

	private func toggleIsOpen() {
		withErrorReporting {
			try database.write { db in
				try Block.find(paragraph.id)
					.update { $0.isOpen = !$0.isOpen }
					.execute(db)
			}
		}
	}

	private func changeOrder(cursorPosition: Int, delta: Int, currentText: String) -> Bool {
		let siblings = blockTree.children(of: paragraph.parentId)
		guard paragraph.order + delta >= 0, paragraph.order + delta < siblings.count else {
			return false
		}

		withErrorReporting {
			try database.write { db in
				try Block.find(paragraph.id)
					.update {
						$0.order += delta

						if currentText != paragraph.string {
							$0.string = #bind(currentText)
						}
					}
					.execute(db)
			}
		}

		blockCoordinator.request(for: paragraph.id, at: cursorPosition, expectsNewText: currentText != paragraph.string, startingInMode: .raw)
		return true
	}

	/// Returns true if a new block was created, false if focus stays on this block (e.g., outdent)
	private func createNewBlock(currentText: String, withText text: String? = nil) -> Bool {
		let isRootParagraph = paragraph.id == rootBlockID

		// IF we press return on an empty block with no children,
		// AND the parent is not at the top level in the current page,
		// THEN we move it up a level instead of creating a new block.
		if currentText.isEmpty, text?.isEmpty ?? true, !isRootParagraph, !paragraph.parentIsPage, paragraph.parentId != rootBlockID {
			_ = outdentBlock()
			return false
		}

		let newBlockId = withErrorReporting {
			try database.write { db in
				try Paragraph.insert {
					Paragraph(
						string: text ?? "",
						parentId: isRootParagraph ? paragraph.id : paragraph.parentId,
						pageId: paragraph.pageId,
						order: isRootParagraph ? 0 : paragraph.order + 1,
						viewType: paragraph.viewType
					)
				}.returning(\.id).fetchOne(db)
			}
		}

		blockCoordinator.request(for: newBlockId, at: 0, startingInMode: .raw)
		return true
	}

	@discardableResult
	private func outdentBlock(cursorPosition: Int? = nil, currentText: String? = nil) -> Bool {
		guard paragraph.id != rootBlockID, !paragraph.parentIsPage, paragraph.parentId != rootBlockID else {
			return false
		}

		withErrorReporting {
			try database.write { db in
				guard let parentBlock = try Paragraph.find(paragraph.parentId).fetchOne(db) else {
					return
				}

				try Block.find(paragraph.id)
					.update {
						$0.order = parentBlock.order + 1
						$0.parentId = #bind(parentBlock.parentId)

						if let currentText, currentText != paragraph.string {
							$0.string = #bind(currentText)
						}
					}
					.execute(db)
			}
		}

		blockCoordinator.request(for: paragraph.id, at: cursorPosition ?? 0, expectsNewText: currentText != paragraph.string, startingInMode: .raw)
		return true
	}

	private func indentBlock(cursorPosition: Int, currentText: String) -> Bool {
		guard let previousSibling = blockTree.previousSibling(for: paragraph) else {
			return false
		}

		withErrorReporting {
			try database.write { db in
				let maxOrder = try Paragraph
					.where { $0.parentId.eq(previousSibling.id) }
					.order { $0.order.desc() }
					.fetchOne(db)?
					.order

				try Block.find(paragraph.id)
					.update {
						$0.order = (maxOrder ?? -1) + 1
						$0.parentId = #bind(previousSibling.id)

						if currentText != paragraph.string {
							$0.string = #bind(currentText)
						}
					}
					.execute(db)
			}
		}

		blockCoordinator.request(for: paragraph.id, at: cursorPosition, expectsNewText: currentText != paragraph.string, startingInMode: .raw)
		return true
	}

	private func mergeIntoPrevious(appendingContent content: String) -> Bool {
		if paragraph.heading != nil {
			clearHeading()
			return false
		}

		guard !blockTree.hasChildren(paragraph.id), let previousParagraphID = blockTree.previousBlockOnScreen(for: paragraph), let previousParagraph = withErrorReporting(catching: {
			try database.read { db in
				try Paragraph.find(previousParagraphID).fetchOne(db)
			}
		}) else { return false }

		withErrorReporting {
			try database.write { db in
				try Block.find(previousParagraphID)
					.update {
						$0.string = $0.string.map({ $0 + content.strippingTodoPrefix() }, or: content.strippingTodoPrefix()).asOptional
					}
					.execute(db)

				try Paragraph.find(paragraph.id).delete().execute(db)
			}
		}

		blockCoordinator.request(
			for: previousParagraphID,
			at: previousParagraph.string.utf16.count,
			expectsNewText: true,
			startingInMode: .raw
		)

		return true
	}

	private func clearHeading() {
		withErrorReporting {
			try database.write { db in
				try Block.find(paragraph.id)
					.update { $0.heading = #bind(nil) }
					.execute(db)
			}
		}
	}

	private func moveToPreviousBlock(visualX: CGFloat) -> Bool {
		guard let previousBlockId = blockTree.previousBlockOnScreen(for: paragraph) else { return false }

		if visualX == .infinity { blockCoordinator.request(for: previousBlockId, at: Int.max, startingInMode: .raw) }
		else if visualX == -.infinity { blockCoordinator.request(for: previousBlockId, at: 0, startingInMode: .raw) }
		else { blockCoordinator.request(for: previousBlockId, visualX: visualX, edge: .last, startingInMode: .raw) }

		return true
	}

	private func moveToNextBlock(visualX: CGFloat) -> Bool {
		guard let nextBlockId = blockTree.nextBlockOnScreen(for: paragraph) else { return false }

		if visualX == .infinity { blockCoordinator.request(for: nextBlockId, at: Int.max, startingInMode: .raw) }
		else if visualX == -.infinity { blockCoordinator.request(for: nextBlockId, at: 0, startingInMode: .raw) }
		else { blockCoordinator.request(for: nextBlockId, visualX: visualX, edge: .first, startingInMode: .raw) }

		return true
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
