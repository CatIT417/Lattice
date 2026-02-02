import SwiftUI
import SQLiteData

struct PlaceholderBlock: View {
	var pageId: Page.ID

	@Dependency(\.uuid) var uuid
	@Dependency(\.defaultDatabase) var database
	@Environment(\.blockCoordinator) var blockCoordinator
	@Environment(\.fontResolutionContext) var fontContext

	var body: some View {
		let font = Font.body.resolve(in: fontContext).ctFont

		Button(action: createFirstBlock) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Circle()
					.fill(Color.primary)
					.frame(width: 6, height: 6)
					.alignmentGuide(.firstTextBaseline) { [xHeight = CTFontGetXHeight(font)] _ in
						xHeight
					}

				Text("Tap here to start typing")
					.font(.body)
					.foregroundStyle(.secondary)
				#if os(macOS)
					.pointerStyle(.horizontalText)
				#endif
			}
		}
		.buttonStyle(.plain)
		.foregroundStyle(.primary)
	}

	private func createFirstBlock() {
		let newBlockId = withErrorReporting {
			try database.write { db in
				try Paragraph.insert {
					Paragraph(
						string: "",
						parentId: pageId,
						pageId: pageId,
						order: 0
					)
				}.returning(\.id).fetchOne(db)
			}
		}

		blockCoordinator?.request(for: newBlockId, at: 0, startingInMode: .raw)
	}
}

#Preview {
	let page = previewData { try Page.fetchOne($0) }

	PlaceholderBlock(pageId: page!.id)
		.preview()
}
