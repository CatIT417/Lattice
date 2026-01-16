import SwiftUI
import SQLiteData

struct ContentView: View {
	var body: some View {
		VStack {
			Image(systemName: "globe")
				.imageScale(.large)
				.foregroundStyle(.tint)

			Text("Hello, world!")
		}
		.padding()
	}
}

#Preview {
	let _ = withErrorReporting {
		try prepareDependencies {
			try $0.bootstrapDatabase()
		}
	}

	ContentView()
}
