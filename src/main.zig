const std = @import("std");

/// error union return type function - allows using 'try' inside it
pub fn main() !void {
    // Set up debug allocator
    var debug_allocator = std.heap.DebugAllocator(.{}){};

    defer {
        const leaked = debug_allocator.deinit();
        if (leaked == .leak) std.debug.print("MEMORY LEAKED!\n", .{});
    }

    const allocator = debug_allocator.allocator();

    // Allocate a buffer of 16 bytes

    const buf = try allocator.alloc(u8, 16);

    defer allocator.free(buf);

    @memset(buf, 0);

    buf[0] = 42;
    std.debug.print("first byte = {d}\n", .{buf[0]});
}
