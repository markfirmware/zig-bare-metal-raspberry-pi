export fn kernelMain() void {
    arm.setCntfrq(1*1000*1000);
    arm.setBssToZero();

    serial.init();
    var sctlr_el3 = asm("mrs %[sctlr_el3], sctlr_el3"
        : [sctlr_el3] "=r" (-> usize)
    );
    log("sctlr_el3 {x}", sctlr_el3);
    sctlr_el3 = sctlr_el3 & ~u64(2) | 0x40;
    log("sctlr_el3 {x}", sctlr_el3);
    asm volatile("msr sctlr_el3, %[sctlr_el3]"
        :
        : [sctlr_el3] "{x0}" (sctlr_el3)
    );
    log("sctlr_el3 {x}", sctlr_el3);

    pollData();
}

fn pollData() void {
    if (poll()) |event_data| {
        var buf = event_data;
        const rssi = buf[buf.len - 1]; // this is required to break
    }
}

pub var poll_data_buf: [50]u8 = undefined;
pub fn poll() ?[]u8 {
    return poll_data_buf[0..];
}

export fn exceptionEntry0x00() noreturn {
    exceptionHandler(0x00);
}

export fn exceptionEntry0x01() noreturn {
    exceptionHandler(0x01);
}

export fn exceptionEntry0x02() noreturn {
    exceptionHandler(0x02);
}

export fn exceptionEntry0x03() noreturn {
    exceptionHandler(0x03);
}

export fn exceptionEntry0x04() noreturn {
    exceptionHandler(0x04);
}

export fn exceptionEntry0x05() noreturn {
    exceptionHandler(0x05);
}

export fn exceptionEntry0x06() noreturn {
    exceptionHandler(0x06);
}

export fn exceptionEntry0x07() noreturn {
    exceptionHandler(0x07);
}

export fn exceptionEntry0x08() noreturn {
    exceptionHandler(0x08);
}

export fn exceptionEntry0x09() noreturn {
    exceptionHandler(0x09);
}

export fn exceptionEntry0x0A() noreturn {
    exceptionHandler(0x0A);
}

export fn exceptionEntry0x0B() noreturn {
    exceptionHandler(0x0B);
}

export fn exceptionEntry0x0C() noreturn {
    exceptionHandler(0x0C);
}

export fn exceptionEntry0x0D() noreturn {
    exceptionHandler(0x0D);
}

export fn exceptionEntry0x0E() noreturn {
    exceptionHandler(0x0E);
}

export fn exceptionEntry0x0F() noreturn {
    exceptionHandler(0x0F);
}

fn exceptionHandler(entry_number: u32) noreturn {
    var current_el = asm("mrs %[current_el], CurrentEL"
        : [current_el] "=r" (-> usize));
    var sctlr_el3 = asm("mrs %[sctlr_el3], sctlr_el3"
        : [sctlr_el3] "=r" (-> usize));
    var esr_el3 = asm("mrs %[esr_el3], esr_el3"
        : [esr_el3] "=r" (-> usize));
    var elr_el3 = asm("mrs %[elr_el3], elr_el3"
        : [elr_el3] "=r" (-> usize));
    var spsr_el3 = asm("mrs %[spsr_el3], spsr_el3"
        : [spsr_el3] "=r" (-> usize));
    var far_el3 = asm("mrs %[far_el3], far_el3"
        : [far_el3] "=r" (-> usize));
    log("\n");
    switch (esr_el3) {
        0x96000021 => {
            log("alignment fault data abort exception level {} (no change) 32 bit instruction at 0x{x} reading from 0x{x}", current_el >> 2 & 0x3, elr_el3, far_el3);
        },
        0x96000050 => {
            log("synchronous external data abort exception level {} (no change) 32 bit instruction at 0x{x} writing to 0x{x}", current_el >> 2 & 0x3, elr_el3, far_el3);
        },
        else => {
            log("arm exception taken");
        },
    }
    log("CurrentEL {x} exception level {}", current_el, current_el >> 2 & 0x3);
    log("esr_el3 {x} class 0x{x}", esr_el3, esr_el3 >> 26 & 0x3f);
    log("spsr_el3 {x}", spsr_el3);
    log("elr_el3 {x}", elr_el3);
    log("far_el3 {x}", far_el3);
    log("sctlr_el3 {x}", sctlr_el3);
    arm.hang("core 0 is now idle in arm exception handler (other cores were already idle from start up)");
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("main.zig pub fn panic(): {}", message);
}

const arm = @import("arm_assembly_code.zig");
const builtin = @import("builtin");
const log = serial.log;
const panicf = arm.panicf;
const serial = @import("serial.zig");
