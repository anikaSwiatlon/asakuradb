const std = @import("std");
const memtable = @import("Memtable.zig");
const compareKeys = @import("compareKeys.zig");

const Cell = memtable.Cell;
const ValueKind = memtable.ValueKind;

const Entry = struct { key: []const u8, cell: Cell };

// Caller owns then returned slice and must free it
// slice, not the underlying data

fn sortedEntries(
    allocator: std.mem.Allocator,
    map: *std.StringHashMap(Cell),
) ![]Entry {
    var list = try std.ArrayList(Entry).initCapacity(allocator, map.count());
    errdefer list.deinit(allocator);

    var it = map.iterator();
    while (it.next()) |entry| {
        list.appendAssumeCapacity(.{ .key = entry.key_ptr.*, .cell = entry.value_ptr.* });
    }

    const slice = try list.toOwnedSlice(allocator);
    std.sort.pdq(Entry, slice, {}, lessThan);
    return slice;
}

fn lessThan(_: void, a: Entry, b: Entry) bool {
    return compareKeys.compareKeys(a.key, b.key) == .lt;
}

test Entry {
    const a = std.testing.allocator;
    var map = std.StringHashMap(Cell).init(a);
    defer map.deinit();

    // (In real code these come from Memtable; inline here for the unit testing)
    try map.put("banana", .{ .kind = .put, .timestamp = 1, .data = "" });
    try map.put("apple", .{ .kind = .put, .timestamp = 1, .data = "" });
    try map.put("cherry", .{ .kind = .put, .timestamp = 1, .data = "" });

    const entries = try sortedEntries(a, &map);
    defer a.free(entries);

    try std.testing.expectEqualStrings("apple", entries[0].key);
    try std.testing.expectEqualStrings("banana", entries[1].key);
    try std.testing.expectEqualStrings("cherry", entries[2].key);
}
