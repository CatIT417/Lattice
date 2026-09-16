/// Create a plain-text representation of the given markup string
///
/// This will:
/// - Strip all formatting
/// - Localize links to daily pages
/// - Resolve page links and tags to their titles
/// - Remove any TODO/DONE prefix from the string
func renderPlainText(fromMarkup source: String) -> String {
	renderPlainText(from: InlineParser.default.parse(source.strippingTodoPrefix()))
}

private func renderPlainText(from spans: [InlineSpan]) -> String {
	spans.map { span in
		switch span.kind {
			case .pageLink, .tag:
				let prefix = span.kind == .tag ? "#" : ""
				return prefix + Page.title(for: span.content)
			case .bold, .italic, .highlight, .link:
				return span.children.isEmpty ? span.content : renderPlainText(from: span.children)
			case .text, .code, .blockRef, .blockEmbed:
				return span.content
		}
	}
	.joined()
}
