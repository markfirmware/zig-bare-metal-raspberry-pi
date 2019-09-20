const arm = @import("arm_assembly_code.zig");
const fmt = std.fmt;
const gpio = @import("gpio.zig");
const io = arm.io;
const PERIPHERAL_BASE = arm.PERIPHERAL_BASE;
const std = @import("std");

const AUX_ENABLES = io(0x215004);

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

const serial_registers = arm.ioStruct(SerialRegisters, 0x215040);

const NoError = error{};

pub fn writeByte(byte: u8) void {
    // Wait for UART to become ready to transmit.
    while (serial_registers.AUX_MU_LSR_REG & 0x20 == 0) {
    }
    serial_registers.AUX_MU_IO_REG = @intCast(u32, byte);
}

pub fn isReadByteReady() bool {
    return serial_registers.AUX_MU_LSR_REG & 0x01 != 0;
}

pub fn readByte() u8 {
    // Wait for UART to have recieved something.
    while (!isReadByteReady()) {
    }
    return @truncate(u8, serial_registers.AUX_MU_IO_REG);
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
    gpio.setAlt5(14);
    gpio.setAlt5(15);
    serial_registers.AUX_MU_CNTL_REG = 3;
}

pub fn log(comptime format: []const u8, args: ...) void {
    fmt.format({}, NoError, logBytes, format ++ "\n", args) catch |e| switch (e) {};
}

fn logBytes(context: void, bytes: []const u8) NoError!void {
    writeText(bytes);
}
