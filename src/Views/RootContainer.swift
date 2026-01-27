import SwiftUI
import SQLiteData

struct RootContainer: View {
	@FetchAll(Page.all) var pages
	@Dependency(\.defaultDatabase) var database

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
		#if os(iOS)
		.postNotificationOnStateChange()
		#endif
		.onAppear { createDailyNoteIfNeeded() }
	}

	func createDailyNoteIfNeeded() {
		withErrorReporting {
			guard let hasPage = try database.read({ db in
				try Values(Page.where { $0.dailyNoteDate.eq(#bind(Date())) }.exists()).fetchOne(db)
			}), !hasPage else { return }

			try database.write { db in
				try Page.insert { Page.createDailyNote(for: Date()) }.execute(db)
			}
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
