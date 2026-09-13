import SwiftUI
import SQLiteData

struct PageRenamingModifier: ViewModifier {
	var page: Page
	@Binding var active: Bool
	@Dependency(\.defaultDatabase) private var database

	@State private var newTitle: String
	@State private var error: Page.TitleError?

	init(page: Page, active: Binding<Bool>) {
		self.page = page
		_active = active
		_newTitle = State(initialValue: page.title)
	}

	var validationError: Page.TitleError? {
		do {
			try Page.validateTitle(newTitle)
			return nil
		} catch {
			return error
		}
	}

	var isValidTitle: Bool {
		newTitle.trimmingCharacters(in: .whitespacesAndNewlines) != page.title && validationError == nil
	}

	func body(content: Content) -> some View {
		content
			.alert("Rename Page", isPresented: $active) {
				TextField("Title", text: $newTitle)

				Button("Rename", action: renamePage)
					.disabled(!isValidTitle)

				Button("Cancel", role: .cancel) {}
			} message: {
				if let validationError {
					Text(validationError.localizedDescription)
				} else {
					Text("Any blocks referencing this page will also be updated.")
				}
			}
			.alert(isPresented: $error.isPresent(), error: error) {
				Button("OK", role: .close) {
					active = true
				}
			}
			.onChange(of: page.title) { newTitle = $1 }
	}

	func renamePage() {
		guard isValidTitle else { return }
		let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)

		if Constants.specialPages.contains(trimmedTitle) {
			error = .reserved
			return
		}

		if DayOfYear(title: trimmedTitle) != nil {
			error = .isDateTitle
			return
		}

		withErrorReporting {
			try database.write { db in
				if let existingPage = try Select(Page.where { $0.title.eq(trimmedTitle) }.exists()).fetchOne(db), existingPage {
					// TODO: Offer to merge pages
					error = .existing
					return
				}

				try Block.find(page.id)
					.update {
						$0.title = #bind(trimmedTitle)
					}
					.execute(db)
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
