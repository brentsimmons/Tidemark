//
//  ASCII.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

// MARK: - ASCII Byte Constants

extension UInt8 {

	static let asciiTab: UInt8 = 0x09
	static let asciiNewline: UInt8 = 0x0A
	static let asciiCarriageReturn: UInt8 = 0x0D
	static let asciiFormFeed: UInt8 = 0x0C
	static let asciiSpace: UInt8 = 0x20
	static let asciiBang: UInt8 = 0x21
	static let asciiDoubleQuote: UInt8 = 0x22
	static let asciiHash: UInt8 = 0x23
	static let asciiDollar: UInt8 = 0x24
	static let asciiPercent: UInt8 = 0x25
	static let asciiAmpersand: UInt8 = 0x26
	static let asciiSingleQuote: UInt8 = 0x27
	static let asciiLParen: UInt8 = 0x28
	static let asciiRParen: UInt8 = 0x29
	static let asciiAsterisk: UInt8 = 0x2A
	static let asciiPlus: UInt8 = 0x2B
	static let asciiComma: UInt8 = 0x2C
	static let asciiDash: UInt8 = 0x2D
	static let asciiDot: UInt8 = 0x2E
	static let asciiSlash: UInt8 = 0x2F
	static let asciiZero: UInt8 = 0x30
	static let asciiNine: UInt8 = 0x39
	static let asciiColon: UInt8 = 0x3A
	static let asciiSemicolon: UInt8 = 0x3B
	static let asciiLessThan: UInt8 = 0x3C
	static let asciiEquals: UInt8 = 0x3D
	static let asciiGreaterThan: UInt8 = 0x3E
	static let asciiQuestionMark: UInt8 = 0x3F
	static let asciiAt: UInt8 = 0x40
	static let asciiUppercaseA: UInt8 = 0x41
	static let asciiUppercaseF: UInt8 = 0x46
	static let asciiUppercaseX: UInt8 = 0x58
	static let asciiUppercaseZ: UInt8 = 0x5A
	static let asciiLBracket: UInt8 = 0x5B
	static let asciiBackslash: UInt8 = 0x5C
	static let asciiRBracket: UInt8 = 0x5D
	static let asciiUnderscore: UInt8 = 0x5F
	static let asciiBacktick: UInt8 = 0x60
	static let asciiLowercaseA: UInt8 = 0x61
	static let asciiLowercaseF: UInt8 = 0x66
	static let asciiLowercaseX: UInt8 = 0x78
	static let asciiLowercaseZ: UInt8 = 0x7A
	static let asciiLBrace: UInt8 = 0x7B
	static let asciiRBrace: UInt8 = 0x7D
	static let asciiTilde: UInt8 = 0x7E

	/// Difference between an uppercase ASCII letter and its lowercase form.
	static let asciiCaseOffset: UInt8 = 32

	// MARK: - Character Classification

	var isASCIIWhitespace: Bool {
		self == .asciiSpace
			|| self == .asciiTab
			|| self == .asciiNewline
			|| self == .asciiCarriageReturn
			|| self == .asciiFormFeed
	}

	var isASCIIDigit: Bool {
		self >= .asciiZero && self <= .asciiNine
	}

	var isASCIIHexDigit: Bool {
		isASCIIDigit
			|| (self >= .asciiUppercaseA && self <= .asciiUppercaseF)
			|| (self >= .asciiLowercaseA && self <= .asciiLowercaseF)
	}

	var isASCIIAlphanumeric: Bool {
		isASCIIDigit
			|| (self >= .asciiUppercaseA && self <= .asciiUppercaseZ)
			|| (self >= .asciiLowercaseA && self <= .asciiLowercaseZ)
	}

	var isASCIIPunctuation: Bool {
		MarkdownBytes.isPunctuation(self)
	}

	/// Whether this byte is safe to include in a URL without percent-encoding.
	///
	/// Covers the character set defined by RFC 3986:
	/// - unreserved characters (§2.3): alphanumerics and `- _ . ~`
	/// - reserved gen-delims (§2.2): `: / ? # [ ] @`
	/// - reserved sub-delims (§2.2): `! $ ' ( ) * + , ; =` (minus `&`,
	///   which is HTML-escaped separately for attribute context)
	/// - `%` so already-percent-encoded sequences pass through unchanged
	///
	/// See: https://datatracker.ietf.org/doc/html/rfc3986#section-2
	var isURLSafe: Bool {
		MarkdownBytes.isURLSafe(self)
	}

	var asciiLowercased: UInt8 {
		if self >= .asciiUppercaseA && self <= .asciiUppercaseZ {
			return self + .asciiCaseOffset
		}
		return self
	}
}
