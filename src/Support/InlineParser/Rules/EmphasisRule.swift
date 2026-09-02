import Foundation

/// Matches emphasis: *italic*, **bold**, ***bold italic***, and underscore variants.
/// Uses regex-driven delimiter scanning with an inner-opener stack for correct nesting.
struct EmphasisRule: InlineParser.Rule, Sendable {
	let priority = 800
	let startingCharacters: Set<Character>? = ["*", "_"]

	private struct Delimiter {
		let char: Character
		let runPattern: Regex<Substring>
		let tokenPattern: Regex<(Substring, Substring?)>

		var isUnderscore: Bool {
			char == "_"
		}

		private nonisolated(unsafe) static let star = Delimiter(
			char: "*",
			runPattern: /\*+/,
			tokenPattern: /\\.|(\*+)/
		)

		private nonisolated(unsafe) static let underscore = Delimiter(
			char: "_",
			runPattern: /_+/,
			tokenPattern: /\\.|(_+)/
		)

		static func from(_ char: Character) -> Delimiter? {
			switch char {
				case "*": star
				case "_": underscore
				default: nil
			}
		}
	}

	private struct DelimiterState {
		let canOpen: Bool
		let canClose: Bool
	}

	func match(in text: String, at index: String.Index, using parser: InlineParser) -> InlineSpan? {
		guard let delimiter = Delimiter.from(text[index]) else { return nil }

		// Only match at the start of a delimiter run
		if index > text.startIndex, text[text.index(before: index)] == delimiter.char { return nil }

		let runLen = delimiterRunLength(in: text, at: index, delimiter: delimiter)
		guard runLen > 0 else { return nil }

		// Try bold (openerLen=2) first if run is long enough, then italic (openerLen=1)
		if runLen >= 2 {
			if let span = tryMatch(in: text, at: index, runLen: runLen, openerLen: 2, delimiter: delimiter, using: parser) {
				return span
			}

			// Fallback to italic for runs >= 2 that couldn't find a bold closer
			return tryMatch(in: text, at: index, runLen: runLen, openerLen: 1, delimiter: delimiter, using: parser)
		}

		return tryMatch(in: text, at: index, runLen: runLen, openerLen: 1, delimiter: delimiter, using: parser)
	}

	private func tryMatch(
		in text: String,
		at index: String.Index,
		runLen: Int,
		openerLen: Int,
		delimiter: Delimiter,
		using parser: InlineParser
	) -> InlineSpan? {
		let opener = delimiterState(in: text, at: index, runLen: runLen, delimiter: delimiter)
		guard opener.canOpen else { return nil }

		let contentStart = text.index(index, offsetBy: openerLen)
		guard contentStart < text.endIndex else { return nil }

		// Scan forward with inner-opener stack, one token at a time so we stop at the closer
		var stack: [Int] = []
		var searchStart = contentStart

		while let token = text[searchStart...].firstMatch(of: delimiter.tokenPattern) {
			searchStart = token.range.upperBound

			guard let run = token.1 else {
				// Escaped character token (e.g. \*) - delimiters inside it are inert.
				continue
			}

			let pos = token.range.lowerBound
			let scanRunLen = run.count
			let state = delimiterState(in: text, at: pos, runLen: scanRunLen, delimiter: delimiter)

			var available = scanRunLen

			if state.canClose {
				// Close inner openers first
				while available > 0, !stack.isEmpty {
					let inner = stack.removeLast()
					let consumed = min(available, inner)
					available -= consumed
					if inner > consumed {
						stack.append(inner - consumed)
					}
				}

				// Try to close our opener
				if available >= openerLen, stack.isEmpty {
					let innerConsumed = scanRunLen - available
					let ourCloserStart = text.index(pos, offsetBy: innerConsumed)
					let contentEnd = ourCloserStart
					let content = String(text[contentStart..<contentEnd])

					guard isValidCloser(content: content, in: text, closerStart: ourCloserStart, openerLen: openerLen, delimiter: delimiter) else {
						pushAvailableAsOpener(available, canOpen: state.canOpen, into: &stack)
						continue
					}

					let spanEnd = text.index(ourCloserStart, offsetBy: openerLen)
					let kind: InlineSpan.Kind = openerLen == 2 ? .bold : .italic
					let children = parser.parse(content)

					return InlineSpan(kind: kind, range: index..<spanEnd, content: content, children: children)
				}
			}

			// Push remaining as inner opener if left-flanking
			pushAvailableAsOpener(available, canOpen: state.canOpen, into: &stack)
		}

		return nil
	}

	// MARK: - Helpers

	/// Count consecutive delimiter characters at `index` using a regex prefix match.
	private func delimiterRunLength(in text: String, at index: String.Index, delimiter: Delimiter) -> Int {
		let remaining = text[index...]
		guard let match = remaining.prefixMatch(of: delimiter.runPattern) else { return 0 }
		return match.0.count
	}

	private func delimiterState(
		in text: String,
		at index: String.Index,
		runLen: Int,
		delimiter: Delimiter
	) -> DelimiterState {
		let rightFlanking = isRightFlanking(in: text, at: index, length: runLen)
		let leftFlanking = isLeftFlanking(in: text, at: index, length: runLen)

		guard delimiter.isUnderscore else {
			return DelimiterState(canOpen: leftFlanking, canClose: rightFlanking)
		}

		let canClose = rightFlanking && (!leftFlanking || {
			let afterRun = text.index(index, offsetBy: runLen)
			return afterRun < text.endIndex && text[afterRun].isPunctuation
		}())
		let canOpen = leftFlanking && (!rightFlanking || index > text.startIndex && text[text.index(before: index)].isPunctuation)

		return DelimiterState(canOpen: canOpen, canClose: canClose)
	}

	private func isValidCloser(
		content: String,
		in text: String,
		closerStart: String.Index,
		openerLen: Int,
		delimiter: Delimiter
	) -> Bool {
		guard !content.isEmpty else { return false }

		guard delimiter.isUnderscore else { return true }

		let afterCloser = text.index(closerStart, offsetBy: openerLen)
		guard afterCloser < text.endIndex else { return true }

		let next = text[afterCloser]
		return !(next.isLetter || next.isNumber || next == "_")
	}

	private func pushAvailableAsOpener(_ available: Int, canOpen: Bool, into stack: inout [Int]) {
		if canOpen, available > 0 {
			stack.append(available)
		}
	}

	/// A left-flanking delimiter run: not followed by whitespace, and either
	/// not followed by punctuation, or preceded by whitespace/punctuation.
	private func isLeftFlanking(in text: String, at index: String.Index, length: Int) -> Bool {
		let afterRun = text.index(index, offsetBy: length)

		// Must not be followed by whitespace (end of string counts as whitespace)
		guard afterRun < text.endIndex else { return false }
		let nextChar = text[afterRun]
		if nextChar.isWhitespace { return false }

		// Either not followed by punctuation, or preceded by whitespace/punctuation
		if nextChar.isPunctuation {
			if index == text.startIndex { return true } // start of string counts as whitespace
			let prevChar = text[text.index(before: index)]
			return prevChar.isWhitespace || prevChar.isPunctuation
		}

		return true
	}

	/// A right-flanking delimiter run: not preceded by whitespace, and either
	/// not preceded by punctuation, or followed by whitespace/punctuation.
	private func isRightFlanking(in text: String, at index: String.Index, length: Int) -> Bool {
		// Must not be preceded by whitespace (start of string counts as whitespace)
		guard index > text.startIndex else { return false }
		let prevChar = text[text.index(before: index)]
		if prevChar.isWhitespace { return false }

		let afterRun = text.index(index, offsetBy: length)

		// Either not preceded by punctuation, or followed by whitespace/punctuation
		if prevChar.isPunctuation {
			if afterRun >= text.endIndex { return true } // end of string counts as whitespace
			let nextChar = text[afterRun]
			return nextChar.isWhitespace || nextChar.isPunctuation
		}

		return true
	}
}
