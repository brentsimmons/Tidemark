//
//  main.swift
//  tidemark
//
//  Created by Brent Simmons on 4/18/26.
//

import Foundation
import Tidemark

let tidemarkVersion = "1.0.0"

let args = CommandLine.arguments.dropFirst()

// Parse flags

var filePaths = [String]()

for arg in args {
	if arg == "--version" {
		print("Tidemark \(tidemarkVersion)")
		exit(0)
	}
	if arg == "--shortversion" {
		print(tidemarkVersion)
		exit(0)
	}
	if arg == "--help" {
		printUsage()
		exit(0)
	}
	if arg == "--html4tags" {
		continue // Already our default behavior
	}
	if arg.hasPrefix("--") {
		fputs("Unknown option: \(arg)\n", stderr)
		printUsage()
		exit(1)
	}
	filePaths.append(arg)
}

// Convert

if filePaths.isEmpty {
	let data = FileHandle.standardInput.readDataToEndOfFile()
	let bytes = Array(data)
	print(markdownToHTML(bytes), terminator: "")
} else {
	for path in filePaths {
		guard let data = FileManager.default.contents(atPath: path) else {
			fputs("Error: could not read \(path)\n", stderr)
			exit(1)
		}
		let bytes = Array(data)
		print(markdownToHTML(bytes), terminator: "")
	}
}

// MARK: - Helpers

func printUsage() {
	fputs("""
	Usage: tidemark [options] [file ...]

	Options:
	  --html4tags      Accepted for Markdown.pl compatibility (already the default)
	  --version        Print version
	  --shortversion   Print version number only
	  --help           Print this help

	With no file arguments, reads from standard input.

	""", stderr)
}
