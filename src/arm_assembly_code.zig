var already_panicking: bool = false;
pub fn panicf(comptime fmt: []const u8, args: ...) noreturn {
    @setCold(true);
    if (already_panicking) {
        hang("\npanicked during kernel panic, execution stopped in panicf()");
    }
    already_panicking = true;

    log("panic: " ++ fmt, args);
    hang("panic completed, exceution stopped in panicf()");
}

pub fn io(comptime StructType: type, offset: u32) *volatile StructType {
    const PERIPHERAL_BASE = if (build_options.subarch >= 7) 0x3F000000 else 0x20000000;
    return @intToPtr(*volatile StructType, PERIPHERAL_BASE + offset);
}

// Loop count times in a way that the compiler won't optimize away.
pub fn delay(count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        asm volatile("mov r0, r0");
    }
}

pub fn hang(comptime format: []const u8, args: ...) noreturn {
    log(format, args);
    while (true) {
        if (build_options.subarch >= 7) {
            v7.wfe();
        }
    }
}

pub const v7 = struct {
    pub fn mpidr() u32 {
        var word = asm("mrc p15, 0, %[word], c0, c0, 5"
            : [word] "=r" (-> usize));
        return word;
    }

    pub fn wfe() void {
        asm volatile("wfe");
    }
};

pub inline fn lr() u32 {
    var word = asm("mov %[word], lr"
        : [word] "=r" (-> usize));
    return word;
}

pub inline fn sp() u32 {
    var word = asm("mov %[word], sp"
        : [word] "=r" (-> usize));
    return word;
}

pub fn cpsr() u32 {
    var word = asm("mrs %[word], cpsr"
        : [word] "=r" (-> usize));
    return word;
}

pub fn spsr() u32 {
    var word = asm("mrs %[word], spsr"
        : [word] "=r" (-> usize));
    return word;
}

pub fn sctlr() u32 {
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
    asm volatile("mcr p15, #0, %[address], cr12, cr0, 0"
        :
        : [address] "{r0}" (address)
    );
}

pub fn cntpct32() u32 {
    return asm("mrrc p15, 0, %[cntpct_lo], r1, c14"
        : [cntpct_lo] "=r" (-> usize)
        :
        : "r1");
}

pub fn seconds() u32 {
    return cntpct32() / (192*100*1000);
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

const build_options = @import("build_options");
const log = @import("serial.zig").log;
