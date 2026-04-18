//
//  NodeKind.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

/// The kind of an AST node, with associated data where applicable.
enum NodeKind: Sendable, Equatable {

	// Block-level
	case document									// root
	case paragraph									// text between blank lines
	case heading(level: Int)						// # Heading
	case blockquote									// > Quote
	case codeBlock([UInt8])							//     indented code
	case hrule										// ---
	case list(ListInfo)								// * item  or  1. item
	case listItem									// one entry in a list
	case htmlBlock([UInt8])							// <div>...</div>

	// Inline
	case text([UInt8])								// run of literal text
	case softbreak									// newline
	case hardbreak									// two trailing spaces + newline
	case emphasis									// *text* or _text_
	case strong										// **text** or __text__
	case codeSpan([UInt8])							// `code`
	case link(LinkInfo)								// [text](url) or [text][ref]
	case image(alt: [UInt8], link: LinkInfo)		// ![alt](url) or ![alt][ref]
	case htmlInline([UInt8])						// <span>...</span>
}

/// Unordered (`*`, `-`, `+`) or ordered (`1.`, `2.`, ...).
enum ListType: Sendable, Equatable {
	case unordered
	case ordered
}
