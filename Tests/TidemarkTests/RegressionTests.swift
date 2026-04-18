//
//  RegressionTests.swift
//  TidemarkTests
//
//  Created by Brent Simmons on 4/17/26.
//

import Testing
@testable import Tidemark

// MARK: - Trailing Whitespace (Crash Fix)

@Test func trailingSpacesProduceEmptyOutput() {
	#expect(markdownToHTML("   ") == "")
}

@Test func twoTrailingSpacesProduceEmptyOutput() {
	#expect(markdownToHTML("  ") == "")
}

@Test func singleTrailingSpaceProducesEmptyOutput() {
	#expect(markdownToHTML(" ") == "")
}

@Test func textFollowedByTrailingSpaces() {
	let result = markdownToHTML("hello   ")
	#expect(result.contains("hello"))
}

// MARK: - Image Alt Text Escaping

@Test func imageAltTextEscapesDoubleQuotes() {
	let result = markdownToHTML("![foo \"bar\"](img.jpg)")
	#expect(result.contains("alt=\"foo &quot;bar&quot;\""))
}

@Test func imageAltTextWithoutQuotesIsUnchanged() {
	let result = markdownToHTML("![simple alt](img.jpg)")
	#expect(result.contains("alt=\"simple alt\""))
}

@Test func imageAltTextEscapesAmpersand() {
	let result = markdownToHTML("![A & B](img.jpg)")
	#expect(result.contains("alt=\"A &amp; B\""))
}

@Test func imageAltTextEscapesLessThan() {
	let result = markdownToHTML("![a < b](img.jpg)")
	#expect(result.contains("alt=\"a &lt; b\""))
}

// MARK: - Line Ending Normalization

@Test func crlfLineEndings() {
	let input = "line one\r\nline two\r\n"
	let result = markdownToHTML(input)
	#expect(result.contains("line one"))
	#expect(result.contains("line two"))
}

@Test func loneCRLineEndings() {
	// Classic Mac line endings: lone \r should be treated as line breaks,
	// not silently deleted (which would merge lines).
	let input = "line one\rline two\r"
	let result = markdownToHTML(input)
	#expect(result.contains("line one"))
	#expect(result.contains("line two"))
}

@Test func loneCRCreatesNewParagraph() {
	// A lone \r\r should act like \n\n — a blank line separating paragraphs.
	let input = "first\r\rsecond\r"
	let result = markdownToHTML(input)
	#expect(result.contains("<p>first"))
	#expect(result.contains("<p>second"))
}

@Test func mixedLineEndings() {
	let input = "one\r\ntwo\rthree\nfour\r\n"
	let result = markdownToHTML(input)
	#expect(result.contains("one"))
	#expect(result.contains("two"))
	#expect(result.contains("three"))
	#expect(result.contains("four"))
}

// MARK: - Lazy Blockquote Continuation

@Test func lazyBlockquoteContinuation() {
	let input = "> line one\nline two\n"
	let result = markdownToHTML(input)
	// Both lines should be in a single blockquote paragraph.
	#expect(result.contains("<blockquote>"))
	#expect(result.contains("line one"))
	#expect(result.contains("line two"))
	// Should be one blockquote, not a blockquote + separate paragraph.
	#expect(!result.contains("</blockquote>\n<p>"))
}

@Test func lazyBlockquoteMultipleLines() {
	let input = "> first\nsecond\nthird\n"
	let result = markdownToHTML(input)
	#expect(result.contains("<blockquote>"))
	#expect(result.contains("first"))
	#expect(result.contains("second"))
	#expect(result.contains("third"))
	#expect(!result.contains("</blockquote>\n<p>"))
}

@Test func lazyBlockquoteStopsAtBlankLine() {
	let input = "> quote\n\nnot in quote\n"
	let result = markdownToHTML(input)
	#expect(result.contains("<blockquote>"))
	#expect(result.contains("quote"))
	// "not in quote" should be a separate paragraph outside the blockquote.
	let blockquoteEnd = result.range(of: "</blockquote>")!.lowerBound
	let separateParagraph = result.range(of: "not in quote")!.lowerBound
	#expect(separateParagraph > blockquoteEnd)
}

@Test func lazyBlockquoteStopsAtBlockMarker() {
	let input = "> quote\n# Heading\n"
	let result = markdownToHTML(input)
	#expect(result.contains("<blockquote>"))
	// The heading should be outside the blockquote.
	let blockquoteEnd = result.range(of: "</blockquote>")!.lowerBound
	let heading = result.range(of: "<h1>")!.lowerBound
	#expect(heading > blockquoteEnd)
}

@Test func noLazyAfterBlankLineInBlockquote() {
	let input = "> quote\n> \nnot continuation\n"
	let result = markdownToHTML(input)
	// "not continuation" should be outside the blockquote.
	let blockquoteEnd = result.range(of: "</blockquote>")!.lowerBound
	let outside = result.range(of: "not continuation")!.lowerBound
	#expect(outside > blockquoteEnd)
}

@Test func explicitBlockquoteAfterLazy() {
	let input = "> line one\nlazy\n> line three\n"
	let result = markdownToHTML(input)
	// All three lines should be in the blockquote.
	#expect(result.contains("<blockquote>"))
	#expect(result.contains("line one"))
	#expect(result.contains("lazy"))
	#expect(result.contains("line three"))
}
