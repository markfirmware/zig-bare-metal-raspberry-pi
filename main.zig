export fn main() void {
    const err = std.fmt.bufPrint(&buf, "", .{});
}

var buf: [100]u8 = undefined;
const std = @import("std");
