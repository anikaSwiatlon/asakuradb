const std = @import("std");

// Cassandra uses only soft delete marking deleted value as tombstone
const ValueKind = enum { put, tombstone };

const Cell = struct {
    kind: ValueKind,
    timestamp: u64, // higher = newer; newest is the one read
    data: []const u8, // Empty for a tombstone
};

const Memtable = struct {
    map: std.StringHashMap(Cell),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) Memtable {
        return .{
            .map = std.StringHashMap(Cell).init(allocator),
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

    fn put(self: *Memtable, key: []const u8, value: []const u8, ts: u64) !void {
        const owned_val = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_val);

        try self.upsert(key, .{ .kind = .put, .timestamp = ts, .data = owned_val });
    }

    fn get(self: *Memtable, key: []const u8) ?[]const u8 {
        const cell = self.map.get(key) orelse return null;

        // return no data for tombstone <- data deleted
        if (cell.kind == .tombstone) return null;

        // return data when no tomstoned
        return cell.data;
    }

    // self contained part from put

    fn upsert(self: *Memtable, key: []const u8, cell: Cell) !void {
        const gop = try self.map.getOrPut(key);

        if (gop.found_existing) {

            // only overwrite if newer <- last write wins

            if (cell.timestamp < gop.value_ptr.timestamp) {

                // Drop stale data
                self.allocator.free(cell.data);
                return;
            }

            self.allocator.free(gop.value_ptr.data);
        } else {

            // if no value tor gop
            gop.key_ptr.* = try self.allocator.dupe(u8, key);
        }

        gop.value_ptr.* = cell;
    }

    fn delete(self: *Memtable, key: []const u8, ts: u64) !void {

        // Put of an empty cell

        const owned_val = try self.allocator.dupe(u8, "");

        errdefer self.allocator.free(owned_val);
        try self.upsert(key, .{ .kind = .tombstone, .timestamp = ts, .data = owned_val });
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
