//
//  Renderer.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

/// Render an AST to HTML.
func renderHTML(_ document: Node, inputLength: Int) -> String {
	var state = RenderState(inputLength: inputLength)
	state.renderChildren(document)
	return state.buffer.toString()
}

// MARK: - Render State

private struct RenderState {
	var buffer: ByteArray
	var tightList = false

	init(inputLength: Int) {
		// HTML output is typically 1.5–2× the source Markdown size,
		// so double the input length to reduce reallocation/copy cycles.
		buffer = ByteArray(estimatedCapacity: inputLength * 2)
	}

	mutating func renderNode(_ node: Node) {
		switch node.kind {
		case .document:
			renderChildren(node)

		case .paragraph:
			renderParagraph(node)

		case .heading(let level):
			renderHeading(node, level: level)

		case .blockquote:
			renderBlockquote(node)

		case .codeBlock(let literal):
			renderCodeBlock(node, literal: literal)

		case .hrule:
			renderHrule(node)

		case .list(let listInfo):
			renderList(node, listInfo: listInfo)

		case .listItem:
			renderListItem(node)

		case .htmlBlock(let literal):
			renderHTMLBlock(node, literal: literal)

		case .text(let literal):
			HTMLEscaper.escapeText(literal, into: &buffer)

		case .softbreak:
			buffer.append(.asciiNewline)

		case .hardbreak:
			buffer.append(staticString: "<br>\n")

		case .emphasis:
			buffer.append(staticString: "<em>")
			renderChildren(node)
			buffer.append(staticString: "</em>")

		case .strong:
			buffer.append(staticString: "<strong>")
			renderChildren(node)
			buffer.append(staticString: "</strong>")

		case .codeSpan(let literal):
			buffer.append(staticString: "<code>")
			HTMLEscaper.escapeCode(literal, into: &buffer)
			buffer.append(staticString: "</code>")

		case .link(let linkInfo):
			renderLink(node, linkInfo: linkInfo)

		case .image(let alt, let linkInfo):
			renderImage(alt: alt, linkInfo: linkInfo)

		case .htmlInline(let literal):
			buffer.append(literal)
		}
	}

	mutating func renderChildren(_ node: Node) {
		for child in node.children {
			renderNode(child)
		}
	}

	/// Emit a blank line separator if the node has a following sibling.
	/// Used to space block-level siblings in the output.
	mutating func appendBlankLineIfFollowedBySibling(_ node: Node) {
		if node.next != nil {
			buffer.append(.asciiNewline)
		}
	}

	// MARK: - Block Rendering

	/// Render a paragraph node to HTML.
	///
	/// Paragraph spacing is the trickiest part of HTML rendering because
	/// the rules differ by context:
	///
	/// - **Tight lists** suppress `<p>` tags entirely — items are rendered
	///   as bare text separated by newlines.
	/// - **Loose list items** use `<p>` tags, but `renderListItem` appends
	///   its own `</li>\n`, so the last paragraph in an item must not add
	///   a trailing newline (or it would be doubled).
	/// - **Blockquotes** need a blank line before code blocks or nested
	///   blockquotes, but not before other content.
	/// - **Top-level paragraphs** get blank-line separation (an extra `\n`
	///   after the closing tag) between siblings.
	mutating func renderParagraph(_ node: Node) {
		if tightList {
			// Tight lists: no <p> tags, just inline content.
			renderChildren(node)
			if node.next != nil {
				buffer.append(.asciiNewline)
			}
			return
		}

		buffer.append(staticString: "<p>")
		renderChildren(node)

		let inListItem = node.parent?.kind == .listItem

		// The last child in a list item skips its newline here because
		// renderListItem appends "</li>\n" — adding one here would double it.
		if !(inListItem && node.next == nil) {
			buffer.append(.asciiNewline)
		}

		// Decide whether to add a blank line (extra newline) after the
		// closing tag based on what follows this paragraph and where it sits.
		if let next = node.next, let parent = node.parent {
			let parentIsListItem = parent.kind == .listItem
			if parentIsListItem && next.kind == .paragraph {
				// Multiple paragraphs in a list item: separate them.
				buffer.append(.asciiNewline)
			} else if parentIsListItem, case .list = next.kind {
				// Nested list after a paragraph in a loose item.
				if !tightList {
					buffer.append(.asciiNewline)
				}
			} else if parentIsListItem {
				// Other content in a list item (e.g. code block): no extra spacing.
			} else if case .blockquote = parent.kind {
				// Inside a blockquote, only separate before code blocks or
				// nested blockquotes — other siblings flow together.
				switch next.kind {
				case .codeBlock, .blockquote:
					buffer.append(.asciiNewline)
				default:
					break
				}
			} else {
				// Top-level: blank line between sibling blocks.
				buffer.append(.asciiNewline)
			}
		}
	}

	private static let headingOpen: [StaticString] = [
		"<h1>", "<h2>", "<h3>", "<h4>", "<h5>", "<h6>"
	]

	private static let headingClose: [StaticString] = [
		"</h1>\n", "</h2>\n", "</h3>\n", "</h4>\n", "</h5>\n", "</h6>\n"
	]

	mutating func renderHeading(_ node: Node, level: Int) {
		let levelIndex = min(max(level, 1), 6) - 1
		buffer.append(staticString: Self.headingOpen[levelIndex])
		renderChildren(node)
		buffer.append(staticString: Self.headingClose[levelIndex])
		appendBlankLineIfFollowedBySibling(node)
	}

	mutating func renderBlockquote(_ node: Node) {
		buffer.append(staticString: "<blockquote>\n")
		renderChildren(node)
		buffer.append(staticString: "</blockquote>\n")
		appendBlankLineIfFollowedBySibling(node)
	}

	mutating func renderCodeBlock(_ node: Node, literal: [UInt8]) {
		buffer.append(staticString: "<pre><code>")

		// Trim trailing whitespace per Gruber's Markdown.pl.
		var length = literal.count
		while length > 0 && literal[length - 1].isASCIIWhitespace {
			length -= 1
		}
		if length > 0 {
			HTMLEscaper.escapeCode(literal, into: &buffer, length: length)
		}

		buffer.append(staticString: "\n</code></pre>\n")
		appendBlankLineIfFollowedBySibling(node)
	}

	mutating func renderHrule(_ node: Node) {
		buffer.append(staticString: "<hr>\n")
		appendBlankLineIfFollowedBySibling(node)
	}

	mutating func renderList(_ node: Node, listInfo: ListInfo) {
		let ordered = listInfo.type == .ordered

		// Save/restore tight-list state for nested lists
		let parentTight = tightList
		tightList = listInfo.tight

		if ordered {
			buffer.append(staticString: "<ol>\n")
		} else {
			buffer.append(staticString: "<ul>\n")
		}

		renderChildren(node)

		buffer.append(staticString: ordered ? "</ol>" : "</ul>")
		// When inside a list item, skip the newline — renderListItem adds it.
		if node.parent?.kind != .listItem {
			buffer.append(.asciiNewline)
			appendBlankLineIfFollowedBySibling(node)
		}

		tightList = parentTight
	}

	mutating func renderListItem(_ node: Node) {
		buffer.append(staticString: "<li>")
		renderChildren(node)
		buffer.append(.asciiNewline)
	}

	mutating func renderHTMLBlock(_ node: Node, literal: [UInt8]) {
		buffer.append(literal)
		appendBlankLineIfFollowedBySibling(node)
	}

	// MARK: - Inline Rendering

	mutating func renderLink(_ node: Node, linkInfo: LinkInfo) {
		buffer.append(staticString: "<a href=\"")
		HTMLEscaper.escapeURL(linkInfo.urlBytes, into: &buffer)
		buffer.append(.asciiDoubleQuote)

		if let titleBytes = linkInfo.titleBytes, !titleBytes.isEmpty {
			buffer.append(staticString: " title=\"")
			HTMLEscaper.escapeAttribute(titleBytes, into: &buffer)
			buffer.append(.asciiDoubleQuote)
		}

		buffer.append(.asciiGreaterThan)
		renderChildren(node)
		buffer.append(staticString: "</a>")
	}

	mutating func renderImage(alt: [UInt8], linkInfo: LinkInfo) {
		buffer.append(staticString: "<img src=\"")
		HTMLEscaper.escapeURL(linkInfo.urlBytes, into: &buffer)
		buffer.append(staticString: "\" alt=\"")
		HTMLEscaper.escapeAttribute(alt, into: &buffer)
		buffer.append(.asciiDoubleQuote)

		if let titleBytes = linkInfo.titleBytes, !titleBytes.isEmpty {
			buffer.append(staticString: " title=\"")
			HTMLEscaper.escapeAttribute(titleBytes, into: &buffer)
			buffer.append(.asciiDoubleQuote)
		}

		buffer.append(staticString: ">")
	}
}
