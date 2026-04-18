//
//  main.swift
//  Benchmark
//
//  Created by Brent Simmons on 4/15/26.
//

import Foundation
import Tidemark

let args = CommandLine.arguments
guard args.count >= 3 else {
	fputs("Usage: benchmark <iterations> <file> [file...]\n", stderr)
	exit(1)
}

let iterations = max(Int(args[1]) ?? 1000, 1)

for i in 2..<args.count {
	let path = args[i]
	guard let data = FileManager.default.contents(atPath: path) else {
		fputs("Could not open: \(path)\n", stderr)
		continue
	}

	let bytes = Array(data)
	let size = bytes.count

	// Warm up
	for _ in 0..<100 {
		_ = markdownToHTML(bytes)
	}

	// Benchmark
	let start = ContinuousClock.now
	for _ in 0..<iterations {
		_ = markdownToHTML(bytes)
	}
	let elapsed = ContinuousClock.now - start

	let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
	let perIter = seconds / Double(iterations)

	// Print: filename <tab> size <tab> time
	let name = URL(fileURLWithPath: path).lastPathComponent
	print(String(format: "%@\t%d\t%.6f", name, size, perIter))
}
