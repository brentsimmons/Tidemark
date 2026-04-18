// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "Tidemark",
	platforms: [
		.macOS(.v14),
		.iOS(.v17)
	],
	products: [
		.library(
			name: "Tidemark",
			targets: ["Tidemark"]
		),
		.executable(
			name: "tidemark",
			targets: ["TidemarkCLI"]
		)
	],
	targets: [
		.target(
			name: "Tidemark"
		),
		.executableTarget(
			name: "TidemarkCLI",
			dependencies: ["Tidemark"]
		),
		.executableTarget(
			name: "Benchmark",
			dependencies: ["Tidemark"]
		),
		.testTarget(
			name: "TidemarkTests",
			dependencies: ["Tidemark"],
			resources: [
				.copy("Resources")
			]
		)
	]
)
