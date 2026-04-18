//
//  LookupTables.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

/// Fast O(1) byte classification for the Markdown inline parser.
///
/// Backed by a 256-byte lookup table so each check is a single
/// indexed load rather than a chain of comparisons.
enum MarkdownBytes {

	/// True for bytes that a backslash can escape in Markdown.
	///
	/// Characters: `\` `` ` `` `*` `_` `{` `}` `[` `]` `(` `)` `#` `+` `-` `.` `!` `<` `>`
	static func isEscapable(_ byte: UInt8) -> Bool {
		escapableTable[Int(byte)]
	}

	/// True for bytes safe in a URL without percent-encoding (RFC 3986).
	///
	/// Note: `&` is excluded — it is HTML-escaped separately in attribute context.
	static func isURLSafe(_ byte: UInt8) -> Bool {
		urlSafeTable[Int(byte)]
	}

	/// True for ASCII punctuation characters.
	///
	/// Ranges: `!`–`/`, `:`–`@`, `[`–`` ` ``, `{`–`~`
	static func isPunctuation(_ byte: UInt8) -> Bool {
		punctuationTable[Int(byte)]
	}
}

private extension MarkdownBytes {

	static let escapableTable: [Bool] = {
		var table = [Bool](repeating: false, count: 256)
		table[Int(UInt8.asciiBang)] = true
		table[Int(UInt8.asciiHash)] = true
		table[Int(UInt8.asciiLParen)] = true
		table[Int(UInt8.asciiRParen)] = true
		table[Int(UInt8.asciiAsterisk)] = true
		table[Int(UInt8.asciiPlus)] = true
		table[Int(UInt8.asciiDash)] = true
		table[Int(UInt8.asciiDot)] = true
		table[Int(UInt8.asciiLessThan)] = true
		table[Int(UInt8.asciiGreaterThan)] = true
		table[Int(UInt8.asciiLBracket)] = true
		table[Int(UInt8.asciiBackslash)] = true
		table[Int(UInt8.asciiRBracket)] = true
		table[Int(UInt8.asciiUnderscore)] = true
		table[Int(UInt8.asciiBacktick)] = true
		table[Int(UInt8.asciiLBrace)] = true
		table[Int(UInt8.asciiRBrace)] = true
		return table
	}()

	static let punctuationTable: [Bool] = {
		var table = [Bool](repeating: false, count: 256)
		for byte in UInt8.asciiBang...UInt8.asciiSlash { table[Int(byte)] = true }
		for byte in UInt8.asciiColon...UInt8.asciiAt { table[Int(byte)] = true }
		for byte in UInt8.asciiLBracket...UInt8.asciiBacktick { table[Int(byte)] = true }
		for byte in UInt8.asciiLBrace...UInt8.asciiTilde { table[Int(byte)] = true }
		return table
	}()

	static let urlSafeTable: [Bool] = {
		var table = [Bool](repeating: false, count: 256)
		// Alphanumerics
		for byte in UInt8.asciiZero...UInt8.asciiNine { table[Int(byte)] = true }
		for byte in UInt8.asciiUppercaseA...UInt8.asciiUppercaseZ { table[Int(byte)] = true }
		for byte in UInt8.asciiLowercaseA...UInt8.asciiLowercaseZ { table[Int(byte)] = true }
		// RFC 3986 unreserved: - _ . ~
		table[Int(UInt8.asciiDash)] = true
		table[Int(UInt8.asciiUnderscore)] = true
		table[Int(UInt8.asciiDot)] = true
		table[Int(UInt8.asciiTilde)] = true
		// RFC 3986 gen-delims: : / ? # [ ] @
		table[Int(UInt8.asciiColon)] = true
		table[Int(UInt8.asciiSlash)] = true
		table[Int(UInt8.asciiQuestionMark)] = true
		table[Int(UInt8.asciiHash)] = true
		table[Int(UInt8.asciiLBracket)] = true
		table[Int(UInt8.asciiRBracket)] = true
		table[Int(UInt8.asciiAt)] = true
		// RFC 3986 sub-delims (minus &): ! $ ' ( ) * + , ; =
		table[Int(UInt8.asciiBang)] = true
		table[Int(UInt8.asciiDollar)] = true
		table[Int(UInt8.asciiSingleQuote)] = true
		table[Int(UInt8.asciiLParen)] = true
		table[Int(UInt8.asciiRParen)] = true
		table[Int(UInt8.asciiAsterisk)] = true
		table[Int(UInt8.asciiPlus)] = true
		table[Int(UInt8.asciiComma)] = true
		table[Int(UInt8.asciiSemicolon)] = true
		table[Int(UInt8.asciiEquals)] = true
		// % for pass-through of existing percent-encoding
		table[Int(UInt8.asciiPercent)] = true
		return table
	}()
}
