import SwiftUI
import SQLiteData

struct ParagraphView: View {
	var paragraph: Paragraph

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

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				if paragraph.viewType != .document {
					bulletView
						.alignmentGuide(.firstTextBaseline) { _ in
							fontXHeight
						}
				}

				RenderText(text: paragraph.string)
					.font(fontForHeading)
			}

			ChildrenRenderer(parentID: paragraph.id)
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
