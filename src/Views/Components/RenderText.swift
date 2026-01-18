import SwiftUI

struct RenderText: View {
	var text: String

	var body: some View {
		Text(attributedText)
	}

	private var attributedText: AttributedString {
		let refs = text.extractRefs().sorted { $0.range.lowerBound < $1.range.lowerBound }

		guard !refs.isEmpty else {
			return AttributedString(text)
		}

		var result = AttributedString()
		var currentIndex = text.startIndex

		for ref in refs {
			if currentIndex < ref.range.lowerBound {
				result += AttributedString(text[currentIndex..<ref.range.lowerBound])
			}

			result += tap(AttributedString(ref.target)) {
				$0.link = ref.url
				$0.foregroundColor = .accentColor
			}

			currentIndex = ref.range.upperBound
		}

		if currentIndex < text.endIndex { result += AttributedString(text[currentIndex...]) }

		return result
	}
}

#Preview("Regular Text") {
	RenderText(text: "Hi! I'm a Regular Text 😄")
		.preview()
}

#Preview("With Page Link") {
	RenderText(text: "You should check out [[page]].")
		.preview()
}
