//
//  Tidemark.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

/// Convert Markdown to HTML in a single call.
public func markdownToHTML(_ markdown: String) -> String {
	guard !markdown.isEmpty else {
		return ""
	}

	let bytes = Array(markdown.utf8)
	return markdownToHTML(bytes)
}

/// Convert Markdown bytes to HTML in a single call.
public func markdownToHTML(_ markdown: [UInt8]) -> String {
	guard !markdown.isEmpty else {
		return ""
	}

	let document = Parser.parse(markdown)
	let html = renderHTML(document, inputLength: markdown.count)
	document.destroy()
	return html
}
