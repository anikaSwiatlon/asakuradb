const std = @import("std");
const memtable = @import("Memtable.zig");
const compareKeys = @import("compareKeys.zig");

const MAX_LEVEL = 16; // 2 ^ 16 entries

const Node = struct {
    key: []const u8,
    cell: memtable.Cell,

    // Maybe node pointer maybe null
    // i.e. slice of optional pointer to a Node
    forward: []?*Node,
};

const SkipList = struct {
    allocator: std.mem.Allocator,
    head: *Node,
    level: usize,
    rng: std.Random.DefaultPrng,

    fn init(allocator: std.mem.Allocator, seed: u64) !SkipList {
        const head = try allocator.create(Node);
        const forward = try allocator.alloc(?*Node, MAX_LEVEL);
        @memset(forward, null);

        head.* = .{ .key = "", .cell = undefined, .forward = forward };

        return .{
            .allocator = allocator,
            .head = head,
            .level = 1,
            .rng = std.Random.DefaultPrng.init(seed),
        };
    }

    fn deinit(self: *SkipList) void {
        var node = self.head.forward[0];
        while (node) |n| {
            const next = n.forward[0];
            self.allocator.free(n.forward);
            self.allocator.free(n.key);
            self.allocator.free(n.cell.data);
            self.allocator.destroy(n);
            node = next;
        }

        self.allocator.free(self.head.forward);
        self.allocator.destroy(self.head);
    }

    fn randomHeight(self: *SkipList) usize {
        var h: usize = 1;
        while (h < MAX_LEVEL and self.rng.random().boolean()) : (h += 1) {}
        return h;
    }

    /// Recording a predecessor at each level. If the key exist at level 0
    /// this means overwrite. If not creates new node, picks a height
    /// and grows the level if needed
    fn insert(self: *SkipList, key: []const u8, cell: memtable.Cell) !void {
        var update: [MAX_LEVEL]?*Node = .{null} ** MAX_LEVEL;
        var x: *Node = self.head;

        // TODO: Refactor to lower level functions

        // RECORDING
        var i: usize = self.level;
        while (i > 0) {
            i -= 1;
            while (x.forward[i]) |next| {
                if (compareKeys.compareKeys(next.key, key) == .lt) {
                    x = next;
                } else break;
            }
            update[i] = x;
        }

        // OVERWRITE CHECK
        if (x.forward[0]) |next| {
            if (compareKeys.compareKeys((next.key), key) == .eq) {
                if (cell.timestamp < next.cell.timestamp) {
                    self.allocator.free(cell.data);
                    return;
                }
                self.allocator.free(next.cell.data);
                next.cell = cell;
                return;
            }
        }

        // NEW NODE CREATION
        const height = self.randomHeight();
        if (height > self.level) {
            var j = self.level;
            while (j < height) : (j += 1) update[j] = self.head;
            self.level = height;
        }

        const node = try self.allocator.create(Node);
        node.forward = try self.allocator.alloc(?*Node, height);
        node.key = try self.allocator.dupe(u8, key);
        node.cell = cell;

        // INSERT INTO EACH LINE UP TO HEIGHT

        var k: usize = 0;
        while (k < height) : (k += 1) {
            const pred = update[k].?;
            node.forward[k] = pred.forward[k];
            pred.forward[k] = node;
        }
    }

    fn get(self: *SkipList, key: []const u8) ?[]const u8 {
        var x: *Node = self.head;
        var i: usize = self.level;

        while (i > 0) {
            i -= 1;
            while (x.forward[i]) |next| {
                if (compareKeys.compareKeys(next.key, key) == .lt) x = next else break;
            }
        }

        if (x.forward[0]) |candidate| {
            if (compareKeys.compareKeys(candidate.key, key) == .eq) {
                if (candidate.cell.kind == .tombstone) return null;
                return candidate.cell.data;
            }
        }
        return null;
    }

    const Cursor = struct {
        node: ?*Node,
        fn next(self: *Cursor) ?*Node {
            const n = self.node orelse return null;
            self.node = n.forward[0];
            return n;
        }
    };

    fn scanFrom(self: *SkipList, start: []const u8) Cursor {
        var x: *Node = self.head;
        var i: usize = self.level;
        while (i > 0) {
            i -= 1;
            while (x.forward[i]) |next| {
                if (compareKeys.compareKeys(next.key, start) == .lt) x = next else break;
            }
        }
        return .{ .node = x.forward[0] };
    }
};

test "skip list height allocator" {
    const a = std.testing.allocator;
    var s1 = try SkipList.init(a, 0xCAFE);
    defer s1.deinit();

    try std.testing.expect(s1.level == 1);
}

test "skip list insert keeps sorted order" {
    const a = std.testing.allocator;
    var s1 = try SkipList.init(a, 1);
    defer s1.deinit();

    const c = memtable.Cell{ .kind = .put, .timestamp = 1, .data = "" };

    try s1.insert("m", c);
    try s1.insert("a", c);
    try s1.insert("z", c);
    try s1.insert("d", c);

    // test level 0

    var node = s1.head.forward[0];
    var prev: []const u8 = "";
    while (node) |n| {
        try std.testing.expect(compareKeys.compareKeys(prev, n.key) == .lt);
        prev = n.key;
        node = n.forward[0];
    }
}

test "search and range scan" {
    const a = std.testing.allocator;
    var sl = try SkipList.init(a, 21);
    defer sl.deinit();

    for ([_][]const u8{ "a", "b", "c", "d", "e" }) |k| {
        const data = try a.dupe(u8, "x");
        const c = memtable.Cell{ .kind = .put, .timestamp = 1, .data = data };
        try sl.insert(k, c);
    }

    try std.testing.expectEqualStrings("x", sl.get("c").?);
    try std.testing.expect(sl.get("zzz") == null);

    var cur = sl.scanFrom("c");
    var seen: std.ArrayListUnmanaged(u8) = .empty;
    defer seen.deinit(a);

    while (cur.next()) |n| try seen.append(a, n.key[0]);
    try std.testing.expectEqualStrings("cde", seen.items);
}
