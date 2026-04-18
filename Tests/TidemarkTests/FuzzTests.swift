//
//  FuzzTests.swift
//  TidemarkTests
//
//  Created by Brent Simmons on 4/17/26.
//

import Testing
@testable import Tidemark

// MARK: - Fuzz Testing
//
// These tests feed pseudo-random byte sequences to the parser to
// verify it never crashes, hangs, or traps on arbitrary input.
//
// Each test uses a deterministic seed so failures are reproducible.
// The generator mixes plain ASCII, Markdown-significant bytes, and
// raw binary to exercise both normal paths and edge cases.

@Test(arguments: 0..<100)
func fuzzRandomBytes(_ seed: Int) {
	let bytes = FuzzGenerator.randomBytes(seed: seed, count: 512)
	_ = markdownToHTML(bytes)
}

@Test(arguments: 0..<100)
func fuzzMarkdownHeavy(_ seed: Int) {
	let bytes = FuzzGenerator.markdownHeavyBytes(seed: seed, count: 1024)
	_ = markdownToHTML(bytes)
}

@Test(arguments: 0..<20)
func fuzzLargeInput(_ seed: Int) {
	let bytes = FuzzGenerator.markdownHeavyBytes(seed: seed, count: 16384)
	_ = markdownToHTML(bytes)
}

@Test(arguments: 0..<50)
func fuzzRepeatedPatterns(_ seed: Int) {
	let bytes = FuzzGenerator.repeatedPattern(seed: seed, count: 2048)
	_ = markdownToHTML(bytes)
}

// MARK: - Generator

/// Deterministic pseudo-random byte generator for fuzz testing.
///
/// Uses a simple xorshift64 PRNG seeded from the test argument,
/// so every run produces the same bytes for the same seed.
private enum FuzzGenerator {

	/// Pure random bytes — exercises error recovery on malformed UTF-8
	/// and unexpected byte values.
	static func randomBytes(seed: Int, count: Int) -> [UInt8] {
		var rng = XorShift64(seed: UInt64(bitPattern: Int64(seed &+ 1)))
		var bytes = [UInt8]()
		bytes.reserveCapacity(count)
		for _ in 0..<count {
			bytes.append(UInt8(truncatingIfNeeded: rng.next()))
		}
		return bytes
	}

	/// Bytes biased toward Markdown-significant characters — exercises
	/// the parser's inline and block-level logic more heavily than
	/// pure random bytes.
	static func markdownHeavyBytes(seed: Int, count: Int) -> [UInt8] {
		var rng = XorShift64(seed: UInt64(bitPattern: Int64(seed &+ 1)))
		var bytes = [UInt8]()
		bytes.reserveCapacity(count)
		for _ in 0..<count {
			let r = rng.next()
			if r % 3 == 0 {
				// Pick from Markdown-significant bytes
				bytes.append(markdownChars[Int(truncatingIfNeeded: r >> 8) & 0x7FFF_FFFF % markdownChars.count])
			} else {
				// ASCII printable + whitespace
				let byte = UInt8(truncatingIfNeeded: r >> 8) % 96 + 0x20
				bytes.append(byte)
			}
		}
		return bytes
	}

	/// A short pattern repeated many times — catches quadratic behavior
	/// in delimiter matching, bracket scanning, or entity detection.
	static func repeatedPattern(seed: Int, count: Int) -> [UInt8] {
		var rng = XorShift64(seed: UInt64(bitPattern: Int64(seed &+ 1)))
		let patternLen = Int(rng.next() & 7) + 2 // 2–9 bytes
		var pattern = [UInt8]()
		for _ in 0..<patternLen {
			pattern.append(markdownChars[Int(truncatingIfNeeded: rng.next()) & 0x7FFF_FFFF % markdownChars.count])
		}
		var bytes = [UInt8]()
		bytes.reserveCapacity(count)
		while bytes.count < count {
			bytes.append(contentsOf: pattern)
		}
		return Array(bytes.prefix(count))
	}

	private static let markdownChars: [UInt8] = [
		.asciiAsterisk, .asciiUnderscore, .asciiBacktick,
		.asciiLBracket, .asciiRBracket, .asciiLParen, .asciiRParen,
		.asciiLessThan, .asciiGreaterThan, .asciiHash,
		.asciiDash, .asciiPlus, .asciiDot, .asciiEquals,
		.asciiBang, .asciiBackslash, .asciiAmpersand,
		.asciiSpace, .asciiTab, .asciiNewline,
		.asciiColon, .asciiDoubleQuote, .asciiSingleQuote
	]
}

// MARK: - PRNG

/// Minimal xorshift64 PRNG — deterministic, no Foundation dependency.
private struct XorShift64 {

	var state: UInt64

	init(seed: UInt64) {
		state = seed == 0 ? 1 : seed
	}

	mutating func next() -> UInt64 {
		state ^= state << 13
		state ^= state >> 7
		state ^= state << 17
		return state
	}
}
