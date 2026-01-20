import SwiftUI
import SQLiteData
import Dependencies

struct ParagraphView: View {
	var paragraph: Paragraph

	@Dependency(\.defaultDatabase) var database
	@Environment(\.fontResolutionContext) var fontContext

	var fontForHeading: Font {
		switch paragraph.heading {
			case .h1: .title
			case .h2: .title2
			case .h3: .title3
			case .none: .body
		}
	}

	var fontXHeight: CGFloat {
		let font = fontForHeading.resolve(in: fontContext).ctFont

		return CTFontGetXHeight(font)
	}

	var fontLineHeight: CGFloat {
		let font = fontForHeading.resolve(in: fontContext).ctFont

		return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
	}

	var bulletAlignment: CGFloat {
		if !paragraph.string.isEmpty { return fontXHeight }
		return fontXHeight - (fontXHeight / 2)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				if paragraph.viewType != .document {
					NavigationButton(push: .paragraph(id: paragraph.id)) {
						bulletView
					}
					.alignmentGuide(.firstTextBaseline) { _ in
						bulletAlignment
					}
				}

				EditableText(
					text: paragraph.string,
					onSave: { newText in saveChanges(newText) },
					onReturn: createNewBlock
				)
				.font(fontForHeading)
				.frame(minHeight: fontLineHeight, alignment: .topLeading)
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

				for ref in newText.extractRefs() where ref.kind.isPage {
					let exists = try Page.where { $0.title == ref.target }.fetchOne(db) != nil
					if !exists {
						try Page.insert {
							Page(title: ref.target)
						}.execute(db)
					}
				}

				// TODO: Sync blockReferences table when text changes
			}
		}
	}

	private func createNewBlock(withText text: String? = nil) {
		print("Creating new block")

		withErrorReporting {
			try database.write { db in
				try Paragraph
					.where { $0.parentId == paragraph.parentId && $0.order > paragraph.order }
					.update { $0.order += 1 }
					.execute(db)

				try Paragraph.insert {
					Paragraph(
						string: text ?? "",
						parentId: paragraph.parentId,
						pageId: paragraph.pageId,
						order: paragraph.order + 1,
						viewType: paragraph.viewType
					)
				}.execute(db)
			}
		}
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
