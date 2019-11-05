const arm = @import("arm_assembly_code.zig");
const build_options = @import("build_options");
const fmt = std.fmt;
const gpio = @import("gpio.zig");
const io = arm.io;
const PERIPHERAL_BASE = arm.PERIPHERAL_BASE;
const std = @import("std");

const uart0_registers = arm.io(Uart0Registers, 0x201000);
const Uart0Registers = packed struct {
    DR: u32,
};

const aux_registers = arm.io(AuxRegisters, 0x215000);
const AuxRegisters = packed struct {
    AUX_IRQ: u32,
    AUX_ENABLES: u32,
    UNUSED1: u32,
    UNUSED2: u32,
    UNUSED3: u32,
    UNUSED4: u32,
    UNUSED5: u32,
    UNUSED6: u32,
    UNUSED7: u32,
    UNUSED8: u32,
    UNUSED9: u32,
    UNUSED10: u32,
    UNUSED11: u32,
    UNUSED12: u32,
    UNUSED13: u32,
    UNUSED14: u32,
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

var output_queue: [16 * 1024]u8 = undefined;
var output_queue_write: usize = 0;
var output_queue_read: usize = 0;
pub fn loadOutputFifo() void {
    while (!isOutputQueueEmpty() and isWriteByteReady()) {
        writeByteBlockingActual(output_queue[output_queue_read]);
        output_queue_read = output_queue_read + 1 & (output_queue.len - 1);
    }
}

pub fn isOutputQueueEmpty() bool {
    return output_queue_read == output_queue_write;
}

pub fn drainOutputQueue() void {
    while (!isOutputQueueEmpty()) {
        loadOutputFifo();
    }
}

pub fn writeByteBlocking(byte: u8) void {
    const next = output_queue_write + 1 & (output_queue.len - 1);
    while (next == output_queue_read) {
        loadOutputFifo();
    }
    output_queue[output_queue_write] = byte;
    output_queue_write = next;
}

pub fn writeByteBlockingActual(byte: u8) void {
    if (build_options.is_qemu) {
        uart0_registers.DR = @intCast(u32, byte);
    } else {
        while (!isWriteByteReady()) {
        }
        aux_registers.AUX_MU_IO_REG = @intCast(u32, byte);
    }
}

pub fn isWriteByteReady() bool {
    if (build_options.is_qemu) {
        return true;
    } else {
        return aux_registers.AUX_MU_LSR_REG & 0x20 != 0;
    }
}

pub fn isReadByteReady() bool {
    if (build_options.is_qemu) {
        return arm.io(u32, 0x201018).* & 0x10 == 0;
    } else {
        return aux_registers.AUX_MU_LSR_REG & 0x01 != 0;
    }
}

pub fn readByte() u8 {
    // Wait for UART to have recieved something.
    while (!isReadByteReady()) {
    }
    if (build_options.is_qemu) {
        return @truncate(u8, uart0_registers.DR);
    } else {
        return @truncate(u8, aux_registers.AUX_MU_IO_REG);
    }
}

pub fn write(buffer: []const u8) void {
    for (buffer) |c|
        writeByteBlocking(c);
}

/// Translates \n into \r\n
pub fn writeText(buffer: []const u8) void {
    for (buffer) |c| {
        switch (c) {
            '\n' => {
                writeByteBlocking('\r');
                writeByteBlocking('\n');
            },
            else => writeByteBlocking(c),
        }
    }
}

pub fn init() void {
    aux_registers.AUX_ENABLES = 1;
    aux_registers.AUX_MU_IER_REG = 0;
    aux_registers.AUX_MU_CNTL_REG = 0;
    aux_registers.AUX_MU_LCR_REG = 3;
    aux_registers.AUX_MU_MCR_REG = 0;
    aux_registers.AUX_MU_IER_REG = 0;
    aux_registers.AUX_MU_IIR_REG = 0xC6;
    aux_registers.AUX_MU_BAUD_REG = 68; //270;
    gpio.useAsAlt5(14);
    gpio.useAsAlt5(15);
    aux_registers.AUX_MU_CNTL_REG = 3;
}

const NoError = error{};

pub fn literal(comptime format: []const u8, args: ...) void {
    fmt.format({}, NoError, logBytes, format, args) catch |e| switch (e) {};
}

pub fn log(comptime format: []const u8, args: ...) void {
    literal(format ++ "\n", args);
}

fn logBytes(context: void, bytes: []const u8) NoError!void {
    writeText(bytes);
}
