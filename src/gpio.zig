pub fn useAsAlt3(pin_number: u32) void {
    setPinPull(pin_number, Pull.None);
    setPinFunction(pin_number, GPIO_FUNCTION_ALT3);
}

pub fn useAsAlt5(pin_number: u32) void {
    setPinPull(pin_number, Pull.None);
    setPinFunction(pin_number, GPIO_FUNCTION_ALT5);
}

pub fn initOutputPinWithPullNone(pin_number: u32) void {
    setPinPull(pin_number, Pull.None);
    setPinFunction(pin_number, GPIO_FUNCTION_OUT);
}

pub fn setPinOutputBool(pin_number: u32, onOrOff: bool) void {
    if (onOrOff) {
        pins_set.write(pin_number, 1);
    } else {
        pins_clear.write(pin_number, 1);
    }
}

fn setPinPull(pin_number: u32, pull: Pull) void {
    GPPUD.* = @enumToInt(pull);
    arm.delay(150);
    pins_pull.write(pin_number, 1);
    arm.delay(150);
    GPPUD.* = @enumToInt(Pull.None);
    pins_pull.write(pin_number, 0);
}

fn setPinFunction(pin_number: u32, function: u32) void {
    pins_function.write(pin_number, function);
}

pub fn ioArrayOf(base: u32, field_size: u32, length: u32) type {
    var IoArray = struct {
        const Self = @This();

        fn write(self: Self, index: u32, value: u32) void {
            const field_mask = (@as(u32, 1) << @intCast(u5, field_size)) - 1;
            rangeCheck(index, length - 1);
            rangeCheck(value, field_mask);
            const fields_per_word = 32 / field_size;
            const register = @intToPtr(*volatile u32, base + (index / fields_per_word) * 4);
            const shift = @intCast(u5, (index % fields_per_word) * field_size);
            var word = register.*;
            word &= ~(field_mask << shift);
            word |= value << shift;
            register.* = word;
        }
    };
    return IoArray;
}

fn rangeCheck(x: u32, max: u32) void {
    if (x > max) {
        panicf("{} exceeds max {}", x, max);
    }
}

const pins_set: ioArrayOf(GPSET0, 1, GPIO_MAX_PIN) = undefined;
const pins_clear: ioArrayOf(GPCLR0, 1, GPIO_MAX_PIN) = undefined;
const pins_pull: ioArrayOf(GPPUDCLK0, 1, GPIO_MAX_PIN) = undefined;
const pins_function: ioArrayOf(GPFSEL0, 3, GPIO_MAX_PIN) = undefined;

const GPIO_MAX_PIN = 53;

const GPFSEL0 = PERIPHERAL_BASE + 0x200000;
const GPSET0 = PERIPHERAL_BASE + 0x20001C;
const GPCLR0 = PERIPHERAL_BASE + 0x200028;
const GPPUD = arm.io(u32, 0x200094);
const GPPUDCLK0 = PERIPHERAL_BASE + 0x200098;

const Pull = enum {
    None,
    Down,
    Up,
};

const GPIO_FUNCTION_OUT = 1;
const GPIO_FUNCTION_ALT5 = 2;
const GPIO_FUNCTION_ALT3 = 7;

const arm = @import("arm_assembly_code.zig");
const panicf = arm.panicf;
const PERIPHERAL_BASE = arm.PERIPHERAL_BASE;
