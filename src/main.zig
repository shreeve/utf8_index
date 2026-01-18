const std = @import("std");
const Utf8Index = @import("utf8_index").Utf8Index;

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

    const command = args[1];

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "analyze")) {
        if (args.len < 3) {
            try stderr.print("Error: 'analyze' requires a string argument\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        try analyzeString(stdout, allocator, args[2]);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "count")) {
        if (args.len < 3) {
            try stderr.print("Error: 'count' requires a string argument\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        try countString(stdout, args[2]);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "char")) {
        if (args.len < 4) {
            try stderr.print("Error: 'char' requires a string and index argument\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        const index = std.fmt.parseInt(usize, args[3], 10) catch {
            try stderr.print("Error: invalid index '{s}'\n", .{args[3]});
            try stderr.flush();
            std.process.exit(1);
        };
        try charAtIndex(stdout, allocator, args[2], index);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "slice")) {
        if (args.len < 5) {
            try stderr.print("Error: 'slice' requires string, start, and end arguments\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        const start = std.fmt.parseInt(usize, args[3], 10) catch {
            try stderr.print("Error: invalid start index '{s}'\n", .{args[3]});
            try stderr.flush();
            std.process.exit(1);
        };
        const end = std.fmt.parseInt(usize, args[4], 10) catch {
            try stderr.print("Error: invalid end index '{s}'\n", .{args[4]});
            try stderr.flush();
            std.process.exit(1);
        };
        try sliceString(stdout, allocator, args[2], start, end);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, command, "file")) {
        if (args.len < 3) {
            try stderr.print("Error: 'file' requires a filename argument\n", .{});
            try stderr.flush();
            std.process.exit(1);
        }
        try analyzeFile(stdout, allocator, args[2]);
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
        \\    utf8-index <command> [arguments]
        \\
        \\COMMANDS:
        \\    analyze <string>              Analyze a UTF-8 string, showing all character positions
        \\    count <string>                Count characters in a UTF-8 string
        \\    char <string> <index>         Get character at index (0-based)
        \\    slice <string> <start> <end>  Get character slice [start..end)
        \\    file <filename>               Analyze a UTF-8 file
        \\    help                          Show this help message
        \\
        \\EXAMPLES:
        \\    utf8-index analyze "Hello世界"
        \\    utf8-index count "Hello, 世界! 🎉"
        \\    utf8-index char "a世b🎉c" 3
        \\    utf8-index slice "Hello世界!" 5 7
        \\    utf8-index file input.txt
        \\
    , .{});
}

fn analyzeString(w: *std.Io.Writer, allocator: std.mem.Allocator, input: []const u8) !void {
    var idx = Utf8Index.init(allocator, input);
    defer idx.deinit();
    try idx.build();

    try w.print("Input: \"{s}\"\n", .{input});
    try w.print("Bytes: {d}\n", .{input.len});
    try w.print("Characters: {d}\n", .{idx.len()});
    try w.print("\n", .{});

    // Table header
    try w.print("{s:>5}  {s:>6}  {s:>4}  {s:<6}  {s}\n", .{ "Idx", "Offset", "Len", "Char", "Bytes (hex)" });
    try w.print("{s}\n", .{"-" ** 50});

    for (0..idx.len()) |i| {
        const offset = idx.byteOffset(i).?;
        const clen = idx.charLen(i).?;
        const char = idx.charAt(i);
        const bytes = idx.charBytes(i).?;

        // Print character (handle control chars)
        var char_display: [8]u8 = undefined;
        var char_len: usize = 0;
        if (char) |c| {
            if (c < 0x20 or c == 0x7F) {
                char_display[0] = '\\';
                char_display[1] = 'x';
                const hex = "0123456789abcdef";
                char_display[2] = hex[(c >> 4) & 0xF];
                char_display[3] = hex[c & 0xF];
                char_len = 4;
            } else {
                char_len = std.unicode.utf8Encode(c, &char_display) catch 0;
            }
        }

        try w.print("{d:>5}  {d:>6}  {d:>4}  {s:<6}", .{
            i,
            offset,
            clen,
            char_display[0..char_len],
        });

        // Print hex bytes
        try w.print("  ", .{});
        for (bytes) |b| {
            try w.print("{x:0>2} ", .{b});
        }
        try w.print("\n", .{});
    }
}

fn countString(w: *std.Io.Writer, input: []const u8) !void {
    const count = Utf8Index.countChars(input);
    try w.print("Bytes: {d}\n", .{input.len});
    try w.print("Characters: {d}\n", .{count});
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

fn analyzeFile(w: *std.Io.Writer, allocator: std.mem.Allocator, filename: []const u8) !void {
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

    try w.print("File: {s}\n", .{filename});
    try w.print("Bytes: {d}\n", .{content.len});
    try w.print("Characters: {d}\n", .{idx.len()});

    // Show first 20 characters as a preview
    const preview_len = @min(idx.len(), 20);
    if (preview_len > 0) {
        try w.print("\nFirst {d} characters:\n", .{preview_len});
        try w.print("{s:>5}  {s:>6}  {s:>4}  {s:<6}  {s}\n", .{ "Idx", "Offset", "Len", "Char", "Bytes (hex)" });
        try w.print("{s}\n", .{"-" ** 50});

        for (0..preview_len) |i| {
            const offset = idx.byteOffset(i).?;
            const clen = idx.charLen(i).?;
            const char = idx.charAt(i);
            const bytes = idx.charBytes(i).?;

            var char_display: [8]u8 = undefined;
            var char_len: usize = 0;
            if (char) |c| {
                if (c < 0x20 or c == 0x7F) {
                    char_display[0] = '\\';
                    char_display[1] = 'x';
                    const hex = "0123456789abcdef";
                    char_display[2] = hex[(c >> 4) & 0xF];
                    char_display[3] = hex[c & 0xF];
                    char_len = 4;
                } else {
                    char_len = std.unicode.utf8Encode(c, &char_display) catch 0;
                }
            }

            try w.print("{d:>5}  {d:>6}  {d:>4}  {s:<6}", .{
                i,
                offset,
                clen,
                char_display[0..char_len],
            });

            try w.print("  ", .{});
            for (bytes) |b| {
                try w.print("{x:0>2} ", .{b});
            }
            try w.print("\n", .{});
        }

        if (idx.len() > 20) {
            try w.print("... ({d} more characters)\n", .{idx.len() - 20});
        }
    }
}
