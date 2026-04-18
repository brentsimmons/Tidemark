//
//  ByteArray.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

/// A growable byte array used for collecting content during parsing and rendering.
///
/// Wraps `[UInt8]` with:
/// - a 64 MB size cap that guards against pathological content expansion
///   (for example, a large input of `"` characters expanding 6× when
///   HTML-escaped to `&quot;`)
/// - an efficient `append(staticString:)` path for HTML tag literals
///
/// All append methods are all-or-nothing: if adding the new bytes would
/// exceed the size cap, the append is silently dropped.
struct ByteArray {

	private static let maxBufferSize = 64 * 1024 * 1024 // 64 MB

	private var storage: [UInt8]

	init() {
		storage = []
	}

	init(estimatedCapacity: Int) {
		storage = []
		storage.reserveCapacity(min(estimatedCapacity, Self.maxBufferSize))
	}

	var count: Int {
		storage.count
	}

	/// The accumulated bytes. Returned via copy-on-write: no copy is made
	/// unless either the caller or the buffer mutates afterward.
	var bytes: [UInt8] {
		storage
	}

	mutating func append(_ byte: UInt8) {
		guard canAppend(1) else {
			return
		}
		storage.append(byte)
	}

	mutating func append(_ bytes: [UInt8]) {
		append(bytes, start: 0, length: bytes.count)
	}

	mutating func append(_ bytes: [UInt8], start: Int, length: Int) {
		guard canAppend(length) else {
			return
		}
		storage.append(contentsOf: bytes[start..<start + length])
	}

	mutating func append(staticString string: StaticString) {
		guard canAppend(string.utf8CodeUnitCount) else {
			return
		}
		string.withUTF8Buffer { buffer in
			storage.append(contentsOf: buffer)
		}
	}

	mutating func append(_ string: String) {
		let utf8 = string.utf8
		guard canAppend(utf8.count) else {
			return
		}
		storage.append(contentsOf: utf8)
	}

	func toString() -> String {
		String(decoding: storage, as: UTF8.self)
	}

	/// Return the accumulated bytes with trailing ASCII whitespace removed.
	func bytesTrimmingTrailingWhitespace() -> [UInt8] {
		var end = storage.count
		while end > 0 && storage[end - 1].isASCIIWhitespace {
			end -= 1
		}
		if end == storage.count {
			return storage // No trimming needed — CoW avoids copy
		}
		return Array(storage[0..<end])
	}
}

private extension ByteArray {

	/// Returns true if `length` bytes can be appended without exceeding the size cap.
	func canAppend(_ length: Int) -> Bool {
		length >= 0 && storage.count + length <= Self.maxBufferSize
	}
}
