import SwiftUI
import SQLiteData

struct ContentView: View {
	@FetchAll(Page.all) var pages

	var body: some View {
		List(pages) { page in
			NavigationButton(push: .page(id: page.id)) {
				Text(page.title)
			}
		}
		.navigationTitle("Pages")
	}
}

#Preview {
	let _ = withErrorReporting {
		try prepareDependencies {
			try $0.bootstrapDatabase()
		}
	}

	ContentView()
		.preview()
}
