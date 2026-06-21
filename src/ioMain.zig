const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const cwd = Io.Dir.cwd(); // read current directory

    // wirte

    {
        const file = try cwd.createFile(io, "scratch.bin", .{});
        defer file.close(io);

        // buffer writer stream
        var wbuf: [64]u8 = undefined;
        // create writer itself
        var fw = file.writer(io, &wbuf);

        const w = &fw.interface;

        const bytes = [_]u8{ 0xA5, 0x00, 0xFF, 0x42 };

        try w.writeAll(&bytes);
        try w.flush();
    }

    // read back

    {
        const file = try cwd.openFile(io, "scratch.bin", .{});
        defer file.close(io);

        var rbuf: [64]u8 = undefined;
        var fr = file.reader(io, &rbuf);
        const r = &fr.interface;

        var dst: [4]u8 = undefined;
        try r.readSliceAll(&dst);

        std.debug.print("read 4 bytes: ", .{});
        for (dst) |b| std.debug.print("{x:0>2} ", .{b});
        std.debug.print("\n", .{});
    }
}
