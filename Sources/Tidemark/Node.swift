//
//  Node.swift
//  Tidemark
//
//  Created by Brent Simmons on 4/15/26.
//

/// A node in the parsed Markdown document tree.
///
/// Every Markdown construct — document, paragraph, heading, list item,
/// emphasis, link, text run, etc. — becomes a `Node` with a specific
/// `NodeKind`. The block parser builds the top-level tree; the inline
/// parser fills in paragraph/heading children. The renderer walks the
/// tree in document order to produce HTML.
///
/// Tree structure is a doubly-linked sibling list per parent. Each node
/// has:
/// - `firstChild` / `lastChild` — the first and last child of this node
/// - `next` / `prev` — the next and previous siblings
/// - `parent` — the containing node
///
/// All references are strong. The `parent` and `prev` back-references
/// create retain cycles, so callers must call `destroy()` on the root
/// node when the tree is no longer needed. This is simpler and safer
/// than `unowned(unsafe)`, and avoids the runtime cost of `weak`.
final class Node {
	var kind: NodeKind
	var parent: Node?
	var firstChild: Node?
	var lastChild: Node?
	var next: Node?
	var prev: Node?

	init(kind: NodeKind) {
		self.kind = kind
	}

	/// Append `child` as the last child of this node.
	/// The child must not already be in a tree.
	func appendChild(_ child: Node) {
		child.parent = self
		child.next = nil
		child.prev = lastChild

		if let last = lastChild {
			last.next = child
		} else {
			firstChild = child
		}

		lastChild = child
	}

	/// Insert this node immediately after `sibling` under the same parent.
	/// Used during emphasis processing to splice a new `.emphasis` or
	/// `.strong` node into place.
	func insertAfter(_ sibling: Node) {
		parent = sibling.parent
		prev = sibling
		next = sibling.next

		if let siblingNext = sibling.next {
			siblingNext.prev = self
		} else {
			sibling.parent?.lastChild = self
		}

		sibling.next = self
	}

	/// Remove this node from its parent's child list. Leaves the node's
	/// own children intact — only the sibling/parent links are detached.
	func unlink() {
		if let prev {
			prev.next = next
		} else {
			parent?.firstChild = next
		}

		if let next {
			next.prev = prev
		} else {
			parent?.lastChild = prev
		}

		parent = nil
		prev = nil
		next = nil
	}

	/// Break all retain cycles in this subtree so the nodes can be freed.
	/// Call this on the root document node when the tree is no longer needed.
	///
	/// Uses an iterative depth-first walk (no recursion) so deeply nested
	/// documents cannot cause a stack overflow.
	func destroy() {
		var current: Node? = self

		while let node = current {
			if let child = node.firstChild {
				// Descend: move to the first child. Clear the parent's
				// firstChild so that when we backtrack to this node later
				// (via its `parent` link), we'll take the "no children"
				// path and nil it out.
				node.firstChild = nil
				current = child
			} else if let next = node.next {
				// Advance to the next sibling. Nil out this node's links.
				node.parent = nil
				node.lastChild = nil
				node.next = nil
				node.prev = nil
				current = next
			} else {
				// No children, no next sibling — backtrack to the parent.
				let backtrack = node.parent
				node.parent = nil
				node.lastChild = nil
				node.prev = nil
				current = backtrack
			}
		}
	}

	/// Append a text child node.
	func appendTextChild(_ text: [UInt8]) {
		guard !text.isEmpty else {
			return
		}
		appendChild(Node(kind: .text(text)))
	}

	/// Append a text child node from a subrange.
	func appendTextChild(_ text: [UInt8], start: Int, length: Int) {
		guard length > 0 else {
			return
		}
		appendChild(Node(kind: .text(Array(text[start..<start + length]))))
	}

	/// Iterate over this node's children in order.
	///
	///     for child in node.children { ... }
	var children: some Sequence<Node> {
		sequence(state: firstChild) { cursor in
			guard let node = cursor else {
				return nil
			}
			cursor = node.next
			return node
		}
	}
}

// MARK: - Supporting Types

/// Metadata for a list node.
///
/// Example (unordered, tight):
///
///     * Apple
///     * Banana
///
/// Example (ordered, loose — blank lines between items):
///
///     1. First
///
///     2. Second
///
struct ListInfo: Sendable, Equatable {
	let type: ListType
	let marker: UInt8
	var tight: Bool
}

/// Metadata for a link or image node.
///
/// Example (link):
///
///     [text](http://example.com "Title")
///
/// Example (image):
///
///     ![alt text](photo.jpg)
///
struct LinkInfo: Sendable, Equatable {
	let urlBytes: [UInt8]
	let titleBytes: [UInt8]?
}
