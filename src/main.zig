const std = @import("std");
const Utf8Index = @import("utf8_index").Utf8Index;

const Options = struct {
    show_all: bool = false,
    limit: ?usize = null,
    multibyte_only: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup stdout with new I/O pattern (Zig 0.15.x)
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout: *std.Io.Writer = &stdout_writer.interface;

    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr: *std.Io.Writer = &stderr_writer.interface;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage(stderr);
        try stderr.flush();
        std.process.exit(1);
    }

    // Parse options
    var opts = Options{};
    var positional = std.ArrayListUnmanaged([]const u8){};
    defer positional.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--all")) {
            opts.show_all = true;
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--multibyte")) {
            opts.multibyte_only = true;
        } else if (std.mem.eql(u8, arg, "-n")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: -n requires a number\n", .{});
                try stderr.flush();
                std.process.exit(1);
            }
            opts.limit = std.fmt.parseInt(usize, args[i], 10) catch {
                try stderr.print("Error: invalid number '{s}'\n", .{args[i]});
                try stderr.flush();
                std.process.exit(1);
            };
        } else if (arg.len > 0 and arg[0] == '-' and !std.mem.eql(u8, arg, "-h") and !std.mem.eql(u8, arg, "--help")) {
            try stderr.print("Unknown option: {s}\n", .{arg});
            try stderr.flush();
            std.process.exit(1);
        } else {
            try positional.append(allocator, arg);
        }
    }

    if (positional.items.len < 1) {
        try printUsage(stderr);
        try stderr.flush();
        std.process.exit(1);
    }

    const command = positional.items[0];

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "analyze")) {
        if (positional.items.len < 2) {
            try stderr.print("Error: 'analyze' requires a string argument\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        try analyzeString(stdout, allocator, positional.items[1], opts);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "count")) {
        if (positional.items.len < 2) {
            try stderr.print("Error: 'count' requires a string argument\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        try countString(stdout, allocator, positional.items[1]);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "char")) {
        if (positional.items.len < 3) {
            try stderr.print("Error: 'char' requires a string and index argument\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        const index = std.fmt.parseInt(usize, positional.items[2], 10) catch {
            try stderr.print("Error: invalid index '{s}'\n", .{positional.items[2]});
            try stderr.flush();
            std.process.exit(1);
        };
        try charAtIndex(stdout, allocator, positional.items[1], index);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "slice")) {
        if (positional.items.len < 4) {
            try stderr.print("Error: 'slice' requires string, start, and end arguments\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        const start = std.fmt.parseInt(usize, positional.items[2], 10) catch {
            try stderr.print("Error: invalid start index '{s}'\n", .{positional.items[2]});
            try stderr.flush();
            std.process.exit(1);
        };
        const end = std.fmt.parseInt(usize, positional.items[3], 10) catch {
            try stderr.print("Error: invalid end index '{s}'\n", .{positional.items[3]});
            try stderr.flush();
            std.process.exit(1);
        };
        try sliceString(stdout, allocator, positional.items[1], start, end);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "file")) {
        if (positional.items.len < 2) {
            try stderr.print("Error: 'file' requires a filename argument\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        try analyzeFile(stdout, allocator, positional.items[1], opts);
        try stdout.flush();
        return;
    }

    try stderr.print("Unknown command: {s}\n", .{command});
    try printUsage(stderr);
    try stderr.flush();
    std.process.exit(1);
}

fn printUsage(w: *std.Io.Writer) !void {
    try w.print(
        \\UTF-8 Index Tool
        \\
        \\A SIMD-accelerated UTF-8 character indexer that maps character positions
        \\to byte offsets for O(1) lookups.
        \\
        \\USAGE:
        \\    utf8-index [options] <command> [arguments]
        \\
        \\COMMANDS:
        \\    analyze <string>              Analyze a UTF-8 string, showing character positions
        \\    count <string>                Count characters in a UTF-8 string
        \\    char <string> <index>         Get character at index (0-based)
        \\    slice <string> <start> <end>  Get character slice [start..end)
        \\    file <filename>               Analyze a UTF-8 file
        \\    help                          Show this help message
        \\
        \\OPTIONS:
        \\    -a, --all        Show all characters (default: first 20 for files)
        \\    -n <N>           Limit output to N characters
        \\    -m, --multibyte  Show only multibyte (non-ASCII) characters
        \\
        \\EXAMPLES:
        \\    utf8-index analyze "Hello世界"
        \\    utf8-index count "Hello, 世界! 🎉"
        \\    utf8-index char "a世b🎉c" 3
        \\    utf8-index slice "Hello世界!" 5 7
        \\    utf8-index file input.txt
        \\    utf8-index -a file input.txt           # Show all characters
        \\    utf8-index -n 50 file input.txt        # Show first 50 characters
        \\    utf8-index -m file input.txt           # Show only multibyte chars
        \\
    , .{});
}

fn printCharacterTable(w: *std.Io.Writer, idx: *const Utf8Index, opts: Options) !void {
    const total = idx.len();
    var shown: usize = 0;
    var multibyte_count: usize = 0;

    // Determine effective limit
    const limit: usize = if (opts.show_all)
        total
    else if (opts.limit) |l|
        l
    else
        total; // For analyze command, default to all

    // Table header (Char at end to avoid variable-width alignment issues)
    try w.print("{s:>5}  {s:>6}  {s:>4}  {s:<8}  {s:<14}{s}\n", .{ "Idx", "Offset", "Len", "Unicode", "Bytes", "Char" });
    try w.print("{s}\n", .{"-" ** 55});

    for (0..total) |i| {
        const clen = idx.charLen(i).?;

        // Skip ASCII if multibyte-only mode
        if (opts.multibyte_only and clen == 1) {
            continue;
        }

        if (clen > 1) multibyte_count += 1;

        if (shown >= limit) continue; // Still count but don't print

        const offset = idx.byteOffset(i).?;
        const char = idx.charAt(i);
        const bytes = idx.charBytes(i).?;

        // Print character (handle control chars)
        var char_display: [8]u8 = undefined;
        var char_len: usize = 0;
        if (char) |c| {
            if (c < 0x20) {
                // Control characters
                const names = [_][]const u8{
                    "NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL",
                    "BS",  "TAB", "LF",  "VT",  "FF",  "CR",  "SO",  "SI",
                    "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB",
                    "CAN", "EM",  "SUB", "ESC", "FS",  "GS",  "RS",  "US",
                };
                const name = names[c];
                @memcpy(char_display[0..name.len], name);
                char_len = name.len;
            } else if (c == 0x7F) {
                @memcpy(char_display[0..3], "DEL");
                char_len = 3;
            } else {
                char_len = std.unicode.utf8Encode(c, &char_display) catch 0;
            }
        }

        // Unicode codepoint
        var unicode_str: [10]u8 = undefined;
        var unicode_len: usize = 0;
        if (char) |c| {
            unicode_len = (std.fmt.bufPrint(&unicode_str, "U+{X:0>4}", .{c}) catch &[_]u8{}).len;
        }

        try w.print("{d:>5}  {d:>6}  {d:>4}  {s:<8}  ", .{
            i,
            offset,
            clen,
            unicode_str[0..unicode_len],
        });

        // Print hex bytes (fixed width: 4 bytes max = 12 chars)
        var hex_written: usize = 0;
        for (bytes) |b| {
            try w.print("{x:0>2} ", .{b});
            hex_written += 3;
        }
        // Pad to 12 chars for alignment
        while (hex_written < 12) : (hex_written += 1) {
            try w.print(" ", .{});
        }

        // Character at end (variable width doesn't affect alignment)
        try w.print("  {s}\n", .{char_display[0..char_len]});
        shown += 1;
    }

    // Summary
    if (opts.multibyte_only) {
        if (shown < multibyte_count) {
            try w.print("... ({d} more multibyte characters)\n", .{multibyte_count - shown});
        }
    } else if (shown < total) {
        try w.print("... ({d} more characters)\n", .{total - shown});
    }
}

fn analyzeString(w: *std.Io.Writer, allocator: std.mem.Allocator, input: []const u8, opts: Options) !void {
    var idx = Utf8Index.init(allocator, input);
    defer idx.deinit();
    try idx.build();

    // Count multibyte characters
    var multibyte: usize = 0;
    for (0..idx.len()) |i| {
        if (idx.charLen(i).? > 1) multibyte += 1;
    }

    try w.print("Input: \"{s}\"\n", .{input});
    try w.print("Bytes: {d}\n", .{input.len});
    try w.print("Characters: {d}", .{idx.len()});
    if (multibyte > 0) {
        try w.print(" ({d} ASCII, {d} multibyte)\n", .{ idx.len() - multibyte, multibyte });
    } else {
        try w.print(" (all ASCII)\n", .{});
    }
    try w.print("\n", .{});

    try printCharacterTable(w, &idx, opts);
}

fn countString(w: *std.Io.Writer, allocator: std.mem.Allocator, input: []const u8) !void {
    var idx = Utf8Index.init(allocator, input);
    defer idx.deinit();
    try idx.build();

    // Count by byte length
    var ascii: usize = 0;
    var two_byte: usize = 0;
    var three_byte: usize = 0;
    var four_byte: usize = 0;

    for (0..idx.len()) |i| {
        switch (idx.charLen(i).?) {
            1 => ascii += 1,
            2 => two_byte += 1,
            3 => three_byte += 1,
            4 => four_byte += 1,
            else => {},
        }
    }

    try w.print("Bytes: {d}\n", .{input.len});
    try w.print("Characters: {d}\n", .{idx.len()});
    try w.print("\n", .{});
    try w.print("Breakdown:\n", .{});
    try w.print("  ASCII (1-byte):   {d:>6}\n", .{ascii});
    if (two_byte > 0) try w.print("  2-byte:           {d:>6}\n", .{two_byte});
    if (three_byte > 0) try w.print("  3-byte:           {d:>6}\n", .{three_byte});
    if (four_byte > 0) try w.print("  4-byte:           {d:>6}\n", .{four_byte});
}

fn charAtIndex(w: *std.Io.Writer, allocator: std.mem.Allocator, input: []const u8, index: usize) !void {
    var idx = Utf8Index.init(allocator, input);
    defer idx.deinit();
    try idx.build();

    if (idx.charAt(index)) |char| {
        const offset = idx.byteOffset(index).?;
        const clen = idx.charLen(index).?;
        const bytes = idx.charBytes(index).?;

        var buf: [4]u8 = undefined;
        const char_str_len = std.unicode.utf8Encode(char, &buf) catch 0;

        try w.print("Index: {d}\n", .{index});
        try w.print("Character: {s}\n", .{buf[0..char_str_len]});
        try w.print("Codepoint: U+{X:0>4}\n", .{char});
        try w.print("Byte offset: {d}\n", .{offset});
        try w.print("Byte length: {d}\n", .{clen});
        try w.print("Bytes: ", .{});
        for (bytes) |b| {
            try w.print("{x:0>2} ", .{b});
        }
        try w.print("\n", .{});
    } else {
        try w.print("Error: index {d} out of range (string has {d} characters)\n", .{ index, idx.len() });
    }
}

fn sliceString(w: *std.Io.Writer, allocator: std.mem.Allocator, input: []const u8, start: usize, end: usize) !void {
    var idx = Utf8Index.init(allocator, input);
    defer idx.deinit();
    try idx.build();

    if (idx.slice(start, end)) |s| {
        try w.print("Slice [{d}..{d}): \"{s}\"\n", .{ start, end, s });
        try w.print("Characters: {d}\n", .{end - start});
        try w.print("Bytes: {d}\n", .{s.len});
    } else {
        try w.print("Error: invalid slice range [{d}..{d}) for string with {d} characters\n", .{ start, end, idx.len() });
    }
}

fn analyzeFile(w: *std.Io.Writer, allocator: std.mem.Allocator, filename: []const u8, opts: Options) !void {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        try w.print("Error opening file '{s}': {any}\n", .{ filename, err });
        return;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024 * 100) catch |err| { // 100MB max
        try w.print("Error reading file: {any}\n", .{err});
        return;
    };
    defer allocator.free(content);

    var idx = Utf8Index.init(allocator, content);
    defer idx.deinit();
    try idx.build();

    // Count multibyte characters
    var multibyte: usize = 0;
    for (0..idx.len()) |i| {
        if (idx.charLen(i).? > 1) multibyte += 1;
    }

    try w.print("File: {s}\n", .{filename});
    try w.print("Bytes: {d}\n", .{content.len});
    try w.print("Characters: {d}", .{idx.len()});
    if (multibyte > 0) {
        try w.print(" ({d} ASCII, {d} multibyte)\n", .{ idx.len() - multibyte, multibyte });
    } else {
        try w.print(" (all ASCII)\n", .{});
    }

    if (idx.len() == 0) return;

    // Adjust opts for file command - default to 20 unless specified
    var file_opts = opts;
    if (!opts.show_all and opts.limit == null) {
        file_opts.limit = 20;
    }

    const effective_limit = if (file_opts.show_all) idx.len() else (file_opts.limit orelse 20);
    const showing = if (opts.multibyte_only) "multibyte characters" else "characters";

    if (file_opts.show_all) {
        try w.print("\nAll {s}:\n", .{showing});
    } else if (effective_limit < idx.len()) {
        try w.print("\nFirst {d} {s}:\n", .{ effective_limit, showing });
    } else {
        try w.print("\nAll {s}:\n", .{showing});
    }

    try printCharacterTable(w, &idx, file_opts);
}
