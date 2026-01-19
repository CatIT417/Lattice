import SwiftUI
import SQLiteData

struct RootContainer: View {
	@FetchAll(Page.all) var pages

	var content: some View {
		List(pages) { page in
			NavigationButton(push: .page(id: page.id)) {
				Text(page.title)
			}
		}
		.navigationTitle("Pages")
	}

	var body: some View {
		NavigationContainer(parentRouter: Router(level: 0)) {
			content
		}
	}
}

#Preview {
	let _ = withErrorReporting {
		try prepareDependencies {
			try $0.bootstrapDatabase()
		}
	}

	RootContainer()
		.preview(wrapInNavigation: false)
}
