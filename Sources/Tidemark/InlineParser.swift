//
//  InlineParser.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

// MARK: - Why This Is Separate From Parser
//
// Markdown parsing is conventionally split into two stages:
//
//   1. Block parser (Parser.swift) — identifies line-level structure:
//      paragraphs, headings, blockquotes, lists, code blocks. It collects
//      the raw text content of each block but doesn't interpret anything
//      *inside* that text.
//
//   2. Inline parser (this file) — takes the collected text of a block
//      and parses inline constructs: emphasis (`*` and `_`), strong,
//      code spans (`` ` ``), links, images, autolinks, HTML tags,
//      backslash escapes, and hard/soft line breaks.
//
// The split is driven by the spec itself: block boundaries depend on
// whole-line patterns, while inline matching works byte-by-byte with
// context (e.g., the emphasis algorithm needs a delimiter stack spanning
// the entire block's text).
//
// The main complexity here is emphasis matching. Runs of `*`/`_` are
// collected into a linked stack while scanning; then a second pass
// (`processEmphasis`) matches openers with closers and rewrites the node
// tree into `.emphasis`/`.strong` nodes. The pairing rules (what counts
// as an opener or closer, and how to resolve ambiguous cases like
// `*foo*bar*`) look at the characters immediately around each run.

/// Parse inline Markdown content within a block-level node.
///
/// - Parameters:
///   - parent: The block-level node to which parsed inline children are appended.
///   - text: The collected byte content of the block.
///   - linkRefs: Table of link reference definitions for resolving `[text][ref]`.
func parseInlines(parent: Node, text: [UInt8], linkRefs: LinkRefTable) {
	var inlineParser = InlineParser(linkRefs: linkRefs, parent: parent, text: text)
	inlineParser.parse()
}

// MARK: - Delimiter Stack

/// A record of one `*` or `_` delimiter run seen during inline scanning.
///
/// As `parseEmphasis` encounters each run, it creates a text node
/// containing the raw delimiter characters (e.g., `**`) and records a
/// `Delimiter` describing that node's position and properties. The
/// records form a doubly-linked list — the "delimiter stack" — in the
/// order they appear in the text.
///
/// After scanning completes, `processEmphasis` walks the stack and
/// matches openers with closers, rewriting the text nodes into
/// `.emphasis` or `.strong` nodes that contain the intervening content.
/// Delimiters that get consumed (fully used) or skipped (no match) have
/// their `active` flag set to false so later passes ignore them.
///
/// Both `prev` and `next` pointers are needed:
/// - `next` drives forward iteration (process each closer in order) and
///   the walk from a matched opener to its closer to deactivate the
///   delimiters in between.
/// - `prev` lets each closer scan backward to find its nearest compatible
///   opener in O(1) per step — this is the core matching operation.
///   Without `prev` we'd need a separate opener stack or O(n) backward
///   traversals from the head.
///
/// This is a reference type because:
/// - The linked list needs identity-stable nodes (we use `!==` to detect
///   the "bottom" sentinel in `openersBottom`).
/// - `active` is mutated from `processEmphasis`, which holds references
///   to delimiters both directly and through `prev`/`next` chains.
private final class Delimiter {
	let textNode: Node
	let character: UInt8
	let canOpen: Bool
	let canClose: Bool
	var active: Bool = true
	weak var prev: Delimiter?
	var next: Delimiter?

	init(textNode: Node, character: UInt8, canOpen: Bool, canClose: Bool) {
		self.textNode = textNode
		self.character = character
		self.canOpen = canOpen
		self.canClose = canClose
	}
}

// MARK: - Inline Parser

private struct InlineParser {

	/// Cap on the number of `*`/`_` delimiter runs tracked per block, so
	/// pathological input (e.g., a million consecutive asterisks) can't
	/// allocate a million `Delimiter` class instances. Beyond this cap,
	/// additional delimiter runs are emitted as plain text. Real documents
	/// have at most a few dozen delimiter runs per paragraph.
	static let maxDelimiterCount = 10_000
	static let mailtoPrefix: [UInt8] = Array("mailto:".utf8)

	let linkRefs: LinkRefTable
	let parent: Node
	let text: [UInt8]
	var pos: Int = 0
	var delimiterStack: Delimiter?
	var delimiterTail: Delimiter?
	var delimiterCount: Int = 0

	init(linkRefs: LinkRefTable, parent: Node, text: [UInt8]) {
		self.linkRefs = linkRefs
		self.parent = parent
		self.text = text
	}

	/// Scan the block's text and emit inline nodes as children of `parent`.
	///
	/// Strategy: accumulate "plain text" bytes between special markers.
	/// When we hit a special marker, flush any pending plain text as a
	/// text node, then dispatch to the specific parser for that construct.
	///
	/// After scanning, a separate pass (`processEmphasis`) matches
	/// emphasis/strong delimiters and rewrites the node tree.
	mutating func parse() {
		var textStart = pos

		while !isAtEnd {
			let c = peek()
			var handled = false

			switch c {
			case .asciiBackslash:
				flushText(from: textStart, to: pos)
				handled = parseEscape()
				textStart = pos

			case .asciiBacktick:
				flushText(from: textStart, to: pos)
				handled = parseCodeSpan()
				textStart = pos

			case .asciiAsterisk, .asciiUnderscore:
				flushText(from: textStart, to: pos)
				handled = parseEmphasis()
				textStart = pos

			case .asciiLBracket:
				flushText(from: textStart, to: pos)
				handled = parseLink()
				textStart = pos

			case .asciiBang where peekN(1) == .asciiLBracket:
				flushText(from: textStart, to: pos)
				handled = parseImage()
				textStart = pos

			case .asciiLessThan:
				flushText(from: textStart, to: pos)
				handled = parseAutolink()
				if !handled {
					handled = parseHTMLTag()
				}
				textStart = pos

			case .asciiNewline:
				handled = parseLineBreak(textStart: &textStart)

			default:
				break
			}

			if !handled {
				advance()
			}
		}

		flushText(from: textStart, to: pos)
		processEmphasis()
	}

	// MARK: - Character Access

	func peek() -> UInt8 {
		guard pos < text.count else {
			return 0
		}
		return text[pos]
	}

	func peekN(_ n: Int) -> UInt8 {
		guard pos + n < text.count else {
			return 0
		}
		return text[pos + n]
	}

	@discardableResult
	mutating func advance() -> UInt8 {
		guard pos < text.count else {
			return 0
		}
		let c = text[pos]
		pos += 1
		return c
	}

	var isAtEnd: Bool {
		pos >= text.count
	}

	// MARK: - Main Parse Loop

	/// Append `text[start..<end]` to the parent as a text node, if non-empty.
	mutating func flushText(from start: Int, to end: Int) {
		if end > start {
			parent.appendTextChild(text, start: start, length: end - start)
		}
	}

	/// Handle a newline: emit either a hard break or a soft break.
	///
	/// Examples (`␣` = space, `⏎` = newline):
	/// - Hard break: `line one␣␣⏎line two` → `line one<br>line two`
	///   (two or more trailing spaces before the newline)
	/// - Soft break: `line one⏎line two` → `line one\nline two`
	///   (rendered as a single space by the browser)
	mutating func parseLineBreak(textStart: inout Int) -> Bool {
		let isHardBreak = pos >= 2 && text[pos - 1] == .asciiSpace && text[pos - 2] == .asciiSpace

		if isHardBreak {
			// Trim trailing spaces from the text run.
			var textEnd = pos
			while textEnd > textStart && text[textEnd - 1] == .asciiSpace {
				textEnd -= 1
			}
			flushText(from: textStart, to: textEnd)
			advance()
			parent.appendChild(Node(kind: .hardbreak))
		} else {
			flushText(from: textStart, to: pos)
			advance()
			parent.appendChild(Node(kind: .softbreak))
		}
		textStart = pos
		return true
	}

	// MARK: - Escape

	/// Parse a backslash escape sequence.
	///
	/// Example: `\*` emits a literal `*` (not emphasis).
	/// If the character after `\` isn't escapable, the backslash is kept as text.
	mutating func parseEscape() -> Bool {
		advance() // Consume backslash

		guard !isAtEnd else {
			parent.appendTextChild([.asciiBackslash])
			return true
		}

		let c = peek()

		// Check if escapable
		if MarkdownBytes.isEscapable(c) {
			advance()
			parent.appendTextChild([c])
			return true
		}

		// Not escapable, output backslash literally
		parent.appendTextChild([.asciiBackslash])
		return true
	}

	// MARK: - Code Span

	/// Parse a backtick-delimited code span.
	///
	/// Example: `` `code` `` → `<code>code</code>`.
	///
	/// Multiple backticks allow backticks inside the content:
	/// `` `` `code with \` backtick` `` `` → `<code>code with \` backtick`</code>`.
	/// The number of opening backticks must exactly match the closing run.
	/// Unmatched openers are emitted as literal backticks.
	mutating func parseCodeSpan() -> Bool {
		let start = pos

		// Count opening backticks
		var backticks = 0
		while peek() == .asciiBacktick {
			backticks += 1
			advance()
		}

		let contentStart = pos

		// Find matching closing backticks
		while !isAtEnd {
			if peek() == .asciiBacktick {
				let closeStart = pos
				var closeCount = 0
				while peek() == .asciiBacktick {
					closeCount += 1
					advance()
				}
				if closeCount == backticks {
					// Found matching close — calculate trim bounds, allocate once
					var trimStart = contentStart
					var trimEnd = closeStart
					if trimEnd - trimStart > 2 && text[trimStart] == .asciiSpace && text[trimEnd - 1] == .asciiSpace {
						trimStart += 1
						trimEnd -= 1
					}
					let code = Node(kind: .codeSpan(Array(text[trimStart..<trimEnd])))
					parent.appendChild(code)
					return true
				}
				// Not matching, continue
			} else {
				advance()
			}
		}

		// No closing found, output backticks as text
		pos = start
		for _ in 0..<backticks {
			advance()
		}
		parent.appendTextChild([UInt8](repeating: .asciiBacktick, count: backticks))
		return true
	}

	// MARK: - Emphasis

	/// Scan a run of `*` or `_` delimiters and push it onto the delimiter stack.
	///
	/// Examples (actual rewriting happens later in `processEmphasis`):
	/// - `*text*` → `<em>text</em>`
	/// - `**text**` → `<strong>text</strong>`
	/// - `***text***` → `<strong><em>text</em></strong>`
	///
	/// Whether a run can open or close emphasis depends on the characters
	/// immediately before and after the run:
	///
	/// - Can open: not followed by whitespace; either not followed by
	///   punctuation, or preceded by whitespace/punctuation.
	/// - Can close: the symmetric opposite.
	///
	/// Underscore has stricter rules — it can't open or close mid-word,
	/// matching Gruber's "underscores within words are not converted"
	/// rule (so `snake_case` stays intact).
	mutating func parseEmphasis() -> Bool {
		let c = peek()
		let start = pos

		// Count delimiter run
		var count = 0
		while peek() == c {
			count += 1
			advance()
		}

		// Determine if can open/close. Treat "no byte there" (start of text
		// or EOF) as whitespace, matching how Markdown treats document edges.
		let before: UInt8 = (start > 0) ? text[start - 1] : .asciiSpace
		let peeked = peek()
		let after: UInt8 = peeked == 0 ? .asciiSpace : peeked

		let beforeIsWhitespace = before.isASCIIWhitespace
		let afterIsWhitespace = after.isASCIIWhitespace

		let leftFlanking = !afterIsWhitespace &&
			(!after.isASCIIPunctuation || beforeIsWhitespace || before.isASCIIPunctuation)
		let rightFlanking = !beforeIsWhitespace &&
			(!before.isASCIIPunctuation || afterIsWhitespace || after.isASCIIPunctuation)

		var canOpen = leftFlanking
		var canClose = rightFlanking

		// For underscore, stricter rules
		if c == .asciiUnderscore {
			canOpen = leftFlanking && (!rightFlanking || before.isASCIIPunctuation)
			canClose = rightFlanking && (!leftFlanking || after.isASCIIPunctuation)
		}

		// Add delimiter text node
		let textNode = Node(kind: .text([UInt8](repeating: c, count: count)))
		parent.appendChild(textNode)

		if canOpen || canClose {
			pushDelimiter(textNode: textNode, character: c, canOpen: canOpen, canClose: canClose)
		}

		return true
	}

	mutating func pushDelimiter(textNode: Node, character: UInt8, canOpen: Bool, canClose: Bool) {
		guard delimiterCount < Self.maxDelimiterCount else {
			return
		}

		let d = Delimiter(textNode: textNode, character: character, canOpen: canOpen, canClose: canClose)

		if delimiterStack == nil {
			delimiterStack = d
		} else {
			delimiterTail?.next = d
			d.prev = delimiterTail
		}
		delimiterTail = d
		delimiterCount += 1
	}

	/// Return the byte count of a text node's literal content.
	func literalLength(_ node: Node) -> Int {
		if case .text(let bytes) = node.kind {
			return bytes.count
		}
		return 0
	}

	// MARK: - Process Emphasis

	/// Walk the delimiter stack and match openers with closers to build
	/// emphasis (`<em>`) and strong (`<strong>`) nodes.
	///
	/// For each delimiter that can close, look backwards through the
	/// stack for a matching opener. If found, wrap the intervening nodes
	/// in an emphasis (1 delimiter) or strong (2 delimiters) node and
	/// reduce the delimiter counts on both sides. If no match, mark the
	/// closer inactive and move on.
	///
	/// The `openersBottom` array is a per-category "don't look past this
	/// point" memo that avoids O(n²) behavior on pathological input like
	/// `*a_b*c_d*...`. It's indexed by (character, can-both-open-and-close).
	mutating func processEmphasis() {
		// openers_bottom indices:
		//   0 = '*' closers that can both open and close
		//   1 = '_' closers that can both open and close
		//   2 = '*' closers that can only close
		//   3 = '_' closers that can only close
		var openersBottom: [Delimiter?] = [nil, nil, nil, nil]

		var closer = delimiterStack

		while let currentCloser = closer {
			if !currentCloser.canClose || !currentCloser.active {
				closer = currentCloser.next
				continue
			}

			// Determine which openers_bottom index to use
			let bottomIndex: Int
			if currentCloser.character == .asciiAsterisk { // '*'
				bottomIndex = (currentCloser.canOpen && currentCloser.canClose) ? 0 : 2
			} else {
				bottomIndex = (currentCloser.canOpen && currentCloser.canClose) ? 1 : 3
			}

			// Look for matching opener
			var opener = currentCloser.prev
			let bottom = openersBottom[bottomIndex]
			var found = false

			while let currentOpener = opener, currentOpener !== bottom {
				if currentOpener.character == currentCloser.character &&
					currentOpener.canOpen && currentOpener.active {
					// Check the "sum of delimiters" rule
					if (currentOpener.canOpen && currentOpener.canClose) ||
						(currentCloser.canOpen && currentCloser.canClose) {
						let openerCount = literalLength(currentOpener.textNode)
						let closerCount = literalLength(currentCloser.textNode)
						if (openerCount + closerCount) % 3 == 0 &&
							(openerCount % 3 != 0 || closerCount % 3 != 0) {
							opener = currentOpener.prev
							continue
						}
					}
					found = true
					break
				}
				opener = currentOpener.prev
			}

			guard found, let matchedOpener = opener else {
				openersBottom[bottomIndex] = currentCloser.prev
				if !currentCloser.canOpen {
					currentCloser.active = false
				}
				closer = currentCloser.next
				continue
			}

			let openerNode = matchedOpener.textNode
			let closerNode = currentCloser.textNode

			let openerCount = literalLength(openerNode)
			let closerCount = literalLength(closerNode)

			// Determine how many delimiters to use — odd count gets emphasis (inner) first
			let minCount = min(openerCount, closerCount)
			let useDelimiters = (minCount >= 2 && minCount.isMultiple(of: 2)) ? 2 : 1

			let emphasisNode = Node(kind: (useDelimiters == 2) ? .strong : .emphasis)

			// Move all nodes between opener and closer into emphasis node
			var node = openerNode.next
			while let n = node, n !== closerNode {
				let next = n.next
				n.unlink()
				emphasisNode.appendChild(n)
				node = next
			}

			// Insert emphasis after opener text node
			emphasisNode.insertAfter(openerNode)

			// Update opener text node
			let newOpenerCount = openerCount - useDelimiters
			if newOpenerCount > 0 {
				openerNode.kind = .text([UInt8](repeating: matchedOpener.character, count: newOpenerCount))
			} else {
				openerNode.unlink()
				matchedOpener.active = false
			}

			// Update closer text node
			let newCloserCount = closerCount - useDelimiters
			if newCloserCount > 0 {
				closerNode.kind = .text([UInt8](repeating: currentCloser.character, count: newCloserCount))
			} else {
				closerNode.unlink()
				currentCloser.active = false
			}

			// Deactivate delimiters between opener and closer
			var d = matchedOpener.next
			while let dd = d, dd !== currentCloser {
				dd.active = false
				d = dd.next
			}

			// If closer still has delimiters, continue processing it
			if newCloserCount > 0 {
				continue
			}

			closer = currentCloser.next
		}
	}

	// MARK: - Link

	/// Create a link node from a reference, parsing text as inlines.
	mutating func makeLinkFromRef(_ ref: LinkRef, textStart: Int, textEnd: Int) -> Node {
		let link = Node(kind: .link(LinkInfo(urlBytes: ref.urlBytes, titleBytes: ref.titleBytes)))
		if textEnd > textStart {
			var subIP = InlineParser(linkRefs: linkRefs, parent: link, text: Array(text[textStart..<textEnd]))
			subIP.parse()
		}
		return link
	}

	/// Abort a link/image/autolink attempt: restore the cursor to `start`,
	/// consume the opening byte (`[`, `!`, or `<`) and emit it as literal
	/// text so the main loop continues past it.
	///
	/// Returns `true` since the opening byte is now handled.
	mutating func abortAsLiteral(from start: Int, byte: UInt8) -> Bool {
		pos = start
		advance()
		parent.appendTextChild([byte])
		return true
	}

	/// Parse a reference label `[label]` at the current position.
	/// Assumes the cursor is at the opening `[`.
	///
	/// Returns the label bytes to look up: the text inside `[...]` if
	/// non-empty, or `text[textStart..<textEnd]` as fallback (used for
	/// collapsed references like `[text][]`).
	mutating func parseReferenceLabel(textStart: Int, textEnd: Int) -> [UInt8] {
		advance() // Consume [
		let refStart = pos
		while !isAtEnd && peek() != .asciiRBracket {
			advance()
		}
		let refEnd = pos
		if peek() == .asciiRBracket {
			advance()
		}

		if refEnd == refStart {
			return Array(text[textStart..<textEnd])
		}
		return Array(text[refStart..<refEnd])
	}

	/// Skip inline whitespace characters (space, tab, newline) from current pos.
	mutating func skipInlineWhitespace() {
		while true {
			let c = peek()
			if c == .asciiSpace || c == .asciiTab || c == .asciiNewline {
				advance()
			} else {
				return
			}
		}
	}

	/// Parse the URL and optional title inside `(url "title")`.
	///
	/// Assumes the cursor is just past `(`. Consumes through the closing `)`.
	/// The URL may optionally be wrapped in angle brackets:
	/// `(<http://example.com>)`.
	///
	/// Returns the parsed URL and title bytes, or nil if the syntax is invalid.
	mutating func parseURLAndTitle() -> (urlBytes: [UInt8], titleBytes: [UInt8]?)? {
		skipInlineWhitespace()

		// Get URL
		var urlStart = pos
		let inAngle = peek() == .asciiLessThan
		if inAngle {
			advance()
			urlStart = pos
		}

		while !isAtEnd {
			let character = peek()
			if inAngle {
				if character == .asciiGreaterThan {
					break
				}
			} else {
				if character == .asciiRParen || character == .asciiSpace || character == .asciiTab || character == .asciiNewline {
					break
				}
			}
			advance()
		}

		let urlEnd = pos
		if inAngle && peek() == .asciiGreaterThan {
			advance()
		}

		skipInlineWhitespace()

		// Optional title
		var titleBytes: [UInt8]?
		let beforeTitle = peek()
		if beforeTitle == .asciiDoubleQuote || beforeTitle == .asciiSingleQuote {
			titleBytes = parseInlineLinkTitle()
			skipInlineWhitespace()
		}

		guard peek() == .asciiRParen else {
			return nil
		}
		advance() // Consume )

		let urlBytes = Array(text[urlStart..<urlEnd])
		return (urlBytes, titleBytes)
	}

	/// Parse the `(url "title")` portion of an inline link.
	///
	/// Example: for `[click](http://example.com "Title")`, `parseLink`
	/// handles the `[click]` part and calls this with the cursor just
	/// past `(`.
	///
	/// Returns the built link node, or nil if the syntax is invalid
	/// (caller backtracks and emits `[` as literal text).
	mutating func parseInlineLink(textStart: Int, textEnd: Int) -> Node? {
		guard let result = parseURLAndTitle() else {
			return nil
		}

		let link = Node(kind: .link(LinkInfo(urlBytes: result.urlBytes, titleBytes: result.titleBytes)))

		if textEnd > textStart {
			var subIP = InlineParser(linkRefs: linkRefs, parent: link, text: Array(text[textStart..<textEnd]))
			subIP.parse()
		}
		return link
	}

	/// Parse a quoted title within an inline link — `"title"` or `'title'`.
	///
	/// Markdown.pl allows unescaped quotes inside the title and resolves
	/// the ambiguity by treating the *last* quote on the line as the
	/// closer. This lets `[x](http://y "Will "Tom" go?")` work with the
	/// intended title `Will "Tom" go?`. Returns the title bytes, or nil
	/// if no valid closing structure is found.
	mutating func parseInlineLinkTitle() -> [UInt8]? {
		let quote = advance()
		let titleStart = pos

		// Gruber compatibility: find LAST quote before closing )
		var scanPos = pos
		var parenDepth = 1
		var lastQuotePos: Int?

		while scanPos < text.count && parenDepth > 0 {
			let ch = text[scanPos]
			if ch == .asciiLParen {
				parenDepth += 1
			} else if ch == .asciiRParen {
				parenDepth -= 1
				if parenDepth == 0 {
					break
				}
			} else if ch == quote {
				lastQuotePos = scanPos
			}
			scanPos += 1
		}

		guard let lastQ = lastQuotePos, parenDepth == 0 else {
			return nil
		}
		let result = Array(text[titleStart..<lastQ])
		pos = lastQ + 1
		return result
	}

	/// Parse a link in any of its forms.
	///
	/// Examples:
	/// - Inline: `[click here](http://example.com "Title")`
	/// - Reference: `[click here][label]`
	/// - Collapsed reference: `[click here][]`
	/// - Shortcut reference: `[click here]`
	///
	/// If nothing matches, the `[` is emitted as literal text.
	mutating func parseLink() -> Bool {
		let start = pos
		advance() // Consume [

		// Find link text (handle nested brackets)
		var bracketDepth = 1
		let textStart = pos

		while !isAtEnd && bracketDepth > 0 {
			let ch = peek()
			if ch == .asciiBackslash {
				advance() // Consume \
				if !isAtEnd {
					advance() // Consume escaped char
				}
			} else if ch == .asciiLBracket {
				bracketDepth += 1
				advance()
			} else if ch == .asciiRBracket {
				bracketDepth -= 1
				if bracketDepth > 0 {
					advance()
				}
			} else {
				advance()
			}
		}

		if bracketDepth != 0 {
			return abortAsLiteral(from: start, byte: .asciiLBracket)
		}

		let textEnd = pos
		advance() // Consume ]

		// Inline link: [text](url "title")
		if peek() == .asciiLParen {
			advance() // Consume (
			if let link = parseInlineLink(textStart: textStart, textEnd: textEnd) {
				parent.appendChild(link)
				return true
			}
			return abortAsLiteral(from: start, byte: .asciiLBracket)
		}

		// Skip optional whitespace (Gruber allows [text] [ref] with space)
		let afterBracket = pos
		skipInlineWhitespace()

		// Reference link: [text][ref] or [text][]
		if peek() == .asciiLBracket {
			let label = parseReferenceLabel(textStart: textStart, textEnd: textEnd)
			if let ref = linkRefs.find(label) {
				parent.appendChild(makeLinkFromRef(ref, textStart: textStart, textEnd: textEnd))
				return true
			}
			return abortAsLiteral(from: start, byte: .asciiLBracket)
		}

		// Shortcut reference link: [text]
		pos = afterBracket
		let label = Array(text[textStart..<textEnd])
		if let ref = linkRefs.find(label) {
			parent.appendChild(makeLinkFromRef(ref, textStart: textStart, textEnd: textEnd))
			return true
		}

		return abortAsLiteral(from: start, byte: .asciiLBracket)
	}

	// MARK: - Image

	/// Parse an image in any of its forms.
	///
	/// Examples:
	/// - Inline: `![alt text](photo.jpg "Title")`
	/// - Reference: `![alt text][label]`
	///
	/// If nothing matches, the `!` is emitted as literal text.
	mutating func parseImage() -> Bool {
		let start = pos
		advance() // Consume !
		advance() // Consume [

		// Find alt text
		var bracketDepth = 1
		let textStart = pos

		while !isAtEnd && bracketDepth > 0 {
			let character = peek()
			if character == .asciiBackslash {
				advance() // Consume \
				if !isAtEnd {
					advance() // Consume escaped char
				}
			} else if character == .asciiLBracket {
				bracketDepth += 1
				advance()
			} else if character == .asciiRBracket {
				bracketDepth -= 1
				if bracketDepth > 0 {
					advance()
				}
			} else {
				advance()
			}
		}

		if bracketDepth != 0 {
			return abortAsLiteral(from: start, byte: .asciiBang)
		}

		let textEnd = pos
		advance() // Consume ]

		let afterAlt = peek()
		if afterAlt != .asciiLParen {
			// Try reference style
			if afterAlt == .asciiLBracket {
				let label = parseReferenceLabel(textStart: textStart, textEnd: textEnd)
				if let ref = linkRefs.find(label) {
					let altBytes = Array(text[textStart..<textEnd])
					let img = Node(kind: .image(alt: altBytes, link: LinkInfo(urlBytes: ref.urlBytes, titleBytes: ref.titleBytes)))
					parent.appendChild(img)
					return true
				}
			}
			return abortAsLiteral(from: start, byte: .asciiBang)
		}

		advance() // Consume (

		guard let result = parseURLAndTitle() else {
			return abortAsLiteral(from: start, byte: .asciiBang)
		}

		let altBytes = Array(text[textStart..<textEnd])
		let img = Node(kind: .image(alt: altBytes, link: LinkInfo(urlBytes: result.urlBytes, titleBytes: result.titleBytes)))
		parent.appendChild(img)

		return true
	}

	// MARK: - Autolink

	/// Parse an autolink — a URL or email wrapped in angle brackets.
	///
	/// Examples:
	/// - `<http://example.com>` → `<a href="http://example.com">http://example.com</a>`
	/// - `<user@example.com>` → `<a href="mailto:user@example.com">user@example.com</a>`
	///
	/// If the content doesn't look like a URL or email, returns false so
	/// the caller can try HTML-tag parsing instead.
	mutating func parseAutolink() -> Bool {
		let start = pos
		advance() // Consume <

		let urlStart = pos
		var isEmail = false
		var isURL = false

		while !isAtEnd {
			let c = peek()
			if c == .asciiGreaterThan || c == .asciiNewline {
				break
			}
			if c == .asciiAt {
				isEmail = true
			}
			if c == .asciiColon {
				isURL = true
			}
			if c == 0 || c.isASCIIWhitespace {
				pos = start
				return false
			}
			advance()
		}

		if peek() != .asciiGreaterThan {
			return abortAsLiteral(from: start, byte: .asciiLessThan)
		}

		let urlEnd = pos
		advance() // Consume >

		if !isEmail && !isURL {
			pos = start
			return false
		}

		let urlBytes = Array(text[urlStart..<urlEnd])
		let linkURLBytes: [UInt8]

		if isEmail && !isURL {
			var mailto = [UInt8]()
			mailto.reserveCapacity(7 + urlBytes.count) // "mailto:" is 7 bytes
			mailto.append(contentsOf: Self.mailtoPrefix)
			mailto.append(contentsOf: urlBytes)
			linkURLBytes = mailto
		} else {
			linkURLBytes = urlBytes
		}

		let link = Node(kind: .link(LinkInfo(urlBytes: linkURLBytes, titleBytes: nil)))

		// Link text is the URL itself
		let textNode = Node(kind: .text(urlBytes))
		link.appendChild(textNode)

		parent.appendChild(link)
		return true
	}

	// MARK: - HTML Tag

	/// Parse a raw HTML tag and pass it through unchanged as `.htmlInline`.
	///
	/// Example: `<span class="x">` is emitted verbatim in the output.
	/// This method is called as a fallback after `parseAutolink` rejects
	/// the `<...>` as not a URL or email.
	mutating func parseHTMLTag() -> Bool {
		let start = pos

		guard peek() == .asciiLessThan else {
			return false
		}

		advance() // Consume <

		// Find closing >
		while !isAtEnd {
			let c = peek()
			if c == .asciiGreaterThan || c == .asciiNewline {
				break
			}
			advance()
		}

		if peek() != .asciiGreaterThan {
			return abortAsLiteral(from: start, byte: .asciiLessThan)
		}

		advance() // Consume >

		let html = Node(kind: .htmlInline(Array(text[start..<pos])))
		parent.appendChild(html)

		return true
	}
}
