const arm = @import("arm_assembly_code.zig");
const build_options = @import("build_options");
const fmt = std.fmt;
const gpio = @import("gpio.zig");
const io = arm.io;
const std = @import("std");

const AUX_ENABLES = io(u32, 0x215004);
const serial_registers = arm.io(SerialRegisters, 0x215040);
const SerialRegisters = packed struct {
    AUX_MU_IO_REG: u32,
    AUX_MU_IER_REG: u32,
    AUX_MU_IIR_REG: u32,
    AUX_MU_LCR_REG: u32,
    AUX_MU_MCR_REG: u32,
    AUX_MU_LSR_REG: u32,
    AUX_MU_MSR_REG: u32,
    AUX_MU_SCRATCH: u32,
    AUX_MU_CNTL_REG: u32,
    AUX_MU_STAT_REG: u32,
    AUX_MU_BAUD_REG: u32,
};

pub fn writeByte(byte: u8) void {
//  // Wait for UART to become ready to transmit.
//  while (serial_registers.AUX_MU_LSR_REG & 0x20 == 0) {
//  }
//  serial_registers.AUX_MU_IO_REG = @intCast(u32, byte);
    const out = @intToPtr(*volatile u32, 0x3f201000); //arm.io(u32, 0x201000);
    out.* = @intCast(u32, byte);
}

pub fn isReadByteReady() bool {
    if (build_options.is_qemu) {
        return arm.io(u32, 0x201018).* & 0x10 == 0;
    } else {
        return serial_registers.AUX_MU_LSR_REG & 0x01 != 0;
    }
}

pub fn readByteBlocking() u8 {
    while (!isReadByteReady()) {
    }
    if (build_options.is_qemu) {
        return @truncate(u8, arm.io(u32, 0x201000).*);
    } else {
        return @truncate(u8, serial_registers.AUX_MU_IO_REG);
    }
}

pub fn write(buffer: []const u8) void {
    for (buffer) |c|
        writeByte(c);
}

/// Translates \n into \r\n
pub fn writeText(buffer: []const u8) void {
    for (buffer) |c| {
        switch (c) {
            '\n' => {
                writeByte('\r');
                writeByte('\n');
            },
            else => writeByte(c),
        }
    }
}

pub fn init() void {
    AUX_ENABLES.* = 1;
    serial_registers.AUX_MU_IER_REG = 0;
    serial_registers.AUX_MU_CNTL_REG = 0;
    serial_registers.AUX_MU_LCR_REG = 3;
    serial_registers.AUX_MU_MCR_REG = 0;
    serial_registers.AUX_MU_IER_REG = 0;
    serial_registers.AUX_MU_IIR_REG = 0xC6;
    serial_registers.AUX_MU_BAUD_REG = 270;
    gpio.useAsAlt5(14);
    gpio.useAsAlt5(15);
    serial_registers.AUX_MU_CNTL_REG = 3;
}

const NoError = error{};

pub fn log(comptime format: []const u8, args: ...) void {
    fmt.format({}, NoError, logBytes, format ++ "\n", args) catch |e| switch (e) {};
}

fn logBytes(context: void, bytes: []const u8) NoError!void {
    writeText(bytes);
}

pub fn decimal(x: u32) void {
    var buf: [100]u8 = undefined;
    var i: u32 = buf.len;
    var y = x;
    while (i > 0) {
        i -= 1;
        const digit = @intCast(u8, y - 10 * (y / 10));
        buf[i] = if (digit < 10) digit + '0' else digit - 10 + 'A';
        y = y / 10;
        if (y == 0) {
            break;
        }
    }
    writeText(buf[i..]);
}

pub fn hex(message: [] const u8, x: u32) void {
    var buf: [8]u8 = undefined;
    var i: u32 = buf.len;
    var y = x;
    while (i > 0) : (i -= 1) {
        const digit = @intCast(u8, y & 0xf);
        buf[i - 1] = if (digit < 10) digit + '0' else digit - 10 + 'A';
        y = (y & 0xfffffff0) >> 4;
    }
    log("0x{} {}", buf, message);
}
