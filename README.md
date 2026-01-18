# utf8-index

A SIMD-accelerated UTF-8 character indexer for Zig. Maps character positions to byte offsets with O(1) lookup time.

## Features

- **SIMD-accelerated indexing**: Uses 32-byte vector operations for fast ASCII detection
- **O(1) character lookup**: Get byte offset, character length, or character value instantly
- **Zero-copy slicing**: Extract substrings by character indices
- **Fast character counting**: Count UTF-8 characters without building a full index
- **Supports files up to 4GB**: Uses full u32 range for byte offsets

## Requirements

- Zig 0.15.0 or later

## Building

```bash
# Build the CLI tool
zig build

# Run tests
zig build test

# Build with optimizations
zig build -Doptimize=ReleaseFast
```

## CLI Usage

```bash
# Analyze a UTF-8 string showing all character positions
./bin/utf8-index analyze "Hello世界"

# Count characters in a string
./bin/utf8-index count "Hello, 世界! 🎉"

# Get character at index (0-based)
./bin/utf8-index char "a世b🎉c" 3

# Get character slice [start..end)
./bin/utf8-index slice "Hello世界!" 5 7

# Analyze a file
./bin/utf8-index file input.txt

# Options
./bin/utf8-index -a file input.txt      # Show ALL characters
./bin/utf8-index -n 50 file input.txt   # Limit to first 50 characters
./bin/utf8-index -m file input.txt      # Show only multibyte (non-ASCII) chars
./bin/utf8-index -m -a file input.txt   # All multibyte characters
```

### Example File

An `example.txt` file is included with mixed UTF-8 content for testing — it contains
Japanese text (日本語), mathematical symbols (∑, ∫, π, √), emojis (🎉, 🍣, 🚀), and
other Unicode characters. Try:

```bash
./bin/utf8-index -m -a file example.txt   # See all 49 multibyte characters
./bin/utf8-index count "$(cat example.txt)"
```

### Example Output

```
$ ./bin/utf8-index analyze "Hello世界"

Input: "Hello世界"
Bytes: 11
Characters: 7

  Idx  Offset   Len  Char    Bytes (hex)
--------------------------------------------------
    0       0     1  H       48
    1       1     1  e       65
    2       2     1  l       6c
    3       3     1  l       6c
    4       4     1  o       6f
    5       5     3  世      e4 b8 96
    6       8     3  界      e7 95 8c
```

```
$ ./bin/utf8-index char "a世b🎉c" 3

Index: 3
Character: 🎉
Codepoint: U+1F389
Byte offset: 5
Byte length: 4
Bytes: f0 9f 8e 89
```

## Library Usage

```zig
const std = @import("std");
const Utf8Index = @import("utf8_index").Utf8Index;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var idx = Utf8Index.init(allocator, "Hello, 世界! 🎉");
    defer idx.deinit();
    try idx.build();

    // Get character count
    std.debug.print("Characters: {d}\n", .{idx.len()});

    // Get byte offset for character index (O(1))
    if (idx.byteOffset(7)) |offset| {
        std.debug.print("Character 7 starts at byte {d}\n", .{offset});
    }

    // Get character at index (O(1))
    if (idx.charAt(7)) |char| {
        std.debug.print("Character 7: {u}\n", .{char});
    }

    // Get slice by character indices
    if (idx.slice(7, 9)) |s| {
        std.debug.print("Slice [7..9): {s}\n", .{s});
    }

    // Fast character count (without full index)
    const count = Utf8Index.countChars("Quick count 🚀");
    std.debug.print("Fast count: {d}\n", .{count});
}
```

## API Reference

### `Utf8Index`

#### Methods

| Method | Description | Complexity |
|--------|-------------|------------|
| `init(allocator, source)` | Create a new index | O(1) |
| `build()` | Build the index with SIMD | O(n) |
| `deinit()` | Free resources | O(1) |
| `len()` | Get character count | O(1) |
| `byteOffset(char_idx)` | Get byte offset for character | O(1) |
| `charLen(char_idx)` | Get character length in bytes | O(1) |
| `charAt(char_idx)` | Get Unicode codepoint at index | O(1) |
| `charBytes(char_idx)` | Get byte slice for character | O(1) |
| `slice(start, end)` | Get byte slice for character range | O(1) |
| `countChars(source)` | Fast character count (static) | O(n) |

## How It Works

The indexer builds an array of byte offsets where each entry corresponds to a character position. For ASCII-heavy text, it uses SIMD to process 32 bytes at a time, detecting runs of pure ASCII and writing offsets in batches of 8 using vector operations.

For multibyte UTF-8 sequences, it falls back to scalar processing, computing offsets from the lead byte pattern:

- `0xxxxxxx` → 1 byte (ASCII)
- `110xxxxx` → 2 bytes
- `1110xxxx` → 3 bytes
- `11110xxx` → 4 bytes

## License

MIT
