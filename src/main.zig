const std = @import("std");

/// Defining own error set
const DbError = error{
    KeyNotFount,
    Corrupted,
};

fn lookup(key: []const u8) DbError!u64 {
    if (key.len == 0) return DbError.KeyNotFount;
    if (key[0] == '!') return DbError.Corrupted;

    return 1234; // happy path
}

pub fn main() void {
    const v1 = lookup("!bad") catch |err| {
        std.debug.print("lookup failed, error: {s}\n", .{@errorName(err)});
        return;
    };
    std.debug.print("got {d}\n", .{v1});

    // catch can supply default value
    const v2 = lookup("") catch 0;

    std.debug.print("got {d}\n", .{v2});
}
