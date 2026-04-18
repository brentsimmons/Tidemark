//
//  Parser.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

struct Parser {

	private var tokenizer: Tokenizer
	private let input: [UInt8]
	private var current = Token.eof
	private var linkRefs = LinkRefTable()
	private var depth: Int = 0

	init(input: [UInt8]) {
		self.input = input
		self.tokenizer = Tokenizer(input)
	}

	/// Parse a byte array of Markdown input and return the document node.
	static func parse(_ input: [UInt8]) -> Node {
		let document = Node(kind: .document)

		guard input.count <= maxInputSize else {
			return document
		}

		let normalized = Self.normalizeLineEndings(input)
		var parser = Parser(input: normalized)
		parser.prescanLinkDefinitions()

		// Reset tokenizer for main parsing
		parser.tokenizer.reset()
		parser.advance()

		parser.parseBlocks(parent: document)

		return document
	}

	/// Parse a string of Markdown input and return the document node.
	static func parse(_ string: String) -> Node {
		parse(Array(string.utf8))
	}
}

// MARK: - Private

private extension Parser {

	static let maxNestingDepth = 100
	static let maxInputSize = 64 * 1024 * 1024 // 64 MB
	static let fourSpaces: [UInt8] = [0x20, 0x20, 0x20, 0x20]

	/// Normalize line endings: `\r\n` → `\n`, lone `\r` → `\n`.
	static func normalizeLineEndings(_ input: [UInt8]) -> [UInt8] {
		guard input.contains(.asciiCarriageReturn) else {
			return input
		}
		var result = [UInt8]()
		result.reserveCapacity(input.count)
		var i = 0
		while i < input.count {
			if input[i] == .asciiCarriageReturn {
				result.append(.asciiNewline)
				if i + 1 < input.count && input[i + 1] == .asciiNewline {
					i += 1 // Skip the \n in \r\n
				}
			} else {
				result.append(input[i])
			}
			i += 1
		}
		return result
	}

	// MARK: - Block-level HTML Tag Detection

	static let blockTagSet: Set<[UInt8]> = {
		let tags = [
			"address", "article", "aside", "base", "basefont", "blockquote", "body",
			"caption", "center", "col", "colgroup", "dd", "del", "details", "dialog",
			"dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer",
			"form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head",
			"header", "hr", "html", "iframe", "ins", "legend", "li", "link", "main",
			"math", "menu", "menuitem", "nav", "noframes", "noscript", "ol", "optgroup",
			"option", "p", "param", "pre", "script", "section", "source", "summary",
			"table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul"
		]
		return Set(tags.map { Array($0.utf8) })
	}()

	/// Check if a tag name (already lowercased) is a block-level HTML tag.
	static func isBlockTag(_ tag: [UInt8]) -> Bool {
		blockTagSet.contains(tag)
	}

	static func isHTMLBlockStart(_ input: [UInt8], offset: Int, length: Int) -> Bool {
		let end = offset + length
		guard length > 0, input[offset] == .asciiLessThan else {
			return false
		}

		var i = offset + 1

		// Check for closing tag
		if i < end && input[i] == .asciiSlash {
			i += 1
		}

		// Check for comment
		if i + 2 < end && input[i] == .asciiBang && input[i + 1] == .asciiDash && input[i + 2] == .asciiDash {
			return true
		}

		// Check for DOCTYPE
		if i < end && input[i] == .asciiBang {
			return true
		}

		// Check for processing instruction
		if i < end && input[i] == .asciiQuestionMark {
			return true
		}

		// Get tag name
		let tagStart = i
		while i < end && (input[i].isASCIIAlphanumeric || input[i] == .asciiDash) {
			i += 1
		}

		let tagLen = i - tagStart
		guard tagLen > 0 else {
			return false
		}

		let tagBytes = input[tagStart..<i].map { $0.asciiLowercased }
		if isBlockTag(tagBytes) {
			return true
		}

		// Non-block tag at start of line — block if tag doesn't close on same line
		if i < end {
			let afterTag = input[i]
			if afterTag == .asciiSpace || afterTag == .asciiTab || afterTag == .asciiGreaterThan || afterTag == .asciiSlash || afterTag == .asciiNewline {
				let tagCloses = input[i..<end].contains(.asciiGreaterThan)
				if !tagCloses {
					return true
				}
			}
		}

		return false
	}

	// MARK: - Prescan

	/// Skip to the next line in the input, returning the new position.
	func skipToNextLine(_ pos: Int) -> Int {
		var pos = pos
		while pos < input.count && input[pos] != .asciiNewline {
			pos += 1
		}
		if pos < input.count {
			pos += 1
		}
		return pos
	}

	/// Skip horizontal whitespace (spaces and tabs), returning the new position.
	func skipHorizontalWhitespace(_ pos: Int) -> Int {
		var pos = pos
		while pos < input.count && (input[pos] == .asciiSpace || input[pos] == .asciiTab) {
			pos += 1
		}
		return pos
	}

	/// Result of successfully parsing a link reference definition from raw input.
	struct LinkDefinitionResult {
		let label: [UInt8]
		let url: [UInt8]
		let title: [UInt8]?
		let endPos: Int
	}

	/// Try to parse a link reference definition starting at `pos` in `input`.
	///
	/// Expects the cursor at `[` (the opening bracket of the label). Returns
	/// nil if the bytes don't form a valid definition.
	///
	/// Used by both `prescanLinkDefinitions` (which walks raw input) and
	/// `tryParseLinkDefinition` (which is called during token-driven parsing).
	func parseLinkDefinition(at startPos: Int) -> LinkDefinitionResult? {
		var pos = startPos

		guard pos < input.count, input[pos] == .asciiLBracket else {
			return nil
		}
		pos += 1 // Skip [

		// Get label (bracket-matched, single-line)
		let labelStart = pos
		var bracketDepth = 1
		while pos < input.count && bracketDepth > 0 && input[pos] != .asciiNewline {
			if input[pos] == .asciiBackslash && pos + 1 < input.count {
				pos += 2
				continue
			}
			if input[pos] == .asciiLBracket {
				bracketDepth += 1
			} else if input[pos] == .asciiRBracket {
				bracketDepth -= 1
			}
			if bracketDepth > 0 {
				pos += 1
			}
		}

		guard bracketDepth == 0, pos < input.count else {
			return nil
		}

		let labelEnd = pos
		guard labelEnd > labelStart else {
			return nil
		}
		pos += 1 // Skip ]

		// Must be followed by :
		guard pos < input.count, input[pos] == .asciiColon else {
			return nil
		}
		pos += 1

		// Skip whitespace (including one optional newline)
		pos = skipHorizontalWhitespace(pos)
		if pos < input.count && input[pos] == .asciiNewline {
			pos = skipHorizontalWhitespace(pos + 1)
		}

		// Get URL
		var urlStart = pos
		let inAngle = pos < input.count && input[pos] == .asciiLessThan

		if inAngle {
			pos += 1
			urlStart = pos
			while pos < input.count && input[pos] != .asciiGreaterThan && input[pos] != .asciiNewline {
				pos += 1
			}
			guard pos < input.count, input[pos] == .asciiGreaterThan else {
				return nil
			}
		} else {
			while pos < input.count && !input[pos].isASCIIWhitespace {
				pos += 1
			}
		}

		let urlEnd = pos
		guard urlEnd > urlStart else {
			return nil
		}

		if inAngle && pos < input.count && input[pos] == .asciiGreaterThan {
			pos += 1
		}

		pos = skipHorizontalWhitespace(pos)

		// Optional title
		var titleBytes: [UInt8]?
		if pos < input.count &&
			(input[pos] == .asciiDoubleQuote || input[pos] == .asciiSingleQuote || input[pos] == .asciiLParen) {
			let quote = input[pos]
			let closeQuote: UInt8 = (quote == .asciiLParen) ? .asciiRParen : quote
			let titleStart = pos + 1

			var lineEnd = titleStart
			while lineEnd < input.count && input[lineEnd] != .asciiNewline {
				lineEnd += 1
			}

			// Find last occurrence of close quote on this line
			var lastQuotePos = lineEnd
			var index = lineEnd
			while index > titleStart {
				if input[index - 1] == closeQuote {
					lastQuotePos = index - 1
					break
				}
				index -= 1
			}

			if lastQuotePos < lineEnd {
				titleBytes = Array(input[titleStart..<lastQuotePos])
				pos = lastQuotePos + 1
			}
		}

		pos = skipHorizontalWhitespace(pos)

		// Must end with newline or EOF
		guard pos >= input.count || input[pos] == .asciiNewline else {
			return nil
		}

		let label = Array(input[labelStart..<labelEnd])
		let url = Array(input[urlStart..<urlEnd])
		return LinkDefinitionResult(label: label, url: url, title: titleBytes, endPos: pos)
	}

	/// Pre-scan the input to collect all link reference definitions.
	/// This must happen before block parsing because references can
	/// be used before they are defined: `[click here][1]` can appear
	/// above `[1]: http://example.com` in the source.
	mutating func prescanLinkDefinitions() {
		var pos = 0

		while pos < input.count {
			// Must be at start of line
			if pos > 0 && input[pos - 1] != .asciiNewline {
				pos = skipToNextLine(pos)
				continue
			}

			let lineStart = pos

			// Skip up to 3 spaces
			var spaces = 0
			while pos < input.count && spaces < 3 && input[pos] == .asciiSpace {
				spaces += 1
				pos += 1
			}

			if let result = parseLinkDefinition(at: pos) {
				linkRefs.add(label: result.label, url: result.url, title: result.title)
				pos = result.endPos
				if pos < input.count {
					pos += 1
				}
			} else {
				pos = skipToNextLine(lineStart)
			}
		}
	}

	// MARK: - Token Helpers

	mutating func advance() {
		current = tokenizer.next()
	}

	func check(_ type: TokenType) -> Bool {
		current.type == type
	}

	@discardableResult
	mutating func match(_ type: TokenType) -> Bool {
		if check(type) {
			advance()
			return true
		}
		return false
	}

	func isAtBlockStart() -> Bool {
		switch current.type {
		case .atxHeader1, .atxHeader2, .atxHeader3,
			 .atxHeader4, .atxHeader5, .atxHeader6,
			 .blockquote, .codeBlockIndent, .hrule,
			 .ulMarker, .olMarker, .blankLine,
			 .setextHeader1, .setextHeader2:
			return true
		default:
			return false
		}
	}

	/// Check if the current token's content starts with a list marker pattern.
	/// Reads directly from `input` to avoid allocating an intermediate array.
	func currentTokenStartsWithListMarker() -> Bool {
		let start = current.start
		let length = current.length
		guard length > 0 else {
			return false
		}

		let first = input[start]

		// Unordered list marker (*, -, +) followed by space/tab
		if (first == .asciiAsterisk || first == .asciiDash || first == .asciiPlus) &&
			length > 1 && (input[start + 1] == .asciiSpace || input[start + 1] == .asciiTab) {
			return true
		}

		// Ordered list marker (digit(s) followed by . and space/tab)
		var i = 0
		while i < length && input[start + i].isASCIIDigit {
			i += 1
		}
		if i > 0 && i < length && input[start + i] == .asciiDot &&
			i + 1 < length && (input[start + i + 1] == .asciiSpace || input[start + i + 1] == .asciiTab) {
			return true
		}

		return false
	}

	// MARK: - Block Parsing

	mutating func parseBlocks(parent: Node) {
		while !check(.eof) {
			while match(.blankLine) {
				// Skip blank lines at block level
			}

			if check(.eof) {
				break
			}

			if let block = parseBlock() {
				parent.appendChild(block)
			}
		}
	}

	mutating func parseBlock() -> Node? {
		// Check for HTML block at line start (quick byte check avoids
		// scanning for the line length on every non-HTML text token)
		if check(.text) && input[current.start] == .asciiLessThan {
			let tokenStart = current.start
			var lineLen = 0
			while tokenStart + lineLen < input.count && input[tokenStart + lineLen] != .asciiNewline {
				lineLen += 1
			}
			if Self.isHTMLBlockStart(input, offset: tokenStart, length: lineLen) {
				return parseHTMLBlock()
			}
		}

		switch current.type {
		case .atxHeader1, .atxHeader2, .atxHeader3,
			 .atxHeader4, .atxHeader5, .atxHeader6:
			return parseATXHeading()
		case .blockquote:
			return parseBlockquote()
		case .codeBlockIndent:
			return parseCodeBlock()
		case .hrule:
			return parseHrule()
		case .setextHeader2:
			// A standalone --- at block level (not preceded by paragraph
			// text) can't be a setext underline — it's a horizontal rule.
			return parseHrule()
		case .setextHeader1:
			// A standalone === at block level can't be a setext underline
			// and isn't a valid hrule — fall through to paragraph.
			return parseParagraph()
		case .ulMarker, .olMarker:
			return parseList()
		default:
			return parseParagraph()
		}
	}

	// MARK: - HTML Block

	/// Extract the tag name from an HTML block's opening line.
	func extractHTMLTagName(_ line: [UInt8]) -> [UInt8]? {
		guard !line.isEmpty, line[0] == .asciiLessThan else {
			return nil
		}
		var i = 1

		// Skip optional closing slash
		if i < line.count && line[i] == .asciiSlash {
			i += 1
		}

		let tagStart = i
		while i < line.count && (line[i].isASCIIAlphanumeric || line[i] == .asciiDash) {
			i += 1
		}

		let tagLen = i - tagStart
		guard tagLen > 0 else {
			return nil
		}

		// Lowercase the tag name in a single allocation
		return line[tagStart..<i].map { $0.asciiLowercased }
	}

	/// Check if the collected content contains a closing tag for the given tag name.
	func contentHasClosingTag(_ data: [UInt8], tagName: [UInt8]) -> Bool {
		let tagLen = tagName.count
		guard data.count >= tagLen + 3 else {
			return false
		}

		for i in 0..<data.count {
			guard i + 2 + tagLen < data.count else {
				break
			}
			if data[i] == .asciiLessThan && data[i + 1] == .asciiSlash { // "</"
				var matchFound = true
				for j in 0..<tagLen {
					let c = data[i + 2 + j].asciiLowercased
					if c != tagName[j] {
						matchFound = false
						break
					}
				}
				if matchFound {
					let after = i + 2 + tagLen
					if after < data.count && data[after] == .asciiGreaterThan {
						return true
					}
				}
			}
		}
		return false
	}

	mutating func parseHTMLBlock() -> Node {
		let html = Node(kind: .htmlBlock([]))

		// Determine if this is a block-level tag
		let tokenStart = current.start
		var lineLen = 0
		while tokenStart + lineLen < input.count && input[tokenStart + lineLen] != .asciiNewline {
			lineLen += 1
		}
		let lineBytes = Array(input[tokenStart..<tokenStart + lineLen])

		let tagName = extractHTMLTagName(lineBytes)
		let needsClosingTag: Bool
		if let tagName {
			needsClosingTag = Self.isBlockTag(tagName)
		} else {
			needsClosingTag = false
		}

		var content = ByteArray()

		while !check(.eof) {
			if check(.blankLine) {
				if !needsClosingTag {
					break
				}
				if let tagName, contentHasClosingTag(content.bytes, tagName: tagName) {
					break
				}
				content.append(.asciiNewline)
				advance()
				continue
			}

			// For CODE_BLOCK_INDENT tokens, restore the stripped indentation
			if current.type == .codeBlockIndent {
				content.append(Self.fourSpaces)
			}

			// Add token content
			if current.length > 0 {
				content.append(input, start: current.start, length: current.length)
			}
			advance()

			// Handle newlines
			if check(.newline) {
				content.append(.asciiNewline)
				advance()
			}
		}

		// Add trailing newline if not present
		let bytes = content.bytes
		if !bytes.isEmpty && bytes[bytes.count - 1] != .asciiNewline {
			content.append(.asciiNewline)
		}

		html.kind = .htmlBlock(content.bytes)
		return html
	}

	// MARK: - ATX Heading

	mutating func parseATXHeading() -> Node {
		let level = current.type.headingLevel ?? 1
		let heading = Node(kind: .heading(level: level))

		advance() // Consume header marker

		// Collect heading content until newline
		var content = ByteArray()

		while !check(.eof) && !check(.newline) && !check(.blankLine) {
			if current.length > 0 {
				content.append(input, start: current.start, length: current.length)
			}
			advance()
		}

		// Strip trailing # and spaces
		let allBytes = content.bytes
		var end = allBytes.count
		while end > 0 && (allBytes[end - 1] == .asciiHash || allBytes[end - 1] == .asciiSpace) {
			end -= 1
		}

		// Parse inline content
		if end > 0 {
			let trimmed = (end == allBytes.count) ? allBytes : Array(allBytes[0..<end])
			parseInlines(parent: heading, text: trimmed, linkRefs: linkRefs)
		}

		// Consume trailing newline
		match(.newline)

		return heading
	}

	// MARK: - Paragraph

	mutating func parseParagraph() -> Node? {
		// First, try to parse as link definition
		if tryParseLinkDefinition() {
			return nil
		}

		let paragraph = Node(kind: .paragraph)
		var content = ByteArray()
		var checkSetext = true

		while !check(.eof) && !check(.blankLine) {
			// Check for setext underline
			if checkSetext && content.count > 0 &&
				(check(.setextHeader1) || check(.setextHeader2)) {
				let heading = parseSetextHeading()
				let contentBytes = content.bytesTrimmingTrailingWhitespace()
				if !contentBytes.isEmpty {
					parseInlines(parent: heading, text: contentBytes, linkRefs: linkRefs)
				}
				return heading
			}

			// Check for block-level interrupt (but NOT list markers —
			// Gruber's Markdown allows list-like lines inside paragraphs
			// without starting a list, e.g. "I use the 1. notation often.")
			if isAtBlockStart() && !check(.setextHeader1) && !check(.setextHeader2) &&
				!check(.ulMarker) && !check(.olMarker) {
				break
			}

			// Append token content
			if current.type == .newline {
				if content.count > 0 {
					content.append(.asciiNewline)
				}
				checkSetext = true
				advance()
			} else if current.type == .hardBreak {
				content.append(staticString: "  \n")
				checkSetext = false
				advance()
			} else {
				appendCurrentTokenBytes(to: &content)
				checkSetext = false
				advance()
			}
		}

		let contentBytes = content.bytesTrimmingTrailingWhitespace()

		guard !contentBytes.isEmpty else {
			return nil
		}

		parseInlines(parent: paragraph, text: contentBytes, linkRefs: linkRefs)

		return paragraph
	}

	// MARK: - Setext Heading

	mutating func parseSetextHeading() -> Node {
		let level = (current.type == .setextHeader1) ? 1 : 2
		let heading = Node(kind: .heading(level: level))
		advance() // Consume underline
		match(.newline)
		return heading
	}

	// MARK: - Blockquote

	mutating func parseBlockquote() -> Node {
		let blockquoteNode = Node(kind: .blockquote)
		var content = ByteArray()
		var sawBlankLine = false

		while true {
			if check(.blockquote) {
				sawBlankLine = false
				advance() // Consume > marker

				// Handle blank line within blockquote
				if check(.blankLine) {
					content.append(.asciiNewline)
					advance()
					sawBlankLine = true
					continue
				}

				// Collect line content
				while !check(.eof) && !check(.newline) && !check(.blankLine) {
					if current.type == .codeBlockIndent {
						content.append(Self.fourSpaces)
					}
					appendCurrentTokenBytes(to: &content)
					advance()
				}

				// Add newline
				content.append(.asciiNewline)

				// Consume newline if present
				match(.newline)

				// Blank line ends the blockquote
				if check(.blankLine) {
					break
				}
			} else if check(.text) && content.count > 0 && !sawBlankLine {
				// Lazy continuation: a text line without > marker
				// continues the preceding blockquote paragraph.
				while !check(.eof) && !check(.newline) && !check(.blankLine) {
					appendCurrentTokenBytes(to: &content)
					advance()
				}
				content.append(.asciiNewline)
				match(.newline)

				if check(.blankLine) {
					break
				}
			} else {
				break
			}
		}

		// Recursively parse blockquote content: the collected bytes
		// are the blockquote's "inner document" with > markers stripped.
		// Re-parsing through a fresh Parser lets nested block structures
		// (paragraphs, lists, code blocks, nested blockquotes) emerge
		// naturally without duplicating block-level logic.
		let contentBytes = content.bytes
		if !contentBytes.isEmpty && depth < Self.maxNestingDepth {
			var subParser = Parser(input: contentBytes)
			subParser.depth = depth + 1
			subParser.linkRefs.merge(from: linkRefs)
			subParser.advance()
			subParser.parseBlocks(parent: blockquoteNode)
			linkRefs.merge(from: subParser.linkRefs)
		}

		return blockquoteNode
	}

	// MARK: - Code Block

	mutating func parseCodeBlock() -> Node {
		let code = Node(kind: .codeBlock([]))
		var content = ByteArray()

		while true {
			if check(.codeBlockIndent) {
				let lenBefore = content.count
				let hasContent = current.length > 0

				if hasContent {
					content.append(input, start: current.start, length: current.length)
				}
				advance()

				if hasContent || lenBefore > 0 {
					content.append(.asciiNewline)
				}

				match(.newline)
			} else if check(.blankLine) {
				var blankCount = 0
				while check(.blankLine) {
					blankCount += 1
					advance()
				}
				if check(.codeBlockIndent) {
					for _ in 0..<blankCount {
						content.append(.asciiNewline)
					}
				} else {
					break
				}
			} else {
				break
			}
		}

		// Strip trailing newlines beyond one
		let allBytes = content.bytes
		var end = allBytes.count
		while end > 1 && allBytes[end - 1] == .asciiNewline && allBytes[end - 2] == .asciiNewline {
			end -= 1
		}

		code.kind = .codeBlock(end == allBytes.count ? allBytes : Array(allBytes[0..<end]))
		return code
	}

	// MARK: - Horizontal Rule

	mutating func parseHrule() -> Node {
		let hruleNode = Node(kind: .hrule)
		advance() // Consume hrule/setext token
		match(.newline)
		return hruleNode
	}

	// MARK: - List

	mutating func parseList() -> Node {
		let listType: ListType = (current.type == .ulMarker) ? .unordered : .ordered
		var listInfo = ListInfo(type: listType, marker: tokenByte(), tight: true)
		let list = Node(kind: .list(listInfo))

		let expectedMarker: TokenType = (listType == .unordered) ? .ulMarker : .olMarker

		while check(expectedMarker) {
			var consumedBlank = false
			if let item = parseListItem(listType: listType, consumedBlank: &consumedBlank) {
				list.appendChild(item)

				// If item has multiple paragraph children, list is loose
				var paragraphCount = 0
				for child in item.children where child.kind == .paragraph {
					paragraphCount += 1
				}
				if paragraphCount > 1 {
					listInfo.tight = false
				}

				if consumedBlank && check(expectedMarker) {
					listInfo.tight = false
				}
			}

			// Check for blank line between items
			if check(.blankLine) {
				while match(.blankLine) {
					// Skip blank lines
				}
				if check(expectedMarker) {
					listInfo.tight = false
				}
			}
		}

		list.kind = .list(listInfo)
		return list
	}

	/// Parse a nested list from indented content.
	mutating func parseNestedList(for item: Node) {
		var nested = ByteArray()

		while check(.codeBlockIndent) {
			if current.length > 0 {
				nested.append(input, start: current.start, length: current.length)
				nested.append(.asciiNewline)
			}
			advance()
			match(.newline)
		}

		let nestedBytes = nested.bytes
		guard !nestedBytes.isEmpty, depth < Self.maxNestingDepth else {
			return
		}

		var nestedParser = Parser(input: nestedBytes)
		nestedParser.depth = depth + 1
		nestedParser.linkRefs.merge(from: linkRefs)
		nestedParser.advance()

		if nestedParser.check(.ulMarker) || nestedParser.check(.olMarker) {
			let nestedList = nestedParser.parseList()
			item.appendChild(nestedList)
		}
	}

	// MARK: - List Item

	mutating func parseListItem(listType: ListType, consumedBlank: inout Bool) -> Node? {
		consumedBlank = false

		let item = Node(kind: .listItem)
		advance() // Consume list marker

		var content = ByteArray()
		var hasNestedList = false

		// Parse first paragraph content
		hasNestedList = collectListItemContent(&content, listType: listType)

		// Trim and create first paragraph
		var contentBytes = content.bytesTrimmingTrailingWhitespace()
		if !contentBytes.isEmpty {
			let paragraph = Node(kind: .paragraph)
			parseInlines(parent: paragraph, text: contentBytes, linkRefs: linkRefs)
			item.appendChild(paragraph)
		}

		// Check for continuation paragraphs (blank line followed by indented content)
		while check(.blankLine) {
			while match(.blankLine) {
				consumedBlank = true
			}

			guard check(.codeBlockIndent) else {
				break
			}

			if currentTokenStartsWithListMarker() {
				hasNestedList = true
				break
			}

			// Collect continuation paragraph (no code spans in indented continuations)
			var continuation = ByteArray()
			while check(.codeBlockIndent) {
				appendCurrentTokenBytes(to: &continuation)
				advance()
				if check(.newline) {
					continuation.append(.asciiNewline)
					advance()
				}
			}

			contentBytes = continuation.bytesTrimmingTrailingWhitespace()
			if !contentBytes.isEmpty {
				let paragraph = Node(kind: .paragraph)
				parseInlines(parent: paragraph, text: contentBytes, linkRefs: linkRefs)
				item.appendChild(paragraph)
			}
		}

		if hasNestedList {
			parseNestedList(for: item)
		}

		return item
	}

	/// Collect the first paragraph content for a list item.
	/// Returns true if a nested list was detected.
	mutating func collectListItemContent(_ content: inout ByteArray, listType: ListType) -> Bool {
		while !check(.eof) && !check(.blankLine) {
			if check(.ulMarker) || check(.olMarker) {
				break
			}

			if current.type == .newline {
				content.append(.asciiNewline)
				advance()
				if check(.codeBlockIndent) {
					if currentTokenStartsWithListMarker() {
						return true
					}
				} else if isAtBlockStart() {
					break
				}
			} else if current.type == .codeBlockIndent {
				if currentTokenStartsWithListMarker() {
					return true
				}
				appendCurrentTokenBytes(to: &content)
				advance()
			} else {
				appendCurrentTokenBytes(to: &content)
				advance()
			}
		}
		return false
	}

	// MARK: - Link Definition

	mutating func tryParseLinkDefinition() -> Bool {
		guard tokenByte() == .asciiLBracket else {
			return false
		}

		guard let result = parseLinkDefinition(at: current.start) else {
			return false
		}

		linkRefs.add(label: result.label, url: result.url, title: result.title)

		// Advance the tokenizer past the consumed content
		while !check(.eof) && !check(.newline) && !check(.blankLine) {
			advance()
		}
		match(.newline)

		return true
	}

	// MARK: - Helpers

	func tokenByte() -> UInt8 {
		guard current.start < input.count else {
			return 0
		}
		return input[current.start]
	}

	/// Append the current token's bytes directly into a ByteArray without
	/// allocating an intermediate [UInt8].
	func appendCurrentTokenBytes(to buffer: inout ByteArray) {
		if current.length > 0 {
			buffer.append(input, start: current.start, length: current.length)
		}
	}
}
