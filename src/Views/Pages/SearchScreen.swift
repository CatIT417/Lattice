import SwiftUI
import SQLiteData

struct SearchScreen: View {
	@State var search = SearchResults()

	var body: some View {
		List {
			ForEach(search.results) { block in
				NavigationButton(push: block.destination) {
					Text(block.title ?? block.string ?? "")
						.padding(.horizontal)
				}
				.buttonStyle(.plain)
				#if os(macOS)
					.pointerStyle(.link)
				#endif
			}
		}
		.searchable(text: $search.searchText)
		.overlay {
			if !search.hasResults {
				ContentUnavailableView.search(text: search.searchText)
			}
		}
	}
}

#Preview {
	let _ = previewData()

	SearchScreen()
		.preview()
}
