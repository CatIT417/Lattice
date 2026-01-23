import SwiftUI
import SQLiteData

struct PlaceholderBlock: View {
	var pageId: Page.ID

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
					.alignmentGuide(.firstTextBaseline) { _ in
						CTFontGetXHeight(font)
					}

				Text("Tap here to start typing")
					.font(.body)
					.foregroundStyle(.secondary)
			}
		}
		.buttonStyle(.plain)
		.foregroundStyle(.primary)
	}

	private func createFirstBlock() {
		let newBlockId = UUID()

		withErrorReporting {
			try database.write { db in
				try Paragraph.insert {
					Paragraph(
						id: newBlockId,
						string: "",
						parentId: pageId,
						pageId: pageId,
						order: 0
					)
				}.execute(db)
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
