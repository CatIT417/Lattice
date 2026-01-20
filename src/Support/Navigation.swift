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
		case tag(name: String)
		case block(id: UUID)

		static var scheme: String { "lattice" }

		var destination: Destination.Kind {
			switch self {
				case let .page(title): .push(.pageByTitle(title: title))
				case let .tag(name): .push(.pageByTitle(title: name)) // Tags navigate to pages with matching title
				case let .block(id): .push(.block(id: id))
			}
		}

		static var routes: Routes {
			Route("page", String.parameter("title")) { title in
				.page(title: title)
			}

			Route("tag", String.parameter("name")) { name in
				.tag(name: name)
			}

			Route("block", UUID.parameter("id")) { id in
				.block(id: id)
			}
		}
	}
}

typealias Router = NavigationKit.Router<Destination>
typealias NavigationButton<Content: View> = NavigationKit.NavigationButton<Content, Destination>
typealias NavigationContainer<Content: View> = NavigationKit.NavigationContainer<Content, Destination>
