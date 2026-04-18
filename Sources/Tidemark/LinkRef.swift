//
//  LinkRef.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

/// A link reference definition collected during parsing.
/// Stored in a dictionary keyed by the normalized label
/// (lowercased with runs of whitespace collapsed to a single space).
///
/// Example:
///
///     [example]: http://example.com "Example Title"
///
/// Here `urlBytes` is `http://example.com` and `titleBytes` is `Example Title`.
/// The label (`example`) is the dictionary key in `LinkRefTable`, not a field here.
struct LinkRef: Sendable {
	let urlBytes: [UInt8]
	let titleBytes: [UInt8]?
}

/// Table of link reference definitions, keyed by the normalized label.
///
/// Matches Markdown.pl's behavior: case-insensitivity is specified by
/// Gruber's Markdown spec, and runs of whitespace are collapsed to a
/// single space (implicit in Markdown.pl, not in the prose spec).
/// So `[Foo  Bar]` and `[foo bar]` refer to the same definition.
struct LinkRefTable: Sendable {

	/// Cap on the number of link definitions a single document may contribute,
	/// so pathological input (e.g., a million `[x]: url` lines) can't exhaust
	/// memory via the backing dictionary. Real documents have at most a few
	/// dozen link references.
	private static let maxRefs = 10_000

	private var refs: [String: LinkRef] = [:]

	/// Look up a link reference by label (normalized first).
	func find(_ label: [UInt8]) -> LinkRef? {
		refs[normalizeLabel(label)]
	}

	/// Add a link reference. First definition wins — duplicates are ignored.
	mutating func add(label: [UInt8], url: [UInt8], title: [UInt8]?) {
		guard refs.count < Self.maxRefs else {
			return
		}
		let normalized = normalizeLabel(label)
		guard !normalized.isEmpty, refs[normalized] == nil else {
			return
		}

		refs[normalized] = LinkRef(urlBytes: url, titleBytes: title)
	}

	/// Merge references from another table. Existing refs take precedence.
	/// Stops adding once the size cap is reached.
	mutating func merge(from other: LinkRefTable) {
		for (key, ref) in other.refs where refs[key] == nil {
			guard refs.count < Self.maxRefs else {
				return
			}
			refs[key] = ref
		}
	}
}

private extension LinkRefTable {

	/// Normalize a label for case-insensitive, whitespace-collapsed lookup.
	func normalizeLabel(_ label: [UInt8]) -> String {
		var result = [UInt8]()
		result.reserveCapacity(label.count)
		var lastWasSpace = true

		for byte in label {
			if byte.isASCIIWhitespace {
				if !lastWasSpace {
					result.append(.asciiSpace)
					lastWasSpace = true
				}
			} else {
				result.append(byte.asciiLowercased)
				lastWasSpace = false
			}
		}

		if result.last == .asciiSpace {
			result.removeLast()
		}

		return String(decoding: result, as: UTF8.self)
	}
}
