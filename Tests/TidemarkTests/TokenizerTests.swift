//
//  TokenizerTests.swift
//  TidemarkTests
//
//  Created by Brent Simmons on 4/15/26.
//

import Testing
@testable import Tidemark

// MARK: - Basic Tests

@Test func nullInputReturnsEOF() {
	let bytes: [UInt8] = []
	let tok = firstToken(bytes)
	#expect(tok.type == .eof)
}

@Test func emptyInput() {
	let tok = firstToken("")
	#expect(tok.type == .eof)
}

@Test func plainText() {
	let tok = firstToken("Hello world")
	#expect(tok.type == .text)
	assertTokenText(tok, "Hello world", in: "Hello world")
}

@Test func newline() {
	let input = "Hello\nWorld"
	var tokenizer = makeTokenizer(input)

	let tok1 = tokenizer.next()
	#expect(tok1.type == .text)

	let tok2 = tokenizer.next()
	#expect(tok2.type == .newline)
}

@Test func blankLine() {
	let tok = firstToken("\n")
	#expect(tok.type == .blankLine)
}

// MARK: - ATX Header Tests

@Test func atxH1() {
	let tok = firstToken("# Header")
	#expect(tok.type == .atxHeader1)
}

@Test func atxH2() {
	let tok = firstToken("## Header")
	#expect(tok.type == .atxHeader2)
}

@Test func atxH3() {
	let tok = firstToken("### Header")
	#expect(tok.type == .atxHeader3)
}

@Test func atxH4() {
	let tok = firstToken("#### Header")
	#expect(tok.type == .atxHeader4)
}

@Test func atxH5() {
	let tok = firstToken("##### Header")
	#expect(tok.type == .atxHeader5)
}

@Test func atxH6() {
	let tok = firstToken("###### Header")
	#expect(tok.type == .atxHeader6)
}

@Test func atxNoSpaceIsText() {
	let tok = firstToken("#NoSpace")
	#expect(tok.type == .text)
}

@Test func atxHeaderContent() {
	let input = "# Hello"
	var tokenizer = makeTokenizer(input)

	let header = tokenizer.next()
	#expect(header.type == .atxHeader1)

	let content = tokenizer.next()
	#expect(content.type == .text)
	assertTokenText(content, "Hello", in: input)
}

// MARK: - Setext Header Tests

@Test func setextH1() {
	let input = "Header\n======"
	var tokenizer = makeTokenizer(input)

	let text = tokenizer.next()
	#expect(text.type == .text)

	let newline = tokenizer.next()
	#expect(newline.type == .newline)

	let underline = tokenizer.next()
	#expect(underline.type == .setextHeader1)
}

@Test func setextH2() {
	let input = "Header\n------"
	var tokenizer = makeTokenizer(input)

	_ = tokenizer.next() // text
	_ = tokenizer.next() // newline

	let underline = tokenizer.next()
	#expect(underline.type == .setextHeader2)
}

// MARK: - Blockquote Tests

@Test func blockquote() {
	let tok = firstToken("> Quote")
	#expect(tok.type == .blockquote)
}

@Test func blockquoteContent() {
	let input = "> Hello"
	var tokenizer = makeTokenizer(input)

	let bq = tokenizer.next()
	#expect(bq.type == .blockquote)

	let content = tokenizer.next()
	#expect(content.type == .text)
	assertTokenText(content, "Hello", in: input)
}

// MARK: - Code Block Tests

@Test func codeBlockSpaces() {
	let tok = firstToken("    code")
	#expect(tok.type == .codeBlockIndent)
	assertTokenText(tok, "code", in: "    code")
}

@Test func codeBlockTab() {
	let tok = firstToken("\tcode")
	#expect(tok.type == .codeBlockIndent)
	assertTokenText(tok, "code", in: "\tcode")
}

// MARK: - Horizontal Rule Tests

@Test func hruleDashes() {
	let tok = firstToken("---")
	// Note: --- could be setext h2 or hrule; tokenizer returns setextHeader2
	#expect(tok.type == .setextHeader2 || tok.type == .hrule)
}

@Test func hruleAsterisks() {
	let tok = firstToken("***")
	#expect(tok.type == .hrule)
}

@Test func hruleUnderscores() {
	let tok = firstToken("___")
	#expect(tok.type == .hrule)
}

@Test func hruleWithSpaces() {
	let tok = firstToken("* * *")
	#expect(tok.type == .hrule)
}

// MARK: - List Tests

@Test func ulAsterisk() {
	let tok = firstToken("* Item")
	#expect(tok.type == .ulMarker)
}

@Test func ulDash() {
	let tok = firstToken("- Item")
	#expect(tok.type == .ulMarker)
}

@Test func ulPlus() {
	let tok = firstToken("+ Item")
	#expect(tok.type == .ulMarker)
}

@Test func olMarker() {
	let tok = firstToken("1. Item")
	#expect(tok.type == .olMarker)
}

@Test func olMultidigit() {
	let tok = firstToken("123. Item")
	#expect(tok.type == .olMarker)
}

// MARK: - Inline Content Tests
//
// The tokenizer emits inline constructs (emphasis, links, autolinks,
// entities, escapes) as `.text` tokens. The inline parser handles all
// inline classification when it re-scans the collected bytes.

@Test func inlineEmphasisIsText() {
	let input = "Hello *world*"
	let tok = firstToken(input)
	#expect(tok.type == .text)
	assertTokenText(tok, "Hello *world*", in: input)
}

@Test func inlineStrongIsText() {
	let input = "Hello **world**"
	let tok = firstToken(input)
	#expect(tok.type == .text)
	assertTokenText(tok, "Hello **world**", in: input)
}

@Test func inlineLinkIsText() {
	let input = "[text](url)"
	let tok = firstToken(input)
	#expect(tok.type == .text)
	assertTokenText(tok, "[text](url)", in: input)
}

@Test func inlineImageIsText() {
	let input = "![alt](url)"
	let tok = firstToken(input)
	#expect(tok.type == .text)
	assertTokenText(tok, "![alt](url)", in: input)
}

@Test func inlineAutolinkIsText() {
	let input = "<http://example.com>"
	let tok = firstToken(input)
	#expect(tok.type == .text)
	assertTokenText(tok, "<http://example.com>", in: input)
}

@Test func inlineHTMLTagIsText() {
	let input = "<div>"
	let tok = firstToken(input)
	#expect(tok.type == .text)
	assertTokenText(tok, "<div>", in: input)
}

@Test func inlineEscapeIsText() {
	let input = "\\*escaped\\]"
	let tok = firstToken(input)
	#expect(tok.type == .text)
	assertTokenText(tok, "\\*escaped\\]", in: input)
}

@Test func inlineEntityIsText() {
	let input = "&amp;"
	let tok = firstToken(input)
	#expect(tok.type == .text)
	assertTokenText(tok, "&amp;", in: input)
}

@Test func inlineEntityDecimalIsText() {
	let tok = firstToken("&#123;")
	#expect(tok.type == .text)
}

@Test func inlineEntityHexIsText() {
	let tok = firstToken("&#x1F600;")
	#expect(tok.type == .text)
}

// MARK: - Hard Break Tests

@Test func hardBreak() {
	let input = "Line one  \nLine two"
	var tokenizer = makeTokenizer(input)

	let text = tokenizer.next()
	#expect(text.type == .text)

	let br = tokenizer.next()
	#expect(br.type == .hardBreak)
}

// MARK: - Position Tracking Tests

@Test func lineTracking() {
	let input = "Line 1\nLine 2\nLine 3"
	var tokenizer = makeTokenizer(input)

	let tok1 = tokenizer.next()
	#expect(tok1.line == 1)

	_ = tokenizer.next() // newline

	let tok2 = tokenizer.next()
	#expect(tok2.line == 2)
}

@Test func columnTracking() {
	let input = "Hello\nWorld"
	var tokenizer = makeTokenizer(input)

	let text = tokenizer.next()
	#expect(text.column == 1)

	_ = tokenizer.next() // newline

	let line2 = tokenizer.next()
	#expect(line2.column == 1)
	#expect(line2.line == 2)
}

// MARK: - Trailing Whitespace Tests

@Test func trailingSpacesWithoutNewline() {
	// Three spaces with no trailing newline should produce EOF, not crash.
	let input = "   "
	var tokenizer = makeTokenizer(input)
	var tokens: [Token] = []
	while true {
		let tok = tokenizer.next()
		tokens.append(tok)
		if tok.type == .eof {
			break
		}
	}
	#expect(tokens.last?.type == .eof)
}

@Test func twoSpacesWithoutNewline() {
	let input = "  "
	var tokenizer = makeTokenizer(input)
	var tokens: [Token] = []
	while true {
		let tok = tokenizer.next()
		tokens.append(tok)
		if tok.type == .eof {
			break
		}
	}
	#expect(tokens.last?.type == .eof)
}

@Test func singleSpaceWithoutNewline() {
	let input = " "
	var tokenizer = makeTokenizer(input)
	var tokens: [Token] = []
	while true {
		let tok = tokenizer.next()
		tokens.append(tok)
		if tok.type == .eof {
			break
		}
	}
	#expect(tokens.last?.type == .eof)
}

// MARK: - Reset Tests

@Test func resetTokenizer() {
	let input = "Hello"
	var tokenizer = makeTokenizer(input)

	_ = tokenizer.next()
	_ = tokenizer.next() // EOF

	tokenizer.reset()

	let tok = tokenizer.next()
	#expect(tok.type == .text)
}

// MARK: - Helpers

private func makeTokenizer(_ string: String) -> Tokenizer {
	Tokenizer(string)
}

private func firstToken(_ string: String) -> Token {
	var tokenizer = Tokenizer(string)
	return tokenizer.next()
}

private func firstToken(_ bytes: [UInt8]) -> Token {
	var tokenizer = Tokenizer(bytes)
	return tokenizer.next()
}

private func assertTokenText(_ token: Token, _ expected: String, in input: String, sourceLocation: SourceLocation = #_sourceLocation) {

	let inputBytes = Array(input.utf8)
	let expectedBytes = Array(expected.utf8)

	#expect(
		token.length == expectedBytes.count,
		"Token length mismatch: expected \(expectedBytes.count), got \(token.length)",
		sourceLocation: sourceLocation
	)

	let tokenBytes = Array(inputBytes[token.start..<token.start + token.length])
	let actual = String(decoding: tokenBytes, as: UTF8.self)
	#expect(
		tokenBytes == expectedBytes,
		"Token text mismatch: expected '\(expected)', got '\(actual)'",
		sourceLocation: sourceLocation
	)
}
