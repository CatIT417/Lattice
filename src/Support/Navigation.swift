import SwiftUI
import Foundation
@_exported import NavigationKit

struct Destination: NavigationDestination {
	enum Pages: PageRepresentable {
		case page(id: UUID)
		case pageByTitle(title: String)
		case paragraph(id: UUID)

		@available(*, deprecated, message: "Use .page or .paragraph instead.")
		case block(id: UUID)

		var view: some View {
			switch self {
				case let .page(id): PageScreen(pageId: id)
				case let .pageByTitle(title): EmptyView() // PageScreen.ByTitle(title: title)
				case let .block(id): BlockScreen(blockID: id)
				case let .paragraph(id): ParagraphScreen(paragraphId: id)
			}
		}
	}

	enum Deeplinks: DeeplinkRepresentable {
		typealias Using = Destination

		case page(title: String)

		static var scheme: String { "lattice" }

		var destination: Destination.Kind {
			switch self {
				case let .page(title): .push(.pageByTitle(title: title))
			}
		}

		static var routes: Routes {
			Route("page", String.parameter("title")) { title in
				.page(title: title)
			}
		}
	}
}

typealias Router = NavigationKit.Router<Destination>
typealias NavigationButton<Content: View> = NavigationKit.NavigationButton<Content, Destination>
typealias NavigationContainer<Content: View> = NavigationKit.NavigationContainer<Content, Destination>
