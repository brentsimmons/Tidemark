//
//  TokenType.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

enum TokenType: Int, Sendable {

	case eof = 0

	// Text content
	case text
	case newline
	case blankLine
	case hardBreak

	// Block-level structure
	case atxHeader1
	case atxHeader2
	case atxHeader3
	case atxHeader4
	case atxHeader5
	case atxHeader6
	case setextHeader1
	case setextHeader2

	case blockquote
	case codeBlockIndent

	case hrule

	// List markers
	case ulMarker
	case olMarker
}

extension TokenType {

	/// The heading level (1–6) for ATX header tokens, or nil for other token types.
	var headingLevel: Int? {
		switch self {
		case .atxHeader1:
			return 1
		case .atxHeader2:
			return 2
		case .atxHeader3:
			return 3
		case .atxHeader4:
			return 4
		case .atxHeader5:
			return 5
		case .atxHeader6:
			return 6
		default:
			return nil
		}
	}
}
