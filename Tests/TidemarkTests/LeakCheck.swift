//
//  LeakCheck.swift
//  TidemarkTests
//
//  Created by Brent Simmons on 4/17/26.
//

import Testing
import Foundation
@testable import Tidemark

@Test func nodeLeakCheck() {
	// Parse many times, call destroy(), and verify all nodes are freed.
	// If destroy() fails to break all retain cycles, the weak references
	// remain non-nil.
	var weakRefs: [WeakNode] = []

	autoreleasepool {
		for _ in 0..<10 {
			let doc = Parser.parse("Hello *world* with [link](http://example.com) and `code`.")
			weakRefs.append(WeakNode(doc))
			doc.destroy()
		}
	}

	let survivors = weakRefs.compactMap { $0.node }.count
	#expect(survivors == 0, "\(survivors)/10 Node trees leaked (retain cycles)")
}

@Test func delimiterLeakCheck() {
	// Verify that emphasis delimiter objects don't leak. Each paragraph
	// with emphasis creates Delimiter instances; destroy() must break
	// all cycles so they can be freed.
	var weakRefs: [WeakNode] = []

	autoreleasepool {
		for _ in 0..<10 {
			let doc = Parser.parse("This *has* **many** *emphasis* **markers** and _underscores_ too.")
			weakRefs.append(WeakNode(doc))
			doc.destroy()
		}
	}

	let survivors = weakRefs.compactMap { $0.node }.count
	#expect(survivors == 0, "\(survivors)/10 Node trees leaked (delimiter retain cycles)")
}

private final class WeakNode {
	weak var node: Node?
	init(_ node: Node) {
		self.node = node
	}
}
