pub fn useAsAlt5(pin_number: u32) void {
      setPinPull(pin_number, Pull.None);
      setPinFunction(pin_number, GPIO_FUNCTION_ALT5);
}

pub fn useAsOutput(pin_number: u32) void {
      setPinPull(pin_number, Pull.None);
      setPinFunction(pin_number, GPIO_FUNCTION_OUT);
}

pub fn setPinOutputBool(pin_number: u32, onOrOff: bool) void {
    if (onOrOff) {
        gpset_array.write(pin_number, 1);
    } else {
        gpclr_array.write(pin_number, 1);
    }
}

fn setPinPull(pin_number: u32, pull: Pull) void {
    GPPUD.* = @enumToInt(pull);
    arm.delay(150);
    gppudclk_array.write(pin_number, 1);
    arm.delay(150);
    gppudclk_array.write(pin_number, 0);
}

fn setPinFunction(pin_number: u32, function: u32) void {
    gpfsel_array.write(pin_number, function);
}

fn ioArrayOf(base: u32, field_size: u32, length: u32) type {
    var IoArray = struct {
        const Self = @This();

        fn write(self: Self, index: u32, value: u32) void {
            const field_mask = u32(1) << @intCast(u5, field_size - 1);
            rangeCheck(index, length - 1);
            rangeCheck(value, field_mask);
            const fields_per_word = 32 / field_size;
            const register = arm.io(u32, base + (index / fields_per_word) * 4);
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

const gpclr_array: ioArrayOf(0x200028, 1, GPIO_MAX_PIN) = undefined;
const gpfsel_array: ioArrayOf(0x200000, 3, GPIO_MAX_PIN) = undefined;
const gpset_array: ioArrayOf(0x20001C, 1, GPIO_MAX_PIN) = undefined;
const GPPUD = arm.io(u32, 0x200094);
const gppudclk_array: ioArrayOf(0x200098, 1, GPIO_MAX_PIN) = undefined;

const GPIO_MAX_PIN = 53;

const Pull = enum {
    None,
    Down,
    Up,
};

const GPIO_FUNCTION_FIELD_SIZE: u32 = 3;
const GPIO_FUNCTION_OUT: u32 = 1;
const GPIO_FUNCTION_ALT5: u32 = 2;

const arm = @import("arm_assembly_code.zig");
const panicf = arm.panicf;
