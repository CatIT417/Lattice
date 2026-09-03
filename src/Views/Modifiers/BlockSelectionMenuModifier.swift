#if os(iOS)
import SwiftUI
import SQLiteData

struct BlockSelectionMenuModifier: ViewModifier {
	@Environment(Router.self) private var router
	@Dependency(\.blockSelectionCoordinator) var selectionCoordinator

	func body(content: Content) -> some View {
		content
			.safeAreaInset(edge: .bottom) {
				if selectionCoordinator.hasSelection {
					SelectionToolbar(router: router)
						.padding(.bottom, 8)
						.transition(.move(edge: .bottom).combined(with: .opacity))
				}
			}
			.animation(selectionCoordinator.animation, value: selectionCoordinator.hasSelection)
			.onChange(of: router.navigationStackPath.count) {
				selectionCoordinator.clearSelection()
			}
	}
}

struct SelectionToolbar: UIViewRepresentable {
	var router: Router

	@Dependency(\.blockSelectionCoordinator) var selectionCoordinator

	func makeUIView(context _: Context) -> UIToolbar {
		let toolbar = UIToolbar()
		toolbar.items = [
			UIBarButtonItem(title: "Copy Reference", image: UIImage(systemName: "parentheses"), primaryAction: UIAction { _ in
				copyReferences()
			}),
			UIBarButtonItem(systemItem: .fixedSpace),
			UIBarButtonItem(title: "Copy", image: UIImage(systemName: "document.on.document"), primaryAction: UIAction { _ in
				copyAsMarkdown()
			}),
			{
				let shareButton = UIBarButtonItem(title: "Share", image: UIImage(systemName: "square.and.arrow.up"))
				shareButton.primaryAction = UIAction { [weak toolbar, weak shareButton] _ in shareBlocks(from: toolbar, anchor: shareButton) }
				return shareButton
			}(),
			UIBarButtonItem(systemItem: .flexibleSpace),
			UIBarButtonItem(title: "Delete", image: UIImage(systemName: "trash"), primaryAction: UIAction { _ in
				deleteBlocks()
			}),
			UIBarButtonItem(systemItem: .fixedSpace),
			UIBarButtonItem(title: "Unselect", image: UIImage(systemName: "xmark"), primaryAction: UIAction { _ in
				selectionCoordinator.clearSelection()
			}),
		]
		toolbar.sizeToFit()

		return toolbar
	}

	func updateUIView(_: UIToolbar, context _: Context) {
		//
	}

	private func copyReferences() {
		guard selectionCoordinator.hasSelection else { return }

		guard selectionCoordinator.highlightedIDs.count > 1 else {
			copyToClipboard("((\(selectionCoordinator.highlightedIDs.first!)))")
			return
		}

		guard let orderedIDs = withErrorReporting(catching: { try Paragraph.fetchInOrder(selectionCoordinator.highlightedIDs).map(\.id) }) else { return }

		// TODO: We might want to indent children inside their parents in the future
		copyToClipboard(orderedIDs.map { "- ((\($0)))" }.joined(separator: "\n"))
	}

	private func copyAsMarkdown() {
		guard selectionCoordinator.hasSelection else { return }

		if let markdown = withErrorReporting(catching: { try MarkdownExporter.exportSelection(selectionCoordinator.highlightedIDs) }) {
			copyToClipboard(markdown)
		}
	}

	private func shareBlocks(from view: UIView?, anchor: UIBarButtonItem?) {
		guard selectionCoordinator.hasSelection,
		      let viewController = view?.window?.rootViewController,
		      let markdown = withErrorReporting(catching: { try MarkdownExporter.exportSelection(selectionCoordinator.highlightedIDs) })
		else { return }

		var presenter = viewController
		while let presented = presenter.presentedViewController {
			presenter = presented
		}

		presenter.present(tap(UIActivityViewController(activityItems: [markdown], applicationActivities: nil)) {
			$0.popoverPresentationController?.barButtonItem = anchor
		}, animated: true)
	}

	private func deleteBlocks() {
		guard selectionCoordinator.hasSelection else { return }

		@Dependency(\.defaultDatabase) var database
		withErrorReporting {
			try database.write { db in
				try Paragraph.where {
					$0.id.in(selectionCoordinator.highlightedIDs)
				}
				.delete()
				.execute(db)
			}

			router.navigationStackPath.removeAll(where: { path in
				guard case let .paragraph(id) = path, selectionCoordinator.highlightedIDs.contains(id) else { return false }
				return true
			})

			selectionCoordinator.clearSelection()
		}
	}
}

extension View {
	func blockSelectionMenu() -> some View {
		modifier(BlockSelectionMenuModifier())
	}
}

#Preview("Toolbar") {
	let _ = previewData()

	SelectionToolbar(router: Router.previewRouter())
}

#Preview("Full") {
	let _ = previewData()

	RootContainer()
		.preview()
}
#endif
