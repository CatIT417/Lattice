import SwiftUI
import Foundation
@_exported import NavigationKit

struct Destination: NavigationDestination {
	enum Tabs: String, TabRepresentable {
		case daily, search
	}

	enum Pages: PageRepresentable {
		case page(id: UUID)
		case block(id: UUID)
		case paragraph(id: UUID)
		case pageByTitle(title: String)

		var view: some View {
			switch self {
				case let .page(id): PageScreen(pageId: id)
				case let .block(id): BlockScreen(blockID: id)
				case let .paragraph(id): ParagraphScreen(paragraphId: id)
				case let .pageByTitle(title): PageScreen.ByTitle(title: title)
			}
		}
	}

	enum Deeplinks: DeeplinkRepresentable {
		typealias Using = Destination

		case block(id: UUID)
		case tag(name: String)
		case page(title: String)

		static var scheme: String { "lattice" }

		var destination: Destination.Kind {
			switch self {
				case let .block(id): .push(.block(id: id))
				case let .tag(name): .push(.pageByTitle(title: name))
				case let .page(title): .push(.pageByTitle(title: title))
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
