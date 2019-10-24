
pub const PERIPHERAL_BASE = 0x3F000000;

var already_panicking: bool = false;
pub fn panicf(comptime fmt: []const u8, args: ...) noreturn {
    @setCold(true);
    if (already_panicking) {
        hang("\npanicked during kernel panic");
    }
    already_panicking = true;

    log("\npanic: " ++ fmt, args);
    hang("panic completed");
}

pub fn io(comptime StructType: type, offset: u32) *volatile StructType {
    return @intToPtr(*volatile StructType, PERIPHERAL_BASE + offset);
}

pub fn hang(comptime format: []const u8, args: ...) noreturn {
    log(format, args);
    while (!serial.isOutputQueueEmpty()) {
        serial.loadOutputFifo();
    }
    while (true) {
        asm volatile("wfe");
    }
}

pub fn setCntfrq(word: u32) void {
    asm volatile("msr cntfrq_el0, %[word]"
        :
        : [word] "{x0}" (word)
    );
}

// Loop count times in a way that the compiler won't optimize away.
pub fn delay(count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        asm volatile("mov x0, x0");
    }
}

// The linker will make the address of these global variables equal
// to the value we are interested in. The memory at the address
// could alias any uninitialized global variable in the kernel.
extern var __bss_start: u8;
extern var __bss_end: u8;
extern var __end_init: u8;

pub fn setBssToZero() void {
    @memset((*volatile [1]u8)(&__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
}


comptime {
    asm(
        \\.section .text.boot // .text.boot to keep this in the first portion of the binary
        \\.globl _start
        \\_start:
        \\ mrs x0,mpidr_el1
        \\ mov x1,#0xC1000000
        \\ bic x0,x0,x1
        \\ cbz x0,master
        \\hang:
        \\ wfe
        \\ b hang
        \\master:
        \\ mov sp,#0x08000000
        \\ mov x0,#0x1000 //exception_vector_table
        \\ msr vbar_el3,x0
        \\ msr vbar_el2,x0
        \\ msr vbar_el1,x0
        \\ bl kernelMain
        \\.balign 0x800
        \\.section .text.exception_vector_table
        \\exception_vector_table:
        \\.balign 0x80
        \\ b exceptionEntry0x00
        \\.balign 0x80
        \\ b exceptionEntry0x01
        \\.balign 0x80
        \\ b exceptionEntry0x02
        \\.balign 0x80
        \\ b exceptionEntry0x03
        \\.balign 0x80
        \\ b exceptionEntry0x04
        \\.balign 0x80
        \\ b exceptionEntry0x05
        \\.balign 0x80
        \\ b exceptionEntry0x06
        \\.balign 0x80
        \\ b exceptionEntry0x07
        \\.balign 0x80
        \\ b exceptionEntry0x08
        \\.balign 0x80
        \\ b exceptionEntry0x09
        \\.balign 0x80
        \\ b exceptionEntry0x0A
        \\.balign 0x80
        \\ b exceptionEntry0x0B
        \\.balign 0x80
        \\ b exceptionEntry0x0C
        \\.balign 0x80
        \\ b exceptionEntry0x0D
        \\.balign 0x80
        \\ b exceptionEntry0x0E
        \\.balign 0x80
        \\ b exceptionEntry0x0F
    );
}

const log = serial.log;
const serial = @import("serial.zig");
