//
//  MarkdownRenderTests.swift
//  TidemarkTests
//
//  Created by Brent Simmons on 4/15/26.
//

import Testing
import Foundation
@testable import Tidemark

@Test func allMarkdownFiles() throws {
	let resourcesURL = try resourcesDirectory()
	let fileManager = FileManager.default
	let contents = try fileManager.contentsOfDirectory(atPath: resourcesURL.path)

	let markdownFiles = contents
		.filter { $0.hasSuffix(".markdown") }
		.map { String($0.dropLast(".markdown".count)) }

	#expect(!markdownFiles.isEmpty, "No .markdown files found in Resources")

	for testName in markdownFiles {
		try runRenderTest(testName, resourcesURL: resourcesURL)
	}
}

// MARK: - Helpers

private func runRenderTest(_ testName: String, resourcesURL: URL) throws {
	let markdownURL = resourcesURL.appendingPathComponent("\(testName).markdown")
	let htmlURL = resourcesURL.appendingPathComponent("\(testName).html")

	let markdownData = try Data(contentsOf: markdownURL)
	let expectedData = try Data(contentsOf: htmlURL)

	let markdownBytes = Array(markdownData)
	let expected = String(decoding: expectedData, as: UTF8.self)
	let actual = markdownToHTML(markdownBytes)

	#expect(actual == expected, "HTML mismatch for \(testName)")
}

private func resourcesDirectory() throws -> URL {
	let bundle = Bundle.module
	guard let url = bundle.url(forResource: "Resources", withExtension: nil) else {
		throw ResourceError.notFound
	}
	return url
}

private enum ResourceError: Error {
	case notFound
}
