//
//  Token.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

struct Token: Sendable {
	let type: TokenType
	let start: Int			// Byte offset into input
	let length: Int
	let line: Int
	let column: Int

	static let eof = Token(type: .eof, start: 0, length: 0, line: 1, column: 1)
}
