
pub fn line(comptime fmt: []const u8, args: ...) void {
    literal(fmt, args);
    pair(0, 0, "K");
    literal("\r\n");
}

pub fn clearScreen() void {
    pair(2, 0, "J");
}

pub fn setScrollingRegion(top: u32, bottom: u32) void {
    pair(top, bottom, "r");
}

pub fn move(row: u32, column: u32) void {
    pair(row, column, "H");
}

pub fn hideCursor() void {
    literal(csi ++ "?25l");
}

pub fn showCursor() void {
    literal(csi ++ "?25h");
}

pub fn saveCursor() void {
    pair(0, 0, "s");
}

pub fn restoreCursor() void {
    pair(0, 0, "u");
}

fn pair(a: u32, b: u32, letter: []const u8) void {
    if (a <= 1 and b <= 1) {
        literal("{}{}", csi, letter);
    } else if (b <= 1) {
        literal("{}{}{}", csi, a, letter);
    } else if (a <= 1) {
        literal("{};{}{}", csi, b, letter);
    } else {
        literal("{}{};{}{}", csi, a, b, letter);
    }
}

const csi = "\x1b[";
const literal = @import("serial.zig").literal;
