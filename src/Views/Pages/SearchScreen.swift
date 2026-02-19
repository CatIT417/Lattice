import SwiftUI
import SQLiteData
import NavigationKit

struct SearchScreen: View {
	@FetchAll var pages: [Page]
	@State var search = SearchResults()

	var body: some View {
		List {
			if search.hasResults {
				searchResults
			} else if search.hasEmptyQuery {
				allPages
			}
		}
		.searchable(text: $search.searchText)
		.searchPresentationToolbarBehavior(.avoidHidingContent)
		.toolbarTitleDisplayMode(.inline)
		.navigationTitle(search.hasEmptyQuery ? "All Pages" : "Search Results")
		.overlay {
			if !search.hasResults, !search.hasEmptyQuery {
				ContentUnavailableView.search(text: search.searchText)
			}
		}
	}

	var searchResults: some View {
		ForEach(search.results) { block in
			NavigationButton(push: block.destination) {
				Group {
					switch block.kind {
						case let .page(page): Text(page.title)
						case let .paragraph(paragraph):
							VStack(alignment: .leading, spacing: 4) {
								BreadcrumbsView(blockId: paragraph.id)
									.environment(\.isNavigationEnabled, false)

								RenderAsLabel(
									text: buildAttributedString(from: paragraph.string).attributedString
								)
							}
					}
				}
				.padding(.horizontal)
			}
			.contentShape(.rect)
			.buttonStyle(.plain)
			#if os(macOS)
				.pointerStyle(.link)
			#endif
		}
	}

	var allPages: some View {
		ForEach(pages) { page in
			NavigationButton(push: .page(id: page.id)) {
				Text(page.title)
					.padding(.horizontal)
			}
			.buttonStyle(.plain)
			#if os(macOS)
				.pointerStyle(.link)
			#endif
		}
	}
}

#Preview {
	let _ = previewData()

	SearchScreen()
		.preview()
}
