const std = @import("std");
const memtable = @import("Memtable.zig");

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
};

test SkipList {
    const a = std.testing.allocator;
    var s1 = try SkipList.init(a, 0xCAFE);
    defer s1.deinit();

    try std.testing.expect(s1.level == 1);
}
