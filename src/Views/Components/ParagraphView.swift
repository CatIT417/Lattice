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
					.alignmentGuide(.firstTextBaseline) { _ in
						CTFontGetXHeight(font)
					}
				}

				EditableText(
					blockId: paragraph.id,
					text: paragraph.string,
					onSave: saveChanges,
					onReturn: createNewBlock,
					tryDeleteBlock: mergeIntoPrevious(appendingContent:)
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

		withErrorReporting {
			try database.write { db in
				try Paragraph
					.where { $0.parentId == paragraph.parentId && $0.order > paragraph.order }
					.update { $0.order += 1 }
					.execute(db)

				try Paragraph.insert {
					Paragraph(
						id: newBlockId,
						string: text ?? "",
						parentId: paragraph.parentId,
						pageId: paragraph.pageId,
						order: paragraph.order + 1,
						viewType: paragraph.viewType
					)
				}.execute(db)
			}
		}

		blockCoordinator?.request(for: newBlockId, at: 0, startingInMode: .raw)
	}

	private func mergeIntoPrevious(appendingContent content: String) -> Bool {
		guard let previousParagraphID = blockTree?.previousBlock(for: paragraph), let previousParagraph = withErrorReporting(catching: {
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

				// Reindex subsequent siblings (TODO: move to trigger)
				try Paragraph
					.where { $0.parentId == paragraph.parentId && $0.order > paragraph.order }
					.update { $0.order -= 1 }
					.execute(db)
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
