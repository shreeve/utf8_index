# Agent Onboarding

Quick-start guide for AI assistants working on this project.

## Project Overview

**utf8-index** is a SIMD-accelerated UTF-8 character indexer written in Zig. It solves the problem of O(n) character lookups in UTF-8 strings by building an index that maps character positions to byte offsets, enabling O(1) access.

### Core Value Proposition
- UTF-8 is variable-width (1-4 bytes per character)
- Without an index, finding character N requires scanning from the start
- This library builds an offset array once, then provides instant lookups

## Project Structure

```
utf8-index/
├── build.zig           # Build configuration
├── build.zig.zon       # Package manifest
├── src/
│   ├── utf8_index.zig  # Library (Utf8Index struct)
│   └── main.zig        # CLI binary
├── bin/
│   └── utf8-index      # Built executable
├── example.txt         # Test file with mixed UTF-8
├── ZIG-0.15.2.md       # Zig 0.15.2 language reference
└── README.md           # User documentation
```

## Important: Zig 0.15.2

This project uses **Zig 0.15.2** which has major breaking changes from earlier versions. Before making changes, read `ZIG-0.15.2.md` for:

- **New I/O API**: `std.Io.Writer` is non-generic, buffer is above vtable
- **Build system**: Must use `root_module` (not `root_source_file`)
- **ArrayList**: Use `ArrayListUnmanaged` with explicit allocator passing
- **Format strings**: Use `{any}` for debug output (not `{}`)

### Quick I/O Pattern (0.15.x)
```zig
var buffer: [4096]u8 = undefined;
var writer = std.fs.File.stdout().writer(&buffer);
const w: *std.Io.Writer = &writer.interface;
try w.print("text\n", .{});
try w.flush();
```

## Building & Testing

```bash
zig build              # Build to bin/utf8-index
zig build test         # Run unit tests
zig build -Doptimize=ReleaseFast  # Optimized build
```

## CLI Usage

```bash
./bin/utf8-index analyze "Hello世界"      # Show all character positions
./bin/utf8-index count "text"             # Count with byte-length breakdown
./bin/utf8-index char "a世b🎉c" 3         # Get character at index
./bin/utf8-index slice "Hello世界!" 5 7   # Slice by character indices
./bin/utf8-index file example.txt         # Analyze a file

# Options
-a, --all        Show all characters (not just first 20)
-n <N>           Limit to N characters  
-m, --multibyte  Show only non-ASCII characters
```

## Test File

`example.txt` contains a realistic mixed UTF-8 document with:
- Japanese text (日本語, kanji)
- Mathematical symbols (∑, ∫, π, √, ∇, ∂, ζ)
- Emojis (🎉, 🍣, 🚀, 😊)
- Various Unicode (em-dash, superscripts, subscripts)

Test with:
```bash
./bin/utf8-index -m -a file example.txt  # All 49 multibyte characters
```

## Library API

```zig
const Utf8Index = @import("utf8_index").Utf8Index;

var idx = Utf8Index.init(allocator, source);
defer idx.deinit();
try idx.build();           // Build the index (O(n), SIMD-accelerated)

idx.len()                  // Character count - O(1)
idx.byteOffset(char_idx)   // Byte offset for character - O(1)
idx.charLen(char_idx)      // Character byte length - O(1)
idx.charAt(char_idx)       // Unicode codepoint - O(1)
idx.charBytes(char_idx)    // Byte slice for character - O(1)
idx.slice(start, end)      // Byte slice for range - O(1)

Utf8Index.countChars(src)  // Fast count without index - O(n)
```

## Implementation Notes

- Uses 32-byte SIMD vectors for ASCII detection
- Processes ASCII runs in batches of 8 offsets using vector writes
- Falls back to scalar for multibyte sequences
- UTF-8 lead byte pattern: `0xxxxxxx`=1, `110xxxxx`=2, `1110xxxx`=3, `11110xxx`=4
- Supports files up to 4GB (u32 offsets)

## Key Files to Understand

1. **src/utf8_index.zig** - The core `Utf8Index` struct with SIMD logic
2. **src/main.zig** - CLI argument parsing and output formatting
3. **build.zig** - Build configuration with custom install path (`bin/`)
