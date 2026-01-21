import SwiftUI
import SQLiteData
import Dependencies

struct ParagraphView: View {
	var paragraph: Paragraph

	@Dependency(\.defaultDatabase) var database
	@Environment(\.focusCoordinator) var focusCoordinator
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
					onSave: { newText in saveChanges(newText) },
					onReturn: createNewBlock
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

		focusCoordinator?.requestFocus(for: newBlockId)
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
