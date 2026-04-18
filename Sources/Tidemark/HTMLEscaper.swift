//
//  HTMLEscaper.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

/// Namespace for byte-level HTML and URL escaping routines used by the renderer.
///
/// All methods write escaped bytes into a `ByteArray`. The methods differ
/// in which characters they escape, to match the escaping rules of each
/// context in HTML output (text, code, attributes, URLs).
enum HTMLEscaper {

	/// Escape `&`, `<`, and `>` — for use inside `<code>` or `<pre>` blocks.
	static func escapeCode(_ bytes: [UInt8], into buffer: inout ByteArray, length: Int? = nil) {
		let end = length ?? bytes.count
		var pos = 0

		while pos < end {
			var next = pos
			while next < end {
				let byte = bytes[next]
				if byte == .asciiAmpersand || byte == .asciiLessThan || byte == .asciiGreaterThan {
					break
				}
				next += 1
			}

			if next > pos {
				buffer.append(bytes, start: pos, length: next - pos)
			}
			if next >= end {
				break
			}

			switch bytes[next] {
			case .asciiAmpersand:
				buffer.append(staticString: ampEntity)
			case .asciiLessThan:
				buffer.append(staticString: ltEntity)
			case .asciiGreaterThan:
				buffer.append(staticString: gtEntity)
			default:
				break
			}
			pos = next + 1
		}
	}

	/// Escape `&` and `<` — for regular text content.
	///
	/// For Gruber compatibility:
	/// - Existing HTML entities are passed through unchanged
	/// - `>` is not escaped (so "6 > 5" stays readable)
	static func escapeText(_ bytes: [UInt8], into buffer: inout ByteArray) {
		let end = bytes.count
		var pos = 0

		while pos < end {
			var next = pos
			while next < end {
				let byte = bytes[next]
				if byte == .asciiAmpersand || byte == .asciiLessThan {
					break
				}
				next += 1
			}

			if next > pos {
				buffer.append(bytes, start: pos, length: next - pos)
			}
			if next >= end {
				break
			}

			if bytes[next] == .asciiAmpersand {
				if let entityLen = entityLength(in: bytes, at: next) {
					buffer.append(bytes, start: next, length: entityLen)
					pos = next + entityLen
					continue
				}
				buffer.append(staticString: ampEntity)
			} else if bytes[next] == .asciiLessThan {
				buffer.append(staticString: ltEntity)
			}
			pos = next + 1
		}
	}

	/// Escape `&`, `<`, and `"` — for use inside attribute values.
	static func escapeAttribute(_ bytes: [UInt8], into buffer: inout ByteArray) {
		let end = bytes.count
		var pos = 0

		while pos < end {
			var next = pos
			while next < end {
				let byte = bytes[next]
				if byte == .asciiAmpersand || byte == .asciiLessThan || byte == .asciiDoubleQuote {
					break
				}
				next += 1
			}

			if next > pos {
				buffer.append(bytes, start: pos, length: next - pos)
			}
			if next >= end {
				break
			}

			switch bytes[next] {
			case .asciiAmpersand:
				buffer.append(staticString: ampEntity)
			case .asciiLessThan:
				buffer.append(staticString: ltEntity)
			case .asciiDoubleQuote:
				buffer.append(staticString: quotEntity)
			default:
				break
			}
			pos = next + 1
		}
	}

	/// Percent-encode characters not safe in URLs, and HTML-escape `&`
	/// (URLs are used in attribute context where `&` must be `&amp;`).
	static func escapeURL(_ bytes: [UInt8], into buffer: inout ByteArray) {
		let end = bytes.count
		var pos = 0

		while pos < end {
			// Scan past the run of URL-safe bytes.
			// Note: `&` is deliberately excluded from `isURLSafe` so it falls
			// through to be HTML-escaped below.
			var next = pos
			while next < end && bytes[next].isURLSafe {
				next += 1
			}

			if next > pos {
				buffer.append(bytes, start: pos, length: next - pos)
			}
			if next >= end {
				break
			}

			let byte = bytes[next]
			if byte == .asciiAmpersand {
				buffer.append(staticString: ampEntity)
			} else {
				appendPercentEncoded(byte, into: &buffer)
			}
			pos = next + 1
		}
	}
}

private extension HTMLEscaper {

	static let ampEntity: StaticString = "&amp;"
	static let ltEntity: StaticString = "&lt;"
	static let gtEntity: StaticString = "&gt;"
	static let quotEntity: StaticString = "&quot;"

	/// Maximum digits in a numeric HTML entity like `&#12345678;` or `&#xABCDEF12;`.
	static let maxEntityDigits = 8

	/// Maximum length of the name in a named HTML entity like `&CounterClockwiseContourIntegral;`.
	static let maxEntityNameLength = 32

	static let hexDigits: ContiguousArray<UInt8> = ContiguousArray("0123456789ABCDEF".utf8)

	/// If bytes starting at `pos` form a valid HTML entity (`&name;`,
	/// `&#123;`, or `&#xAB;`), return its length including the `&` and `;`.
	/// Returns nil if the bytes are not a valid entity.
	static func entityLength(in bytes: [UInt8], at startPos: Int) -> Int? {
		let count = bytes.count
		guard startPos < count, bytes[startPos] == .asciiAmpersand else {
			return nil
		}

		var scanPos = startPos + 1
		guard scanPos < count else {
			return nil
		}

		if bytes[scanPos] == .asciiHash {
			scanPos += 1
			guard scanPos < count else {
				return nil
			}

			if bytes[scanPos] == .asciiLowercaseX || bytes[scanPos] == .asciiUppercaseX {
				scanPos += 1
				let digitsStart = scanPos
				while scanPos < count && bytes[scanPos].isASCIIHexDigit {
					scanPos += 1
				}
				if scanPos == digitsStart || scanPos - digitsStart > maxEntityDigits {
					return nil
				}
			} else {
				let digitsStart = scanPos
				while scanPos < count && bytes[scanPos].isASCIIDigit {
					scanPos += 1
				}
				if scanPos == digitsStart || scanPos - digitsStart > maxEntityDigits {
					return nil
				}
			}
		} else {
			let nameStart = scanPos
			while scanPos < count && bytes[scanPos].isASCIIAlphanumeric {
				scanPos += 1
			}
			if scanPos == nameStart || scanPos - nameStart > maxEntityNameLength {
				return nil
			}
		}

		guard scanPos < count, bytes[scanPos] == .asciiSemicolon else {
			return nil
		}
		scanPos += 1

		return scanPos - startPos
	}

	/// Append a byte as a percent-encoded hex escape (e.g., `0x20` → `%20`).
	static func appendPercentEncoded(_ byte: UInt8, into buffer: inout ByteArray) {
		buffer.append(.asciiPercent)
		buffer.append(hexDigits[Int(byte >> 4)])
		buffer.append(hexDigits[Int(byte & 0x0F)])
	}
}
