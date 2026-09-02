import Foundation

/// Matches emphasis: *italic*, **bold**, ***bold italic***, and underscore variants.
///
/// Delimiter runs are tokenized once per parse (see `Scanner`, kept in the parser's per-parse memo) and scanned
/// with an inner-opener stack for correct nesting. Scan outcomes are memoized per token, so openers that never
/// close don't rescan the same tail over and over.
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

	private struct ScannerKey: Hashable {
		let delimiter: Character
	}

	func match(in text: String, at index: String.Index, using parser: InlineParser) -> InlineSpan? {
		guard let delimiter = Delimiter.from(text[index]) else { return nil }

		// Only match at the start of a delimiter run
		if index > text.startIndex, text[text.index(before: index)] == delimiter.char { return nil }

		let runLen = Self.delimiterRunLength(in: text, at: index, delimiter: delimiter)
		guard runLen > 0 else { return nil }
		guard Self.delimiterState(in: text, at: index, runLen: runLen, delimiter: delimiter).canOpen else { return nil }

		let scanner = parser.memo(key: ScannerKey(delimiter: delimiter.char)) { Scanner(text: text, delimiter: delimiter) }

		// Try bold (openerLen=2) first if run is long enough, then italic (openerLen=1)
		if runLen >= 2, let span = scanner.match(openerAt: index, runLen: runLen, openerLen: 2, using: parser) {
			return span
		}

		return scanner.match(openerAt: index, runLen: runLen, openerLen: 1, using: parser)
	}

	// MARK: - Scanner

	/// Tokenizes every run of one delimiter in a text and answers "where does an opener here close?" using
	/// memoized forward scans. One instance lives for a single parse of a single text.
	private final class Scanner {
		private struct Token {
			let start: String.Index
			let runLen: Int
			let canOpen: Bool
			let canClose: Bool
		}

		/// The first closer reached with capacity left over when scanning forward from a token with an empty stack.
		private struct Dip {
			let token: Int
			let available: Int
		}

		private enum Outcome {
			case unmatched
			case closed(token: Int, available: Int)
		}

		private let text: String
		private let delimiter: Delimiter
		private let tokens: [Token]
		private let dips: [Dip?]

		/// Memoized outcomes of scanning from a token with an empty stack, indexed by `openerLen - 1`.
		private var outcomes: [[Outcome?]]

		init(text: String, delimiter: Delimiter) {
			let tokens = text.matches(of: delimiter.tokenPattern).compactMap { match -> Token? in
				// Escaped character tokens (e.g. \*) are inert.
				guard let run = match.1 else { return nil }

				let runLen = run.count
				let state = EmphasisRule.delimiterState(in: text, at: match.range.lowerBound, runLen: runLen, delimiter: delimiter)

				return Token(start: match.range.lowerBound, runLen: runLen, canOpen: state.canOpen, canClose: state.canClose)
			}

			let unknown = [Outcome?](repeating: nil, count: tokens.count + 1)

			self.text = text
			self.delimiter = delimiter
			self.tokens = tokens
			dips = Self.computeDips(tokens)
			outcomes = [unknown, unknown]
		}

		func match(openerAt index: String.Index, runLen: Int, openerLen: Int, using parser: InlineParser) -> InlineSpan? {
			let contentStart = text.index(index, offsetBy: openerLen)
			guard contentStart < text.endIndex else { return nil }

			var stack: [Int] = []

			// Whatever is left of the opener run is the first thing the scan sees. It can never close (that would
			// wrap empty content), so it only matters as an inner opener.
			if runLen > openerLen {
				let leftover = runLen - openerLen
				if EmphasisRule.delimiterState(in: text, at: contentStart, runLen: leftover, delimiter: delimiter).canOpen {
					stack.append(leftover)
				}
			}

			let runEnd = text.index(index, offsetBy: runLen)
			guard case let .closed(closerToken, available) = scan(from: firstToken(startingAt: runEnd), stack: stack, openerLen: openerLen) else {
				return nil
			}

			let closer = tokens[closerToken]
			let closerStart = text.index(closer.start, offsetBy: closer.runLen - available)
			let spanEnd = text.index(closerStart, offsetBy: openerLen)
			let content = String(text[contentStart..<closerStart])
			let kind: InlineSpan.Kind = openerLen == 2 ? .bold : .italic

			return InlineSpan(kind: kind, range: index..<spanEnd, content: content, children: parser.parse(content))
		}

		/// Runs the inner-opener stack machine over the tokens from `start`. Every empty-stack state along the way
		/// shares the final outcome, so all of them are memoized.
		private func scan(from start: Int, stack initialStack: [Int], openerLen: Int) -> Outcome {
			let memo = openerLen - 1
			var visited: [Int] = []
			var stack = initialStack
			var result = Outcome.unmatched
			var k = start

			while true {
				if stack.isEmpty {
					if let known = outcomes[memo][k] {
						result = known
						break
					}

					visited.append(k)
				}

				guard k < tokens.count, let dip = dips[k] else { break }

				var available = dip.available

				// Close inner openers first
				while available > 0, let inner = stack.popLast() {
					let consumed = min(available, inner)
					available -= consumed
					if inner > consumed {
						stack.append(inner - consumed)
					}
				}

				let closer = tokens[dip.token]

				// Try to close our opener
				if stack.isEmpty, available >= openerLen, isValidCloser(closer, available: available, openerLen: openerLen) {
					result = .closed(token: dip.token, available: available)
					break
				}

				// Push remaining as inner opener if left-flanking
				if available > 0, closer.canOpen {
					stack.append(available)
				}

				k = dip.token + 1
			}

			for state in visited {
				outcomes[memo][state] = result
			}

			return result
		}

		/// For each token, the first closer with capacity left over when scanning forward from it with an empty
		/// stack. Computed right to left so each opener only walks the closers that eat its own run.
		private static func computeDips(_ tokens: [Token]) -> [Dip?] {
			var dips = [Dip?](repeating: nil, count: tokens.count)

			for k in tokens.indices.reversed() {
				let token = tokens[k]

				if token.canClose {
					dips[k] = Dip(token: k, available: token.runLen)
				} else if token.canOpen {
					var entry = token.runLen
					var next = k + 1

					while let candidate = next < tokens.count ? dips[next] : nil {
						if candidate.available > entry {
							dips[k] = Dip(token: candidate.token, available: candidate.available - entry)
							break
						}

						entry -= candidate.available
						next = candidate.token + 1

						if entry == 0 {
							dips[k] = next < tokens.count ? dips[next] : nil
							break
						}
					}
				} else if k + 1 < tokens.count {
					dips[k] = dips[k + 1]
				}
			}

			return dips
		}

		/// Content is never empty for tokens past the opener run, so only the underscore intraword rule applies.
		private func isValidCloser(_ closer: Token, available: Int, openerLen: Int) -> Bool {
			guard delimiter.isUnderscore else { return true }

			let afterCloser = text.index(closer.start, offsetBy: closer.runLen - available + openerLen)
			guard afterCloser < text.endIndex else { return true }

			let next = text[afterCloser]
			return !(next.isLetter || next.isNumber || next == "_")
		}

		private func firstToken(startingAt position: String.Index) -> Int {
			var low = 0
			var high = tokens.count

			while low < high {
				let mid = (low + high) / 2
				if tokens[mid].start < position {
					low = mid + 1
				} else {
					high = mid
				}
			}

			return low
		}
	}

	// MARK: - Helpers

	/// Count consecutive delimiter characters at `index` using a regex prefix match.
	private static func delimiterRunLength(in text: String, at index: String.Index, delimiter: Delimiter) -> Int {
		let remaining = text[index...]
		guard let match = remaining.prefixMatch(of: delimiter.runPattern) else { return 0 }
		return match.0.count
	}

	private static func delimiterState(
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

	/// A left-flanking delimiter run: not followed by whitespace, and either
	/// not followed by punctuation, or preceded by whitespace/punctuation.
	private static func isLeftFlanking(in text: String, at index: String.Index, length: Int) -> Bool {
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
	private static func isRightFlanking(in text: String, at index: String.Index, length: Int) -> Bool {
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
