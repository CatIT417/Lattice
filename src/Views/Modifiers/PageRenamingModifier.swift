import SwiftUI
import SQLiteData

struct PageRenamingModifier: ViewModifier {
	enum TitleError: Error, LocalizedError {
		case existing, reserved, isDateTitle

		var errorDescription: String? {
			switch self {
				case .existing: "A page with that title already exists."
				case .reserved: "That title is reserved for special pages."
				case .isDateTitle: "Titles that look like dates are reserved for daily notes."
			}
		}
	}

	var page: Page
	@Binding var active: Bool
	@Dependency(\.defaultDatabase) private var database

	@State private var newTitle: String
	@State private var error: TitleError?

	init(page: Page, active: Binding<Bool>) {
		self.page = page
		_active = active
		_newTitle = State(initialValue: page.title)
	}

	var isValidTitle: Bool {
		newTitle != page.title && !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	func body(content: Content) -> some View {
		content
			.alert("Rename Page", isPresented: $active) {
				TextField("Title", text: $newTitle)

				Button("Rename", action: renamePage)
					.disabled(!isValidTitle)

				Button("Cancel", role: .cancel) {}
			} message: { Text("Any blocks referencing this page will also be updated.") }
			.alert(isPresented: $error.isPresent(), error: error) {
				Button("OK", role: .close) {
					active = true
				}
			}
			.onChange(of: page.title) { newTitle = $1 }
	}

	func renamePage() {
		guard isValidTitle else { return }

		if Constants.specialPages.contains(newTitle) {
			error = .reserved
			return
		}

		if DayOfYear(title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
			error = .isDateTitle
			return
		}

		withErrorReporting {
			try database.write { db in
				if let existingPage = try Values(Page.where { $0.title.eq(newTitle) }.exists()).fetchOne(db), existingPage {
					// TODO: Offer to merge pages
					error = .existing
					return
				}

				try Block.find(page.id).update { $0.title = #bind(newTitle) }.execute(db)
			}
		}
	}
}

extension View {
	func renamePage(_ page: Page, active: Binding<Bool>) -> some View {
		modifier(PageRenamingModifier(page: page, active: active))
	}
}

#Preview {
	@Previewable @State var isActive = true

	let page = previewData { try Page.fetchOne($0) }

	VStack {}
		.renamePage(page!, active: $isActive)
}
