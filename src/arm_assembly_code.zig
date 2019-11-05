
pub const PERIPHERAL_BASE = if (build_options.subarch >= 7) 0x3F000000 else 0x20000000;

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

pub fn getUnalignedU32(base: [*]u8, offset: u32) u32 {
    var word: u32 = 0;
    var i: u32 = 0;
    while (i <= 3) : (i += 1) {
        word >>= 8;
        word |= @intCast(u32, @intToPtr(*u8, @ptrToInt(base) + offset + i).*) << 24;
    }
    return word;
}

pub fn io(comptime StructType: type, offset: u32) *volatile StructType {
    return @intToPtr(*volatile StructType, PERIPHERAL_BASE + offset);
}

pub fn hang(comptime format: []const u8, args: ...) noreturn {
    log(format, args);
    var time = milliseconds.read();
    while (!serial.isOutputQueueEmpty()) {
        serial.loadOutputFifo();
    }
    while (true) {
      if (build_options.subarch >= 7) {
            v7.wfe();
        }
    }
}

pub const v7 = struct {
    pub inline fn mpidr() u32 {
        var word = asm("mrc p15, 0, %[word], c0, c0, 5"
            : [word] "=r" (-> usize));
        return word;
    }

    pub inline fn wfe() void {
        asm volatile("wfe");
    }
};

pub fn sp() usize {
    var word = asm("mov %[word], sp"
        : [word] "=r" (-> usize));
    return word;
}

pub fn cpsr() usize {
    var word = asm("mrs %[word], cpsr"
        : [word] "=r" (-> usize));
    return word;
}

pub fn spsr() usize {
    var word = asm("mrs %[word], spsr"
        : [word] "=r" (-> usize));
    return word;
}

pub fn sctlr() usize {
    var word = asm("mrc p15, 0, %[word], c1, c0, 0"
        : [word] "=r" (-> usize));
    return word;
}

pub fn scr() u32 {
    var word = asm("mrc p15, 0, %[word], c1, c1, 0"
        : [word] "=r" (-> usize));
    return word;
}

pub fn dsbSt() void {
    if (build_options.subarch >= 7) {
        asm volatile("dsb st");
    } else {
        asm volatile("mcr p15, 0, r0, c7, c10, 4"
            :
            :
            : "r0");
    }
}

pub fn setVectorBaseAddressRegister(address: u32) void {
    if (build_options.subarch >= 8) {
        asm volatile("mcr p15, 0, %[address], cr12, cr0, 0"
            :
            : [address] "{x0}" (address)
        );
    } else {
        asm volatile("mcr p15, 0, %[address], cr12, cr0, 0"
            :
            : [address] "{r0}" (address)
        );
    }
}

pub fn setCntfrq(word: u32) void {
    if (build_options.subarch >= 8) {
        asm volatile("msr cntfrq_el0, %[word]"
            :
            : [word] "{x0}" (word)
        );
    } else {
        asm volatile("mcr p15, 0, %[word], c14, c0, 0"
            :
            : [word] "{r0}" (word)
        );
    }
}

pub fn cntfrq() u32 {
    var word: usize = undefined;
    if (build_options.subarch >= 8) {
        word = asm volatile("mrs %[word], cntfrq_el0"
            : [word] "=r" (-> usize)
        );
    } else {
        word = asm("mrc p15, 0, %[word], c14, c0, 0"
            : [word] "=r" (-> usize)
        );
    }
    return @truncate(u32, word);
}

pub fn cntpct32() u32 {
    var word: usize = undefined;
    if (build_options.subarch >= 8) {
        word = asm volatile("mrs %[word], cntpct_el0"
            : [word] "=r" (-> usize)
        );
    } else {
        word = asm("mrrc p15, 0, %[cntpct_low], r1, c14"
            : [cntpct_low] "=r" (-> usize)
            :
            : "r1"
        );
    }
    return @truncate(u32, word);
}

// Loop count times in a way that the compiler won't optimize away.
pub fn delay(count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (build_options.subarch >= 8) {
            asm volatile("mov x0, x0");
        } else {
            asm volatile("mov r0, r0");
        }
    }
}

pub fn delayMilliseconds(duration: u32) void {
    const start = milliseconds.read();
    while (milliseconds.read() < start + duration) {
    }
}

pub var microseconds: Timer = undefined;
pub var milliseconds: Timer = undefined;
pub var seconds: Timer = undefined;

const Timer = struct {
    frequency: u32,
    last_low: u32,
    overflow: u32,

    fn initScale(self: *Timer, scale: u32) void {
        self.frequency = cntfrq() / scale;
        self.last_low = cntpct32();
        self.overflow = 0;
    }

    fn read(self: *Timer) u32 {
        const low = cntpct32();
        if (low < self.last_low) {
            self.overflow += 0xffffffff / self.frequency;
        }
        self.last_low = low;
        return low / self.frequency + self.overflow;
    }
};

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
    );

    if (build_options.subarch == 7) {
        asm(
            \\ mrc p15, 0, r0, c0, c0, 5
            \\ and r0,#3
            \\ cmp r0,#0
            \\ beq core_0
            \\
            \\not_core_0:
            \\ wfe
            \\ b not_core_0
            \\
            \\core_0:
        );
    }

    if (build_options.subarch <= 7) {
        asm(
            \\ cps #0x1f // enter system mode
            \\ mov sp,#0x08000000
            \\ bl kernelMain
            \\
            \\.section .text.exception_vector_table
            \\.balign 0x80
            \\exception_vector_table:
            \\ b exceptionEntry0x00
            \\ b exceptionEntry0x01
            \\ b exceptionEntry0x02
            \\ b exceptionEntry0x03
            \\ b exceptionEntry0x04
            \\ b exceptionEntry0x05
            \\ b exceptionEntry0x06
            \\ b exceptionEntry0x07
        );
    } else {
        asm(
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
}

const build_options = @import("build_options");
const log = serial.log;
const serial = @import("serial.zig");
