//
//  NaiveParserTests.swift
//  TidemarkTests
//
//  Created by Brent Simmons on 4/17/26.
//

import Testing
@testable import Tidemark

// Tests targeting mistakes a naive Markdown parser would make.

// MARK: - Emphasis Edge Cases

@Test func intraWordUnderscoresAreNotEmphasis() {
	let result = markdownToHTML("foo_bar_baz")
	#expect(result.contains("foo_bar_baz"))
	#expect(!result.contains("<em>"))
}

@Test func intraWordAsterisksAreEmphasis() {
	let result = markdownToHTML("foo*bar*baz")
	#expect(result.contains("<em>bar</em>"))
}

@Test func mismatchedDelimitersPartialMatch() {
	// The * pair should match; the _ pair should not.
	let result = markdownToHTML("*foo _bar* baz_")
	#expect(result.contains("<em>foo _bar</em>"))
	#expect(!result.contains("</em> baz</em>"))
}

@Test func tripleAsteriskBoldItalic() {
	let result = markdownToHTML("***bold italic***")
	#expect(result.contains("<strong>"))
	#expect(result.contains("<em>"))
}

@Test func emphasisAcrossWords() {
	let result = markdownToHTML("*multiple words here*")
	#expect(result.contains("<em>multiple words here</em>"))
}

@Test func doubleUnderscoreStrong() {
	let result = markdownToHTML("__strong text__")
	#expect(result.contains("<strong>strong text</strong>"))
}

// MARK: - Entity Handling

@Test func bareAmpersandEscaped() {
	let result = markdownToHTML("AT&T")
	#expect(result.contains("AT&amp;T"))
}

@Test func existingEntityPassthrough() {
	let result = markdownToHTML("&copy;")
	#expect(result.contains("&copy;"))
	#expect(!result.contains("&amp;copy;"))
}

@Test func numericEntityPassthrough() {
	let result = markdownToHTML("&#169;")
	#expect(result.contains("&#169;"))
	#expect(!result.contains("&amp;#169;"))
}

@Test func hexEntityPassthrough() {
	let result = markdownToHTML("&#xA9;")
	#expect(result.contains("&#xA9;"))
	#expect(!result.contains("&amp;#xA9;"))
}

@Test func greaterThanNotEscapedInText() {
	// Gruber compatibility: > is not escaped in regular text.
	let result = markdownToHTML("4 > 3")
	#expect(result.contains("4 > 3"))
	#expect(!result.contains("&gt;"))
}

@Test func lessThanEscapedInText() {
	let result = markdownToHTML("3 < 4")
	#expect(result.contains("3 &lt; 4"))
}

// MARK: - Code Spans

@Test func codeSpanStripsOneLeadingAndTrailingSpace() {
	let result = markdownToHTML("` code `")
	#expect(result.contains("<code>code</code>"))
}

@Test func codeSpanPreservesInternalSpaces() {
	let result = markdownToHTML("`  two spaces  `")
	#expect(result.contains("<code> two spaces </code>"))
}

@Test func codeSpanNoInlineParsing() {
	// Content inside backticks must NOT be parsed for emphasis.
	let result = markdownToHTML("`*not emphasis*`")
	#expect(result.contains("<code>*not emphasis*</code>"))
	#expect(!result.contains("<em>"))
}

@Test func codeBlockNoInlineParsing() {
	// Content inside code blocks must NOT be parsed for links.
	let result = markdownToHTML("    [not a link](url)\n")
	#expect(result.contains("<pre><code>"))
	#expect(!result.contains("<a"))
}

@Test func codeSpanEscapesAmpersand() {
	let result = markdownToHTML("`a & b`")
	#expect(result.contains("<code>a &amp; b</code>"))
}

@Test func codeSpanEscapesAngleBrackets() {
	let result = markdownToHTML("`<div>`")
	#expect(result.contains("<code>&lt;div&gt;</code>"))
}

// MARK: - Links

@Test func inlineLinkWithTitle() {
	let result = markdownToHTML("[link](/url \"title\")")
	#expect(result.contains("href=\"/url\""))
	#expect(result.contains("title=\"title\""))
}

@Test func forwardReferenceLink() {
	// Reference used before it's defined.
	let input = "[click][1]\n\n[1]: /url\n"
	let result = markdownToHTML(input)
	#expect(result.contains("<a href=\"/url\">click</a>"))
}

@Test func referenceLinkCaseInsensitive() {
	let input = "[click][FOO]\n\n[foo]: /url\n"
	let result = markdownToHTML(input)
	#expect(result.contains("<a href=\"/url\">click</a>"))
}

@Test func urlEndsAtSpace() {
	// Parens-style URL should not include spaces.
	let result = markdownToHTML("[link](url with spaces)")
	// Should not produce a link with "url with spaces" as href.
	#expect(!result.contains("href=\"url with spaces\""))
}

@Test func angleBracketURL() {
	let result = markdownToHTML("[link](<http://example.com>)")
	#expect(result.contains("href=\"http://example.com\""))
}

@Test func unmatchedBracketIsLiteral() {
	let result = markdownToHTML("[not a link")
	#expect(result.contains("[not a link"))
	#expect(!result.contains("<a"))
}

// MARK: - ATX Headings

@Test func atxTrailingHashesStripped() {
	let result = markdownToHTML("## Heading ##")
	#expect(result.contains("<h2>Heading</h2>"))
}

@Test func atxTrailingHashesWithSpaces() {
	let result = markdownToHTML("# Heading #  ")
	#expect(result.contains("<h1>Heading</h1>"))
}

@Test func sevenHashesIsNotHeading() {
	// Only h1–h6 are valid; ####### should be text.
	let result = markdownToHTML("####### Not a heading")
	#expect(!result.contains("<h7>"))
	#expect(result.contains("####### Not a heading"))
}

// MARK: - Lists

@Test func tightListNoParagraphTags() {
	let input = "* Apple\n* Banana\n"
	let result = markdownToHTML(input)
	#expect(result.contains("<li>Apple"))
	#expect(!result.contains("<p>Apple"))
}

@Test func looseListHasParagraphTags() {
	let input = "* Apple\n\n* Banana\n"
	let result = markdownToHTML(input)
	#expect(result.contains("<p>Apple"))
	#expect(result.contains("<p>Banana"))
}

@Test func listLikeLineInParagraphDoesNotStartList() {
	// Gruber: "1. foo" inside a paragraph shouldn't start a list.
	let input = "I often use the\n1. notation for things.\n"
	let result = markdownToHTML(input)
	#expect(!result.contains("<ol>"))
	#expect(result.contains("1. notation"))
}

// MARK: - Backslash Escapes

@Test func escapedAsterisksNotEmphasis() {
	let result = markdownToHTML("\\*literal asterisks\\*")
	#expect(result.contains("*literal asterisks*"))
	#expect(!result.contains("<em>"))
}

@Test func escapedBracketsNotLink() {
	let result = markdownToHTML("\\[not a link\\](url)")
	#expect(!result.contains("<a"))
	#expect(result.contains("[not a link]"))
}

@Test func backslashBeforeNonEscapable() {
	// Backslash before a non-escapable character outputs both.
	let result = markdownToHTML("\\z")
	#expect(result.contains("\\z"))
}

@Test func backslashAtEndOfInput() {
	let result = markdownToHTML("trailing\\")
	#expect(result.contains("trailing\\"))
}

// MARK: - Autolinks

@Test func autolinkURL() {
	let result = markdownToHTML("<http://example.com>")
	#expect(result.contains("<a href=\"http://example.com\">http://example.com</a>"))
}

@Test func autolinkEmail() {
	let result = markdownToHTML("<user@example.com>")
	#expect(result.contains("href=\"mailto:user@example.com\""))
	#expect(result.contains(">user@example.com</a>"))
}

// MARK: - Pathological Input

@Test func onlySpacesProducesNoTags() {
	let result = markdownToHTML("     ")
	#expect(!result.contains("<p>"))
}

@Test func emptyInputProducesEmptyOutput() {
	#expect(markdownToHTML("") == "")
}

@Test func manyUnclosedBracketsDoNotHang() {
	// A naive parser might backtrack exponentially.
	let input = String(repeating: "[", count: 1000)
	let result = markdownToHTML(input)
	#expect(result.contains("["))
}

@Test func deeplyNestedBlockquotesDoNotCrash() {
	// Must not stack overflow. Nesting beyond the depth limit is
	// silently flattened, so just verify we get output without crashing.
	let input = String(repeating: "> ", count: 200) + "deep\n"
	let result = markdownToHTML(input)
	#expect(!result.isEmpty)
}

@Test func manyEmphasisDelimitersDoNotHang() {
	// Pathological emphasis: many openers with no closers.
	let input = String(repeating: "a]* ", count: 500)
	let result = markdownToHTML(input)
	#expect(!result.isEmpty)
}

// MARK: - HTML Escaping in Attributes

@Test func urlAmpersandEscaped() {
	let result = markdownToHTML("[link](http://example.com?a=1&b=2)")
	#expect(result.contains("href=\"http://example.com?a=1&amp;b=2\""))
}

@Test func titleQuotesEscaped() {
	let result = markdownToHTML("[link](/url \"a \\\"quote\\\"\")")
	// The title should have &quot; for any literal " in the attribute.
	#expect(!result.contains("title=\"a \"quote\"\""))
}

@Test func imageAltLessThanEscaped() {
	let result = markdownToHTML("![a < b](img.jpg)")
	#expect(result.contains("alt=\"a &lt; b\""))
}

// MARK: - Setext Headings

@Test func setextH1WithSingleEquals() {
	let result = markdownToHTML("Heading\n=\n")
	#expect(result.contains("<h1>Heading</h1>"))
}

@Test func setextH2WithDashes() {
	let result = markdownToHTML("Heading\n---\n")
	#expect(result.contains("<h2>Heading</h2>"))
}

@Test func standaloneDashesAreHrule() {
	// --- without preceding text is a horizontal rule, not a heading.
	let result = markdownToHTML("---\n")
	#expect(result.contains("<hr>"))
	#expect(!result.contains("<h2>"))
}

// MARK: - Multiple Blank Lines

@Test func multipleBlankLinesCollapse() {
	let result = markdownToHTML("First\n\n\n\nSecond\n")
	// Should produce two paragraphs, not four.
	let paragraphCount = result.components(separatedBy: "<p>").count - 1
	#expect(paragraphCount == 2)
}
