const std = @import("std");
const expect = std.testing.expect;

const Order = enum { lt, eq, gt };

pub fn compareKeys(a: []const u8, b: []const u8) Order {
    const min_len = @min(a.len, b.len);
    var i: usize = 0;

    while (i < min_len) : (i += 1) {
        if (a[i] < b[i]) return .lt;
        if (a[i] > b[i]) return .gt;
    }

    if (a.len < b.len) return .lt;
    if (a.len > b.len) return .gt;
    return .eq;
}

test "key ordering" {
    try expect(compareKeys("apple", "banana") == .lt);
    try expect(compareKeys("apple", "apple") == .eq);
    try expect(compareKeys("apple", "app") == .gt);
    try expect(compareKeys("", "a") == .lt);
}
