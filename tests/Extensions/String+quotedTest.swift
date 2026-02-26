import Testing
import CustomDump

@testable import LatticeDev

extension Tests {
	@Suite("Extensions/String+quoted")
	struct StringQuotedTest {}
}

extension Tests.StringQuotedTest {
	@Test("quoted returns tokenized and phrase clauses for multi-word strings")
	func quotedBuildsTokenizedAndPhraseClauses() {
		expectNoDifference(
			"Quantum Mechanics".quoted(),
			"\"Quantum\" \"Mechanics\" OR \"Quantum Mechanics\""
		)
	}

	@Test("quoted returns a valid fallback query for whitespace-only strings")
	func quotedUsesValidFallbackForWhitespaceOnlyStrings() {
		expectNoDifference("   \n\t  ".quoted(), "\" \"")
	}
}
