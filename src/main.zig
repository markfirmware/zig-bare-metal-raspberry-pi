export fn kernelMain2() noreturn {
    asm volatile(
        \\ mov r1,#0x20000000
        \\ orr r1,#0x00200000
        \\ mov r0,#0x10
        \\ str r0,[r1,#0x28]
        \\loop:
        \\ b loop
        \\ mov r0,#0x10
        \\ str r0,[r1,#0x1c]
        \\ bl delay
        \\ mov r0,#0x10
        \\ str r0,[r1,#0x28]
        \\ bl delay
        \\ b loop
        \\
        \\delay:
        \\ mov r1,#1024
        \\delay_x:
        \\ mov r0,#1024
        \\delay_0:
        \\ mov r0,r0
        \\ subs r0,#1
        \\ bne delay_0
        \\ subs r1,#1
        \\ bne delay_x
        \\ bx lr
    );
    while (true) {
    }
}

export fn kernelMain() noreturn {
    // set exception stacks
    asm volatile(
        \\ cps #0x17 // enter data abort mode
        \\ mov r0,#0x08000000
        \\ sub r0,0x100000
        \\ mov sp,r0
        \\
        \\ cps #0x1b // enter undefined instruction mode
        \\ mov r0,#0x08000000
        \\ sub r0,0x200000
        \\ mov sp,r0
        \\
        \\ cps #0x1f // back to system mode
    );

    arm.setVectorBaseAddressRegister(if (build_options.is_qemu) 0x11000 else 0x1000);
    arm.setBssToZero();

    serial.init();

    log("\x1b[H\x1b[J\x1b[4;200r");
    log("\n{} {} ...", name, release_tag);
//  log("numeric {}", arm.cpsr());

    fb.init();
    log("drawing logo ...");
    var logo: Bitmap = undefined;
    var logo_bmp_file align(@alignOf(u32)) = @embedFile("../assets/zig-logo.bmp");
    logo.init(&fb, &logo_bmp_file);
    logo.drawRect(logo.width, logo.height, 0, 0, 0, 0);

    screen_activity.init(logo.width, logo.height);
    serial_activity.init();

    while (true) {
        screen_activity.update();
        serial_activity.update();
    }
}

const ScreenActivity = struct {
    width: u32,
    height: u32,
    color: Color,
    color32: u32,
    top: u32,
    x: u32,
    y: u32,
    frame_count: u32,
    last_seconds: u32,

    fn init(self: *ScreenActivity, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
        self.color = color_yellow;
        self.color32 = fb.color32(self.color);
        self.top = height + margin;
        self.x = 0;
        self.y = self.top;
        self.frame_count = 0;
        self.last_seconds = arm.seconds();
    }

    fn update (self: *ScreenActivity) void {
        const new_seconds = arm.seconds();
        if (new_seconds >= self.last_seconds + 1) {
            self.last_seconds = new_seconds;
            serial.writeText("\x1b7\x1b[H");
            serial.decimal(self.last_seconds);
            serial.writeText(" seconds ");
            serial.decimal(self.frame_count);
            serial.writeText(" frames");
            serial.writeText("\x1b8");
        }
        fb.drawPixel32(self.x, self.y, self.color32);
        self.x += 1;
        if (self.x == self.width) {
            self.x = 0;
            self.y += 1;
            if (self.y == self.top + self.height) {
                self.y = self.top;
                self.frame_count += 1;
            }
            const delta = 10;
            self.color.red = self.color.red +% delta;
            if (self.color.red < delta) {
                self.color.green = self.color.green +% delta;
                if (self.color.green < delta) {
                    self.color.blue = self.color.blue +% delta;
                }
            }
            self.color32 = fb.color32(self.color);
        }
    }
};

const SerialActivity = struct {
    fn init(self: *SerialActivity) void {
        log("now echoing serial input - press ! to invoke numeric formatting exception");
    }

    fn update(self: *SerialActivity) void {
        if (!serial.isReadByteReady()) {
            return;
        }
        const byte = serial.readByteBlocking();
        switch (byte) {
            '!' => {
                const x: u32 = 0;
                log("invoke numeric formatting exception ... {}", x);
            },
            '\r' => {
                serial.writeText("\n");
            },
            else => serial.writeByte(byte),
        }
    }
};

comptime {
    asm(
        \\.section .text.boot // .text.boot to keep this in the first portion of the binary
        \\.globl _start
        \\_start:
    );

    if (build_options.subarch >= 7) {
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

    asm(
        \\ cps #0x1f // enter system mode
        \\ mov sp,#0x08000000
        \\ bl kernelMain
        \\
        \\.section .text.exception_vector_table_section
        \\.balign 0x80
        \\exception_vector_table:
        \\ b exceptionEntry0x00
        \\ b exceptionEntry0x04
        \\ b exceptionEntry0x08
        \\ b exceptionEntry0x0c
        \\ b exceptionEntry0x10
        \\ b exceptionEntry0x14
        \\ b exceptionEntry0x18
        \\ b exceptionEntry0x1c
    );
}

export fn exceptionEntry0x00() noreturn {
    exceptionHandler(arm.lr(), 0x00);
}

export fn exceptionEntry0x04() noreturn {
    exceptionHandler(arm.lr(), 0x04);
}

export fn exceptionEntry0x08() noreturn {
    exceptionHandler(arm.lr(), 0x08);
}

export fn exceptionEntry0x0c() noreturn {
    exceptionHandler(arm.lr(), 0x0c);
}

export fn exceptionEntry0x10() noreturn {
    exceptionHandler(arm.lr(), 0x10);
}

export fn exceptionEntry0x14() noreturn {
    exceptionHandler(arm.lr(), 0x14);
}

export fn exceptionEntry0x18() noreturn {
    exceptionHandler(arm.lr(), 0x18);
}

export fn exceptionEntry0x1c() noreturn {
    exceptionHandler(arm.lr(), 0x1c);
}

var exception_active: bool = false;

fn exceptionHandler(lr: u32, entry: u32) noreturn {
    if (exception_active) {
        panicf("exceptionHandler already handling exception");
    } else {
        exception_active = true;
        log("");
        log("arm exception taken");
        hex("vector offset", entry);
        hex("spsr", arm.spsr());
        hex("cpsr", arm.cpsr());
        hex("lr", lr);
        hex("sp", arm.sp());
        hex("sctlr", arm.sctlr());
        arm.hang("execution is now stopped in exceptionHandler()");
    }
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("main.zig pub fn panic(): {}", message);
}

var screen_activity: ScreenActivity = undefined;
var serial_activity: SerialActivity = undefined;
var fb: FrameBuffer = undefined;

const margin = 10;

const color_red = Color{ .red = 255, .green = 0, .blue = 0, .alpha = 255 };
const color_green = Color{ .red = 0, .green = 255, .blue = 0, .alpha = 255 };
const color_blue = Color{ .red = 0, .green = 0, .blue = 255, .alpha = 255 };
const color_yellow = Color{ .red = 255, .green = 255, .blue = 0, .alpha = 255 };
const color_white = Color{ .red = 255, .green = 255, .blue = 255, .alpha = 255 };

const name = "zig-bare-metal-raspberry-pi";
const release_tag = "0.1";

const arm = @import("arm_assembly_code.zig");
const build_options = @import("build_options");
const builtin = @import("builtin");
const Bitmap = @import("video_core_frame_buffer.zig").Bitmap;
const Color = @import("video_core_frame_buffer.zig").Color;
const FrameBuffer = @import("video_core_frame_buffer.zig").FrameBuffer;
const hex = serial.hex;
const log = serial.log;
const panicf = arm.panicf;
const serial = @import("serial.zig");
const std = @import("std");
