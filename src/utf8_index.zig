const std = @import("std");

/// Ultra-optimized UTF-8 character index.
/// Maps character position → byte offset using pure 32-bit offsets.
/// No bit packing — length derived from offset differences or byte inspection.
///
/// Supports files up to 4GB (full u32 range).
pub const Utf8Index = struct {
    source: []const u8,
    offsets: std.ArrayListUnmanaged(u32),
    allocator: std.mem.Allocator,

    const Self = @This();

    // SIMD configuration
    const SIMD_WIDTH = 32;
    const Vec32u8 = @Vector(SIMD_WIDTH, u8);
    const Vec8u32 = @Vector(8, u32);

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
        return .{ .source = source, .offsets = .{}, .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.offsets.deinit(self.allocator);
    }

    // =========================================================================
    // Build index
    // =========================================================================

    /// Build complete index with SIMD acceleration
    pub fn build(self: *Self) !void {
        self.offsets.clearRetainingCapacity();

        var byte_pos: u32 = 0;
        const source_len: u32 = @intCast(self.source.len);

        while (byte_pos < source_len) {
            const remaining = source_len - byte_pos;

            // SIMD path: check 32 bytes at once
            if (remaining >= SIMD_WIDTH) {
                const chunk: Vec32u8 = self.source[byte_pos..][0..SIMD_WIDTH].*;

                if (isAllAscii(chunk)) {
                    try self.appendAsciiRun(byte_pos, SIMD_WIDTH);
                    byte_pos += SIMD_WIDTH;
                    continue;
                }
            }

            // Scalar path: one character at a time
            try self.offsets.append(self.allocator, byte_pos);
            byte_pos += utf8Len(self.source[byte_pos]);
        }
    }

    /// SIMD check: all bytes < 0x80?
    inline fn isAllAscii(chunk: Vec32u8) bool {
        return @reduce(.Or, chunk & @as(Vec32u8, @splat(0x80))) == 0;
    }

    /// UTF-8 lead byte → sequence length
    pub inline fn utf8Len(b: u8) u32 {
        if (b < 0x80) return 1;
        if (b < 0xE0) return 2;
        if (b < 0xF0) return 3;
        return 4;
    }

    /// SIMD write: append consecutive offsets for ASCII run
    fn appendAsciiRun(self: *Self, base: u32, count: u32) !void {
        const old_len = self.offsets.items.len;
        try self.offsets.resize(self.allocator, old_len + count);
        const items = self.offsets.items[old_len..];

        var i: u32 = 0;

        // SIMD: write 8 consecutive u32s at a time
        while (i + 8 <= count) : (i += 8) {
            const b = base + i;
            items[i..][0..8].* = Vec8u32{ b, b + 1, b + 2, b + 3, b + 4, b + 5, b + 6, b + 7 };
        }

        // Scalar tail
        while (i < count) : (i += 1) {
            items[i] = base + i;
        }
    }

    // =========================================================================
    // Lookup
    // =========================================================================

    /// Character count
    pub inline fn len(self: *const Self) usize {
        return self.offsets.items.len;
    }

    /// Byte offset for character index — O(1)
    pub inline fn byteOffset(self: *const Self, char_idx: usize) ?u32 {
        return if (char_idx < self.offsets.items.len) self.offsets.items[char_idx] else null;
    }

    /// Character length in bytes — O(1)
    pub inline fn charLen(self: *const Self, char_idx: usize) ?u32 {
        if (char_idx >= self.offsets.items.len) return null;
        if (char_idx + 1 < self.offsets.items.len) {
            return self.offsets.items[char_idx + 1] - self.offsets.items[char_idx];
        }
        // Last char: compute from source
        return utf8Len(self.source[self.offsets.items[char_idx]]);
    }

    /// Get character at index — O(1)
    pub fn charAt(self: *const Self, char_idx: usize) ?u21 {
        const offset = self.byteOffset(char_idx) orelse return null;
        const clen = self.charLen(char_idx) orelse return null;
        return std.unicode.utf8Decode(self.source[offset..][0..clen]) catch null;
    }

    /// Slice of characters [start..end] as bytes
    pub fn slice(self: *const Self, start: usize, end: usize) ?[]const u8 {
        if (start > end or end > self.offsets.items.len) return null;
        const start_byte = self.offsets.items[start];
        const end_byte = if (end < self.offsets.items.len)
            self.offsets.items[end]
        else
            @as(u32, @intCast(self.source.len));
        return self.source[start_byte..end_byte];
    }

    /// Get byte slice for a single character at index
    pub fn charBytes(self: *const Self, char_idx: usize) ?[]const u8 {
        const offset = self.byteOffset(char_idx) orelse return null;
        const clen = self.charLen(char_idx) orelse return null;
        return self.source[offset..][0..clen];
    }

    // =========================================================================
    // Utility
    // =========================================================================

    /// Fast character count without building index (SIMD)
    pub fn countChars(source: []const u8) usize {
        var count: usize = 0;
        var i: usize = 0;

        while (i + SIMD_WIDTH <= source.len) : (i += SIMD_WIDTH) {
            const chunk: Vec32u8 = source[i..][0..SIMD_WIDTH].*;
            // Count bytes that are NOT continuation bytes (10xxxxxx)
            const not_cont = (chunk & @as(Vec32u8, @splat(0xC0))) != @as(Vec32u8, @splat(0x80));
            count += @popCount(@as(u32, @bitCast(not_cont)));
        }

        while (i < source.len) : (i += 1) {
            if (source[i] & 0xC0 != 0x80) count += 1;
        }

        return count;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "ascii" {
    var idx = Utf8Index.init(std.testing.allocator, "Hello");
    defer idx.deinit();
    try idx.build();

    try std.testing.expectEqual(@as(usize, 5), idx.len());
    try std.testing.expectEqual(@as(?u32, 0), idx.byteOffset(0));
    try std.testing.expectEqual(@as(?u32, 4), idx.byteOffset(4));
    try std.testing.expectEqual(@as(?u21, 'H'), idx.charAt(0));
    try std.testing.expectEqual(@as(?u21, 'o'), idx.charAt(4));
}

test "multibyte" {
    var idx = Utf8Index.init(std.testing.allocator, "a世b🎉c");
    defer idx.deinit();
    try idx.build();

    // a(1) + 世(3) + b(1) + 🎉(4) + c(1) = 10 bytes, 5 chars
    try std.testing.expectEqual(@as(usize, 5), idx.len());

    try std.testing.expectEqual(@as(?u32, 0), idx.byteOffset(0)); // a
    try std.testing.expectEqual(@as(?u32, 1), idx.byteOffset(1)); // 世
    try std.testing.expectEqual(@as(?u32, 4), idx.byteOffset(2)); // b
    try std.testing.expectEqual(@as(?u32, 5), idx.byteOffset(3)); // 🎉
    try std.testing.expectEqual(@as(?u32, 9), idx.byteOffset(4)); // c

    try std.testing.expectEqual(@as(?u32, 1), idx.charLen(0)); // a
    try std.testing.expectEqual(@as(?u32, 3), idx.charLen(1)); // 世
    try std.testing.expectEqual(@as(?u32, 4), idx.charLen(3)); // 🎉

    try std.testing.expectEqual(@as(?u21, 'a'), idx.charAt(0));
    try std.testing.expectEqual(@as(?u21, '世'), idx.charAt(1));
    try std.testing.expectEqual(@as(?u21, '🎉'), idx.charAt(3));
}

test "simd ascii run" {
    const text = "The quick brown fox jumps!" ** 20; // 520 chars
    var idx = Utf8Index.init(std.testing.allocator, text);
    defer idx.deinit();
    try idx.build();

    try std.testing.expectEqual(@as(usize, 520), idx.len());
    try std.testing.expectEqual(@as(?u32, 0), idx.byteOffset(0));
    try std.testing.expectEqual(@as(?u32, 519), idx.byteOffset(519));
}

test "slice" {
    var idx = Utf8Index.init(std.testing.allocator, "Hello世界!");
    defer idx.deinit();
    try idx.build();

    try std.testing.expectEqualStrings("Hello", idx.slice(0, 5).?);
    try std.testing.expectEqualStrings("世界", idx.slice(5, 7).?);
    try std.testing.expectEqualStrings("!", idx.slice(7, 8).?);
}

test "count chars fast" {
    const text = "Hello, 世界! 🎉" ** 100;
    const fast = Utf8Index.countChars(text);

    var idx = Utf8Index.init(std.testing.allocator, text);
    defer idx.deinit();
    try idx.build();

    try std.testing.expectEqual(idx.len(), fast);
}

test "empty" {
    var idx = Utf8Index.init(std.testing.allocator, "");
    defer idx.deinit();
    try idx.build();

    try std.testing.expectEqual(@as(usize, 0), idx.len());
    try std.testing.expectEqual(@as(?u32, null), idx.byteOffset(0));
    try std.testing.expectEqual(@as(?u21, null), idx.charAt(0));
}

test "bounds" {
    var idx = Utf8Index.init(std.testing.allocator, "abc");
    defer idx.deinit();
    try idx.build();

    try std.testing.expectEqual(@as(?u32, null), idx.byteOffset(3));
    try std.testing.expectEqual(@as(?u32, null), idx.byteOffset(100));
    try std.testing.expectEqual(@as(?u21, null), idx.charAt(3));
}
