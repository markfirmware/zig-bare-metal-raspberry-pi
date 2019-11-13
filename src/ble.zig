pub fn init() u32 {
    initUart0();
    hciCommand(OGF_HOST_CONTROL, COMMAND_RESET_CHIP, &[_]u8{});
    bcmLoadFirmware();
    setLeEventMask(0xff);
    startActiveScanning();
    return messages_received;
}

fn uartError(byte: u32) bool {
    if (byte & 0xffffff00 != 0) {
        error_count += 1;
        while (isReadByteReady()) {
            _ = readByte32();
        }
        resetPoll();
        return true;
    }
    return false;
}

fn resetPoll() void {
    poll_state = 0;
    discarded_count += bytes_recently_received;
    bytes_recently_received = 0;
}

var poll_state: u32 = 0;
pub var data_len: u32 = undefined;
pub var data_buf: [50]u8 = undefined;
pub var messages_received: u32 = 0;
pub var error_count: u32 = 0;
pub var discarded_count: u32 = 0;
pub var max_read_run: u32 = 0;
pub fn poll() ?[]u8 {
    const goal = messages_received + 1;
    if (isReadByteReady()) {
        var start_time = arm.microseconds.read();
        while (messages_received < goal and arm.microseconds.read() < start_time + 200) {
            var run: u32 = 0;
            while (messages_received < goal and isReadByteReady()) {
                start_time = arm.microseconds.read();
                run += 1;
                var byte = readByte32();
                if (!uartError(byte)) {
                    byte &= 0xff;
                    poll2(byte);
                }
            }
            max_read_run = math.max(run, max_read_run);
        }
        return data_buf[0..data_len];
    }
    return null;
}

fn poll2(byte: u32) void {
    switch (poll_state) {
        0 => {
            if (byte != 0x04) {
                resetPoll();
            } else {
                poll_state = 1;
            }
        },
        1 => {
            if (byte != 0x3e) {
                resetPoll();
            } else {
                poll_state = 2;
            }
        },
        2 => {
            if (byte > data_buf.len) {
                resetPoll();
            } else {
                poll_state = 3;
                data_len = byte;
            }
        },
        else => {
            data_buf[poll_state - 3] = @truncate(u8, byte);
            if (poll_state == data_len + 3 - 1) {
                messages_received += 1;
                bytes_recently_received = 0;
                resetPoll();
            } else {
                poll_state += 1;
            }
        },
    }
}

fn setLeEventMask(mask: u8) void {
    hciCommand(OGF_LE_CONTROL, 0x01, &[_]u8{ mask, 0, 0, 0, 0, 0, 0, 0 });
}

fn setLeScanEnable(state: bool, duplicates: bool) void {
    hciCommand(OGF_LE_CONTROL, 0x0c, &[_]u8{ boolToU8(state), boolToU8(duplicates) });
}

fn setLeScanParameters(type_: u8, interval: u16, window: u16, own_address_type: u8, filter_policy: u8) void {
    hciCommand(OGF_LE_CONTROL, 0x0b, &[_]u8{
        type_, lo(interval), hi(interval), lo(window), hi(window), own_address_type, filter_policy,
    });
}

fn startPassiveScanning() void {
    setLeScanParameters(LL_SCAN_PASSIVE, @floatToInt(u32, BleScanInterval * BleScanUnitsPerSecond), @floatToInt(u32, BleScanWindow * BleScanUnitsPerSecond), 0x00, 0x00);
    setLeScanEnable(true, false);
}

fn startActiveScanning() void {
    setLeScanParameters(LL_SCAN_ACTIVE, @floatToInt(u32, BleScanInterval * BleScanUnitsPerSecond), @floatToInt(u32, BleScanWindow * BleScanUnitsPerSecond), 0x00, 0x00);
    setLeScanEnable(true, false);
}

fn StopScanning() void {
    setLeScanEnable(false, false);
}

fn hciCommand(ogf: u16, ocf: u16, data: []const u8) void {
    const op_code: u16 = @as(u16, ogf) << 10 | ocf;
    hciCommandBytes([_]u8{ @truncate(u8, op_code & 0xff), @truncate(u8, (op_code & 0xff00) >> 8) }, data);
}

var command_counter: u32 = 0;
fn hciCommandBytes(op_code: []const u8, data: []const u8) void {
    command_counter += 1;
    writeByte(HCI_COMMAND_PKT);
    writeByte(op_code[0]);
    writeByte(op_code[1]);
    writeByte(@truncate(u8, data.len));
    for (data) |b| {
        writeByte(b);
    }
    assert(waitReadByte() == HCI_EVENT_PKT);
    assert(waitReadByte() == EVENT_TYPE_COMMAND_STATUS);
    assert(waitReadByte() == 4);
    assert(waitReadByte() != 0);
    assert(waitReadByte() == op_code[0]);
    assert(waitReadByte() == op_code[1]);
    var command_status = waitReadByte();
    assert(command_status == 0);
}

fn flushRx() void {
    while (isReadByteReady()) {
        log("flushRx() 0x{x}", uart0_registers.DR);
    }
}

fn initUart0() void {
    flushRx();
    uart0_registers.CR = 0x00;
    uart0_registers.LCRH = 0x00;
    uart0_registers.IBRD = 0x1a;
    uart0_registers.FBRD = 0x03;
    uart0_registers.LCRH = 0x70;
    uart0_registers.CR = 0x300;
    uart0_registers.CR = 0x301;

    gpio.useAsAlt3(32);
    gpio.useAsAlt3(33);
    arm.delayMilliseconds(20);
    while (isReadByteReady()) {
        log("post flush rx 0x{x}", uart0_registers.DR);
    }
}

fn bcmLoadFirmware() void {
    log("Firmware load ...");
    const fw = &@embedFile("../assets/BCM4345C0.hcd");
    hciCommand(OGF_VENDOR, VENDOR_LOAD_FIRMWARE, &[_]u8{});
    var i: u32 = 0;
    while (i < fw.len) {
        const op_code = fw[i .. i + 2];
        const len = fw[i + 2];
        const data = fw[i + 3 .. i + 3 + len];
        hciCommandBytes(op_code, data);
        i += 3 + len;
    }
    arm.delayMilliseconds(200);
    log("Firmware load done");
}

pub fn isWritingDone() bool {
    const TXFE = 0x80;
    return uart0_registers.FR & TXFE != 0;
}

pub fn writeByte(byte: u8) void {
    const TXFF = 0x20;
    while (uart0_registers.FR & TXFF != 0) {}
    uart0_registers.DR = @intCast(u32, byte);
    serial.loadOutputFifo();
}

pub fn isReadByteReady() bool {
    const RXFE = 0x10;
    return uart0_registers.FR & RXFE == 0;
}

pub fn waitReadByte() u8 {
    while (!isReadByteReady()) {}
    return readByte("waitReadByte()");
}

var bytes_recently_received: u32 = 0;
pub fn readByte32() u32 {
    while (!isReadByteReady()) {}
    const word = uart0_registers.DR;
    bytes_recently_received += 1;
    return word;
}

pub fn readByte(message: []const u8) u8 {
    const word = readByte32();
    if (word & 0xffffff00 != 0) {
        panicf("readByte() {} uart0 status 0x{x} received {} discarded {}", message, word, bytes_recently_received, discarded_count);
    }
    return @truncate(u8, word);
}

fn boolToU8(x: bool) u8 {
    return if (x) @as(u8, 1) else 0;
}

fn lo(x: u16) u8 {
    return @truncate(u8, x & 0xff);
}

fn hi(x: u16) u8 {
    return @truncate(u8, (x & 0xff00) >> 8);
}

const uart0_registers = arm.io(Uart0Registers, 0x201000);
const Uart0Registers = packed struct {
    DR: u32,
    RSRECR: u32,
    Unused1: u32,
    Unused2: u32,
    Unused3: u32,
    Unused4: u32,
    FR: u32,
    Unused5: u32,
    Unused6: u32,
    IBRD: u32,
    FBRD: u32,
    LCRH: u32,
    CR: u32,
};

const BleScanUnitsPerSecond = 1600.0;
const BleScanInterval = 0.800;
const BleScanWindow = 0.400;

const COMMAND_RESET_CHIP = 0x03;
const EVENT_TYPE_COMMAND_STATUS = 0x0e;
const HCI_COMMAND_PKT = 0x01;
const HCI_EVENT_PKT = 0x04;
const OGF_HOST_CONTROL = 0x03;
const OGF_LE_CONTROL = 0x08;
const OGF_VENDOR = 0x3f;
const VENDOR_LOAD_FIRMWARE = 0x2e;
const LL_SCAN_PASSIVE = 0x00;
const LL_SCAN_ACTIVE = 0x01;

const arm = @import("arm_assembly_code.zig");
const assert = std.debug.assert;
const gpio = @import("gpio.zig");
const io = arm.io;
const log = @import("serial.zig").log;
const math = std.math;
const panicf = arm.panicf;
const serial = @import("serial.zig");
const std = @import("std");
