import SwiftUI
import SQLiteData

struct SyncStatusOnToolbarModifier: ViewModifier {
	@Dependency(\.defaultSyncEngine) var syncEngine

	func body(content: Content) -> some View {
		content
			.toolbar {
				if syncEngine.isRunning {
					ToolbarItem {
						Image(systemName: syncEngine.isSynchronizing ? "arrow.trianglehead.2.clockwise.rotate.90.icloud" : "checkmark.icloud")
						#if os(macOS)
							.imageScale(.large)
						#endif
							.contentTransition(.symbolEffect)
							.symbolEffect(.rotate, options: .repeat(.periodic), isActive: syncEngine.isSynchronizing)
							.help(syncEngine.isSynchronizing ? "Syncing..." : "Up to date")
					}
					.sharedBackgroundVisibility(.hidden)
				}
			}
	}
}

extension View {
	func syncStatusOnToolbar() -> some View {
		modifier(SyncStatusOnToolbarModifier())
	}
}

#Preview {
	let _ = previewData()

	VStack {}
		.syncStatusOnToolbar()
		.preview()
}
