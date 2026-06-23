const std = @import("std");

// Cassandra uses only soft delete marking deleted value as tombstone
const ValueKind = enum { put, tombstone };

const Memtable = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) Memtable {
        return .{
            .map = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    // * marks a pointer to an instance

    fn deinit(self: *Memtable) void {
        // Free every key and value we own

        var it = self.map.iterator();

        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    // Copy key and value into own memory so callers can reuse their buffers

    fn put(self: *Memtable, key: []const u8, value: []const u8) !void {
        const owned_val = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_val);

        const gop = try self.map.getOrPut(key);

        if (gop.found_existing) {

            // Overwrite: free old value, keep the key
            self.allocator.free(gop.value_ptr.*);
        } else {
            // New entry: own the key
            gop.key_ptr.* = try self.allocator.dupe(u8, key);
        }
        gop.value_ptr.* = owned_val;
    }

    fn get(self: *Memtable, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }
};

test Memtable {

    // std testing allocator fails if memory leaks
    const a = std.testing.allocator;
    var mt = Memtable.init(a);
    defer mt.deinit();

    try mt.put("name", "asakura");
    try std.testing.expectEqualStrings("asakura", mt.get("name").?);

    try mt.put("name", "sakura");
    try std.testing.expectEqualStrings("sakura", mt.get("name").?);

    try std.testing.expect(mt.get("missing") == null);
}
