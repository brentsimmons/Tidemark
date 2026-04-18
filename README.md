# Tidemark

Tidemark parses and renders Markdown. Original Markdown, with no extensions.

It’s available as a Swift Package Manager (SPM) package.

## Security

Tidemark is written in safe Swift — no `UnsafePointer`, `UnsafeBufferPointer`, `unowned(unsafe)`, or any other `Unsafe` types.

Input size, output buffer size, nesting depth, delimiter count, and link reference count are all capped to prevent pathological input from exhausting memory. These limits are tested by a fuzz suite that feeds random and Markdown-heavy byte sequences to the parser.

## How to use

```swift
import Tidemark

let html = markdownToHTML("Hello *world*")
// html == "<p>Hello <em>world</em></p>\n"
```

There’s also a `[UInt8]` overload for when you already have bytes:

```swift
let bytes: [UInt8] = Array(markdownString.utf8)
let html = markdownToHTML(bytes)
```

## Command-Line Tool

Tidemark includes a command-line tool that works like Markdown.pl.

### Building

```bash
swift build -c release
```

The built binary is at `.build/release/tidemark`. Copy it somewhere in your `$PATH` to install.

### Usage

```bash
tidemark file.md                 # Convert a file to stdout
tidemark < file.md               # Read from stdin
cat file.md | tidemark           # Pipe
tidemark file.md > file.html     # Convert to a new file
tidemark one.md two.md           # Multiple files
tidemark --version               # Print version
tidemark --help                  # Print usage
```

## Benchmarks

### Test Environment

- **Machine:** Mac Studio
- **CPU:** Apple M1 Max
- **Cores:** 10 (8 performance + 2 efficiency)
- **Memory:** 64 GB
- **OS:** macOS 26.2
- **Build:** Release

### Methodology

Each file is parsed and rendered 10,000 times (after 100 warmup iterations). Times are per-iteration averages measured with `ContinuousClock`.

The test corpus consists of 12 real-world Markdown files totaling 139 KB.

### Results

#### Summary

| Operation      | Size   | Time (s) | Throughput |
|----------------|--------|----------|------------|
| Parse + Render | 139 KB | 0.001404 | 101 MB/s   |

#### Individual File Performance

| File                        | Size    | Time (s) |
|-----------------------------|---------|----------|
| ballard_lang                | 38.8 KB | 0.000417 |
| untrue                      | 13.1 KB | 0.000137 |
| what_happened_at_userland   | 12.5 KB | 0.000112 |
| anatomy_of_a_feature        | 10.1 KB | 0.000106 |
| what_happened_at_newsgator  |  9.8 KB | 0.000097 |
| implementing_single_key_... |  8.8 KB | 0.000098 |
| the_design_of_netnewswir... |  8.6 KB | 0.000079 |
| brians_stupid_feed_tricks   |  8.6 KB | 0.000077 |
| things_i_learned_doing_r... |  8.5 KB | 0.000097 |
| starting_over               |  8.2 KB | 0.000073 |
| why_netnewswire_is_fast     |  7.9 KB | 0.000077 |
| langvalue                   |  3.8 KB | 0.000034 |

### Running Benchmarks

```bash
./run-benchmarks.sh                    # Print results
./run-benchmarks.sh --update-readme    # Print results and update this file
```

## Contributing

We’re not adding features, but we welcome bug reports, PRs to fix bugs, and PRs to add tests.

Please run `swift test` and `swiftlint` before submitting a PR.

## License

MIT. See [LICENSE](LICENSE) for details.
