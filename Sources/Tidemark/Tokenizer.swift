//
//  Tokenizer.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

struct Tokenizer {

	private let input: [UInt8]
	private var pos: Int = 0
	private var line: Int = 1
	private var column: Int = 1
	private var isAtLineStart: Bool = true

	init(_ input: [UInt8]) {
		self.input = input
	}

	init(_ string: String) {
		self.input = Array(string.utf8)
	}

	mutating func next() -> Token {
		scanToken()
	}

	mutating func reset() {
		pos = 0
		line = 1
		column = 1
		isAtLineStart = true
	}

	private static let atxTypes: [TokenType] = [
		.atxHeader1, .atxHeader2, .atxHeader3,
		.atxHeader4, .atxHeader5, .atxHeader6
	]

	// MARK: - Private

	private var isAtEnd: Bool {
		pos >= input.count
	}

	private func peek() -> UInt8 {
		guard pos < input.count else {
			return 0
		}
		return input[pos]
	}

	private func peekN(_ n: Int) -> UInt8 {
		guard pos + n < input.count else {
			return 0
		}
		return input[pos + n]
	}

	private mutating func advance() {
		guard !isAtEnd else {
			return
		}

		let c = input[pos]
		pos += 1

		if c == .asciiNewline {
			line += 1
			column = 1
			isAtLineStart = true
		} else {
			column += 1
			if !c.isASCIIWhitespace {
				isAtLineStart = false
			}
		}
	}

	private func makeToken(_ type: TokenType, start: Int, length: Int, line: Int, column: Int) -> Token {
		Token(type: type, start: start, length: length, line: line, column: column)
	}

	/// Count leading spaces/tabs at current position.
	/// Tabs count as 4 spaces for indentation purposes.
	private func countLeadingSpaces() -> Int {
		var count = 0
		var i = 0

		while pos + i < input.count {
			let c = input[pos + i]
			if c == .asciiSpace {
				count += 1
				i += 1
			} else if c == .asciiTab {
				count += 4 - (count % 4)
				i += 1
			} else {
				break
			}
		}

		return count
	}

	/// Check if there's a hard break (2+ spaces followed by newline) at current position.
	private func isHardBreak() -> (isHardBreak: Bool, spaceCount: Int) {
		var scanPosition = pos
		while scanPosition < input.count && input[scanPosition] == .asciiSpace {
			scanPosition += 1
		}

		let count = scanPosition - pos
		let isHard = count >= 2 && scanPosition < input.count && input[scanPosition] == .asciiNewline
		return (isHard, count)
	}

	/// Check if current line is a horizontal rule with given marker.
	private func isHruleLine(_ marker: UInt8) -> Bool {
		var p = pos
		var count = 0

		while p < input.count && input[p] != .asciiNewline {
			let c = input[p]
			if c == marker {
				count += 1
			} else if c != .asciiSpace && c != .asciiTab {
				return false
			}
			p += 1
		}

		return count >= 3
	}

	// MARK: - Token Scanning

	private mutating func scanToken() -> Token {
		guard !isAtEnd else {
			return makeToken(.eof, start: pos, length: 0, line: line, column: column)
		}

		if isAtLineStart {
			return scanLineStart()
		}
		return scanInline()
	}

	/// Scan tokens that can appear at line start (block-level markers).
	private mutating func scanLineStart() -> Token {
		let savedLine = line
		let savedColumn = column
		let start = pos
		let c = peek()

		// Check for blank line (empty or only whitespace)
		if c == .asciiNewline {
			advance()
			return makeToken(.blankLine, start: start, length: 1, line: savedLine, column: savedColumn)
		}

		// Check for indented code block (4+ spaces or tab)
		let indent = countLeadingSpaces()
		if indent >= 4 {
			// Check if it's a blank line with leading whitespace
			let savedPos = pos
			while pos < input.count && (input[pos] == .asciiSpace || input[pos] == .asciiTab) {
				pos += 1
			}
			if pos >= input.count || input[pos] == .asciiNewline {
				// Blank line with whitespace — consume the newline too
				if pos < input.count && input[pos] == .asciiNewline {
					pos += 1
					line += 1
					column = 1
				}
				return makeToken(.blankLine, start: start, length: pos - start, line: savedLine, column: savedColumn)
			}
			// Not blank — restore position and scan as code
			pos = savedPos
			return scanCodeBlockLine()
		}

		// Skip leading spaces (up to 3)
		var spaces = 0
		while spaces < 3 && peek() == .asciiSpace {
			advance()
			spaces += 1
		}

		let firstNonSpaceChar = peek()

		// Line with only whitespace (up to 3 spaces followed by newline) is blank
		if firstNonSpaceChar == .asciiNewline {
			advance()
			return makeToken(.blankLine, start: start, length: pos - start, line: savedLine, column: savedColumn)
		}

		// ATX header
		if firstNonSpaceChar == .asciiHash {
			return scanATXHeader()
		}

		// Blockquote
		if firstNonSpaceChar == .asciiGreaterThan {
			return scanBlockquote()
		}

		// Horizontal rule or setext header underline (-, *, _)
		if firstNonSpaceChar == .asciiDash || firstNonSpaceChar == .asciiAsterisk || firstNonSpaceChar == .asciiUnderscore {
			if isHruleLine(firstNonSpaceChar) {
				return scanHruleOrSetext(firstNonSpaceChar)
			}
			// Could be a list marker
			if (firstNonSpaceChar == .asciiDash || firstNonSpaceChar == .asciiAsterisk) &&
				(peekN(1) == .asciiSpace || peekN(1) == .asciiTab) {
				return scanListMarker()
			}
		}

		// Setext header underline with =
		if firstNonSpaceChar == .asciiEquals {
			return scanHruleOrSetext(firstNonSpaceChar)
		}

		// Unordered list marker (+)
		if firstNonSpaceChar == .asciiPlus && (peekN(1) == .asciiSpace || peekN(1) == .asciiTab) {
			return scanListMarker()
		}

		// Ordered list marker (digit followed by .)
		if firstNonSpaceChar.isASCIIDigit {
			var i = 0
			while peekN(i).isASCIIDigit {
				i += 1
			}
			if peekN(i) == .asciiDot &&
				(peekN(i + 1) == .asciiSpace || peekN(i + 1) == .asciiTab) {
				return scanListMarker()
			}
		}

		// Not a block-level marker, switch to inline scanning
		isAtLineStart = false
		return scanInline()
	}

	/// Scan ATX-style header (# Header).
	private mutating func scanATXHeader() -> Token {
		let savedLine = line
		let savedColumn = column
		let start = pos

		var level = 0
		while peek() == .asciiHash && level < 6 {
			advance()
			level += 1
		}

		// Must be followed by space or end of line for valid header
		let next = peek()
		if next != .asciiSpace && next != .asciiTab && next != .asciiNewline && next != 0 {
			// Not a valid header, treat as text
			isAtLineStart = false
			return makeToken(.text, start: start, length: level, line: savedLine, column: savedColumn)
		}

		// Skip the space after #
		if next == .asciiSpace || next == .asciiTab {
			advance()
		}

		let type = Self.atxTypes[level - 1]

		isAtLineStart = false
		return makeToken(type, start: start, length: pos - start, line: savedLine, column: savedColumn)
	}

	private mutating func scanBlockquote() -> Token {
		let savedLine = line
		let savedColumn = column
		let start = pos

		advance() // Consume '>'

		// Optional space after >
		if peek() == .asciiSpace {
			advance()
		}

		isAtLineStart = true // Content after > is like a new line start
		return makeToken(.blockquote, start: start, length: pos - start, line: savedLine, column: savedColumn)
	}

	/// Scan indented code block line.
	private mutating func scanCodeBlockLine() -> Token {
		let savedLine = line
		let savedColumn = column

		// Skip the 4-space indent (or tab)
		var indentConsumed = 0
		while indentConsumed < 4 && !isAtEnd {
			let c = peek()
			if c == .asciiSpace {
				advance()
				indentConsumed += 1
			} else if c == .asciiTab {
				advance()
				indentConsumed = 4 // Tab counts as reaching 4
			} else {
				break
			}
		}

		let contentStart = pos

		// Consume rest of line
		while !isAtEnd && peek() != .asciiNewline {
			advance()
		}

		let contentLength = pos - contentStart
		isAtLineStart = false

		return makeToken(.codeBlockIndent, start: contentStart, length: contentLength, line: savedLine, column: savedColumn)
	}

	private mutating func scanHruleOrSetext(_ marker: UInt8) -> Token {
		let savedLine = line
		let savedColumn = column
		let start = pos

		var count = 0
		while !isAtEnd && peek() != .asciiNewline {
			let c = peek()
			if c == marker {
				count += 1
				advance()
			} else if c == .asciiSpace || c == .asciiTab {
				advance()
			} else {
				// Invalid character, treat as text
				isAtLineStart = false
				return scanText()
			}
		}

		let length = pos - start
		isAtLineStart = false

		// Determine token type
		if marker == .asciiEquals && count >= 1 {
			return makeToken(.setextHeader1, start: start, length: length, line: savedLine, column: savedColumn)
		} else if marker == .asciiDash && count >= 3 {
			// Could be setext h2 or hrule — parser decides based on preceding context.
			// Entry via scanLineStart requires isHruleLine (count >= 3).
			return makeToken(.setextHeader2, start: start, length: length, line: savedLine, column: savedColumn)
		} else if count >= 3 {
			return makeToken(.hrule, start: start, length: length, line: savedLine, column: savedColumn)
		}

		// Fallback to text
		return makeToken(.text, start: start, length: length, line: savedLine, column: savedColumn)
	}

	/// Scan list marker (*, -, +, or 1.).
	private mutating func scanListMarker() -> Token {
		let savedLine = line
		let savedColumn = column
		let start = pos
		let c = peek()

		let type: TokenType

		if c == .asciiAsterisk || c == .asciiDash || c == .asciiPlus {
			advance()
			type = .ulMarker
		} else {
			// Ordered list: consume digits and period
			while peek().isASCIIDigit {
				advance()
			}
			advance() // Consume '.'
			type = .olMarker
		}

		// Consume following whitespace (up to 4 spaces or 1 tab)
		if peek() == .asciiTab {
			advance()
		} else {
			var spaces = 0
			while peek() == .asciiSpace && spaces < 4 {
				advance()
				spaces += 1
			}
		}

		isAtLineStart = false
		return makeToken(type, start: start, length: pos - start, line: savedLine, column: savedColumn)
	}

	private mutating func scanInline() -> Token {
		let savedLine = line
		let savedColumn = column
		let start = pos
		let c = peek()

		// Newline handling
		if c == .asciiNewline {
			advance()
			return makeToken(.newline, start: start, length: 1, line: savedLine, column: savedColumn)
		}

		// Check for hard break (two+ spaces before newline)
		if c == .asciiSpace {
			let result = isHardBreak()
			if result.isHardBreak {
				for _ in 0..<result.spaceCount {
					advance()
				}
				advance() // Consume newline
				return makeToken(.hardBreak, start: start, length: pos - start, line: savedLine, column: savedColumn)
			}
		}

		// Everything else — emphasis, links, autolinks, entities, escapes,
		// brackets, etc. — is emitted as `.text`. The inline parser
		// (InlineParser.swift) re-scans the collected text bytes and handles
		// all inline constructs directly.
		return scanText()
	}

	/// Scan a run of plain text — everything up to a newline or hard break.
	///
	/// All inline constructs (emphasis, links, autolinks, entities, escapes)
	/// are included in text runs. The inline parser handles them when it
	/// re-scans the collected bytes.
	private mutating func scanText() -> Token {
		let savedLine = line
		let savedColumn = column
		let start = pos

		let inputCount = input.count
		var scanPos = pos
		while scanPos < inputCount {
			let byte = input[scanPos]

			if byte == .asciiNewline {
				break
			}

			if byte == .asciiSpace {
				// Hard-break check: 2+ spaces followed by newline
				var spaceEnd = scanPos + 1
				while spaceEnd < inputCount && input[spaceEnd] == .asciiSpace {
					spaceEnd += 1
				}
				if spaceEnd - scanPos >= 2 && spaceEnd < inputCount && input[spaceEnd] == .asciiNewline {
					break
				}
			}

			scanPos += 1
		}

		// Batch-update tokenizer position (text has no newlines)
		let consumed = scanPos - start
		if consumed > 0 {
			pos += consumed
			column += consumed
			isAtLineStart = false
		}

		var length = consumed
		if length == 0 {
			if isAtEnd {
				return makeToken(.eof, start: start, length: 0, line: savedLine, column: savedColumn)
			}
			// Edge case: advance one character to avoid infinite loop
			advance()
			length = 1
		}

		return makeToken(.text, start: start, length: length, line: savedLine, column: savedColumn)
	}

}
