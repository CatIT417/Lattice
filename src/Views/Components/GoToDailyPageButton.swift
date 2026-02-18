import SwiftUI
import SQLiteData

struct GoToDailyPageButton: View {
	var currentDate = Date()

	init(currentDate: Date = Date()) {
		self.currentDate = currentDate
		_selection = State(initialValue: currentDate)
	}

	@State private var selection: Date
	@State private var buttonSize: CGSize = .zero

	@Environment(Router.self) private var router
	@Dependency(\.defaultDatabase) private var database

	var body: some View {
		Button(action: {}) {
			Image(systemName: "calendar")
		}
		.allowsHitTesting(false)
		.onGeometryChange(for: CGSize.self, of: { $0.size }, action: { buttonSize = $0 })
		.background {
			DatePicker("Go to Date", selection: $selection, displayedComponents: .date)
				.datePickerStyle(.compact)
				.labelsHidden()
				.colorMultiply(.clear)
				.frame(width: buttonSize.width, height: buttonSize.height)
				.clipped()
		}
		.onChange(of: currentDate) { selection = $1 }
		.onChange(of: selection) { _, selection in
			guard selection != currentDate else { return }

			navigateToDailyPage(for: DayOfYear(selection))
		}
	}

	func navigateToDailyPage(for day: DayOfYear) {
		withErrorReporting {
			let page = try database.write { db in
				try Page.createDailyNote(for: day, in: db)
			}

			router.push(.page(id: page.id))
		}
	}
}

#Preview {
	let _ = previewData()

	VStack {}
		.toolbar {
			ToolbarItem {
				GoToDailyPageButton()
			}
		}
		.preview()
}
