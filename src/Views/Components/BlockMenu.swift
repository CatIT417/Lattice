import SwiftUI
import SQLiteData

struct ParagraphMenu: View {
	var paragraph: Paragraph

	init(paragraph: Paragraph) {
		self.paragraph = paragraph
		_blockHeading = State(initialValue: paragraph.heading)
		_blockAlignment = State(initialValue: paragraph.textAlign)
	}

	@State private var blockHeading: Block.HeadingLevel?
	@State private var blockAlignment: Block.TextAlignment

	@Environment(Router.self) var router
	@Environment(\.blockTree) var blockTree
	@Dependency(\.defaultDatabase) var database

	var body: some View {
		Button("Copy block ref", systemImage: "parentheses", action: copyBlockRef)
			.keyboardShortcut("c", modifiers: [.command, .shift])

		Button("Focus on block", systemImage: "magnifyingglass", action: focusOnBlock)
			.keyboardShortcut("o", modifiers: .control)

		//		Button("Open in sidebar", action: openInSidebar)

		if paragraph.isOpen {
			Button("Collapse", systemImage: "arrow.down.and.line.horizontal.and.arrow.up") { setIsOpen(to: false) }
		} else {
			Button("Expand", systemImage: "arrow.up.and.line.horizontal.and.arrow.down") { setIsOpen(to: true) }
		}

		Button("Make TODO", systemImage: "checkmark.square") { /* set TODO */ }

		Picker("", selection: $blockAlignment) {
			ForEach(Block.TextAlignment.allCases, id: \.rawValue) { alignment in
				Image(systemName: alignment.icon)
					.imageScale(.large)
					.tag(alignment)
			}
		}
		.pickerStyle(.palette)
		.onChange(of: blockAlignment) { alignBlock($1) }
		.onChange(of: paragraph.textAlign) { blockAlignment = $1 }

		let headingBinding = Binding(
			get: { self.blockHeading },
			set: { self.blockHeading = $0 == self.blockHeading ? nil : $0 }
		)

		Picker("", selection: headingBinding) {
			ForEach(Block.HeadingLevel.allCases, id: \.rawValue) { heading in
				Image("h\(heading.rawValue)")
					.imageScale(.large)
					.tag(heading)
			}
		}
		.pickerStyle(.palette)
		.onChange(of: blockHeading) { updateHeading(to: $1) }
		.onChange(of: paragraph.heading) { blockHeading = $1 }
	}

	private func copyBlockRef() {
		copyToClipboard("((\(paragraph.id)))")
		#if os(iOS)
		UIImpactFeedbackGenerator(style: .light).impactOccurred()
		#endif
	}

	private func focusOnBlock() {
		router.push(.paragraph(id: paragraph.id))
	}

	private func setIsOpen(to isOpen: Bool) {
		withErrorReporting {
			try database.write { db in
				try Block
					.find(paragraph.id)
					.update { $0.isOpen = isOpen }
					.execute(db)
			}
		}
	}

	private func alignBlock(_ alignment: Block.TextAlignment) {
		withErrorReporting {
			try database.write { db in
				try Block.find(paragraph.id)
					.update { $0.textAlign = alignment }
					.execute(db)
			}
		}
	}

	private func updateHeading(to heading: Block.HeadingLevel?) {
		guard heading != paragraph.heading else { return }

		withErrorReporting {
			try database.write { db in
				try Block.find(paragraph.id)
					.update { $0.heading = heading }
					.execute(db)
			}
		}
	}
}

#Preview {
	let paragraph = previewData { try Paragraph.fetchOne($0) }

	ParagraphView(paragraph: paragraph!)
		.preview()
}
