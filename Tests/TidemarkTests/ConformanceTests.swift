//
//  ConformanceTests.swift
//  TidemarkTests
//
//  Created by Brent Simmons on 4/15/26.
//

import Testing
import Foundation
@testable import Tidemark

/// John Gruber's Original Markdown Conformance Tests (MarkdownTest_1.0)

private let gruberTests = [
	"Amps and angle encoding",
	"Auto links",
	"Backslash escapes",
	"Blockquotes with code blocks",
	"Hard-wrapped paragraphs with list-like lines",
	"Horizontal rules",
	"Inline HTML (Advanced)",
	"Inline HTML (Simple)",
	"Inline HTML comments",
	"Links, inline style",
	"Links, reference style",
	"Literal quotes in titles",
	"Markdown Documentation - Basics",
	"Markdown Documentation - Syntax",
	"Nested blockquotes",
	"Ordered and unordered lists",
	"Strong and em together",
	"Tabs",
	"Tidyness"
]

@Test(arguments: gruberTests)
func gruberConformance(_ testName: String) throws {
	let resourcesURL = try gruberResourcesDirectory()

	let textURL = resourcesURL.appendingPathComponent("\(testName).text")
	let htmlURL = resourcesURL.appendingPathComponent("\(testName).html")

	let markdownData = try Data(contentsOf: textURL)
	let expectedData = try Data(contentsOf: htmlURL)

	let markdownBytes = Array(markdownData)
	let expected = String(decoding: expectedData, as: UTF8.self)
	let actual = markdownToHTML(markdownBytes)

	#expect(normalizeHTML(actual) == normalizeHTML(expected), "HTML mismatch for \(testName)")
}

// MARK: - Helpers

private func gruberResourcesDirectory() throws -> URL {
	let bundle = Bundle.module
	guard let url = bundle.url(forResource: "Resources/tests_gruber", withExtension: nil) else {
		throw GruberError.resourcesNotFound
	}
	return url
}

private enum GruberError: Error {
	case resourcesNotFound
}

/// Expand tabs to the next 4-column boundary, starting from a given column.
private func expandTabs(_ string: some StringProtocol, startColumn: Int = 0) -> String {
	guard string.contains("\t") else {
		return String(string)
	}
	var result = ""
	var column = startColumn
	for character in string {
		if character == "\t" {
			let spaces = 4 - (column % 4)
			result.append(contentsOf: repeatElement(" ", count: spaces))
			column += spaces
		} else {
			result.append(character)
			column += 1
		}
	}
	return result
}

/// Normalize HTML so Gruber's XHTML-style expected output can be
/// compared to our HTML5 output. The differences are cosmetic — both
/// represent the same document structure.
///
/// Gruber's Markdown.pl emits XHTML; Tidemark emits HTML5. The
/// structural differences:
///
/// - `<hr />` → `<hr>` (XHTML self-closing → HTML5)
/// - `</p>` and `</li>` (emitted by Gruber, omitted by Tidemark —
///   both are optional in HTML5)
/// - Blockquote indentation (Gruber indents children with two spaces
///   per nesting level; Tidemark doesn't)
/// - Tab expansion (Gruber expands tabs to spaces in code blocks
///   and HTML blocks; Tidemark preserves them)
/// - Trailing newlines (Gruber and Tidemark may differ by a final newline)
private func normalizeHTML(_ html: String) -> String {
	let stripped = html
		.replacingOccurrences(of: " />", with: ">")
		.replacingOccurrences(of: "</p>", with: "")
		.replacingOccurrences(of: "</li>", with: "")

	// Strip leading whitespace from lines outside <pre> blocks (Gruber
	// indents blockquote children; we don't). Inside <pre> blocks,
	// expand tabs to the next 4-column boundary. Lines that open a
	// <pre><code> block split at the tag boundary so the content
	// portion expands tabs from column 0.
	var lines = [String]()
	var inPre = false
	for line in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
		if !inPre && line.contains("<pre>") {
			inPre = true
			// Split at end of <code> so tabs in content expand from column 0.
			if let range = line.range(of: "<code>") {
				let prefix = line[line.startIndex..<range.upperBound]
				let content = line[range.upperBound...]
				lines.append(String(prefix) + expandTabs(content, startColumn: 0))
			} else {
				lines.append(expandTabs(line))
			}
		} else if inPre {
			lines.append(expandTabs(line))
			if line.contains("</pre>") {
				inPre = false
			}
		} else {
			let expanded = expandTabs(line)
			lines.append(String(expanded.drop(while: { $0 == " " })))
		}
	}

	return lines
		.joined(separator: "\n")
		.trimmingCharacters(in: .whitespacesAndNewlines)
}
