export fn kernelMain() noreturn {
    // set exception stacks
    asm volatile(
        \\ cps #0x17 // enter data abort mode
        \\ mov r0,#0x08000000
        \\ sub r0,0x10000
        \\ mov sp,r0
        \\
        \\ cps #0x1b // enter undefined instruction mode
        \\ mov r0,#0x08000000
        \\ sub r0,0x20000
        \\ mov sp,r0
        \\
        \\ cps #0x1f // back to system mode
    );
    arm.setVectorBaseAddressRegister(if (build_options.is_qemu) 0x11000 else 0x1000);
    if (!build_options.is_qemu) {
        arm.setCntfrq(1*1000*1000);
    }
    arm.setBssToZero();
    arm.seconds.initScale(1);
    arm.milliseconds.initScale(1000);
    arm.microseconds.initScale(1000*1000);

    serial.init();
    log("\n{} {} ...", name, release_tag);

    fb.init();
    log("drawing logo ...");
    logo.init(&fb, &logo_bmp_file);
    logo.drawRect(logo.width, logo.height, 0, 0, 0, 0);

    icon.init(&fb, &icon_bmp_file);

    font_bmp.init(&fb, &font_bmp_file);
    font.init(&font_bmp, 18, 32);
    grid.init(&font, margin, 2 * (logo.height + margin));

    cycle_activity.init();
    screen_activity.init(logo.width, logo.height);
    serial_activity.init();
    if (!build_options.is_qemu) {
        vchi_activity.init();
    }

    while (true) {
        cycle_activity.update();
        screen_activity.update();
        serial_activity.update();
        if (!build_options.is_qemu) {
            vchi_activity.update();
        }
    }
}

const CycleActivity = struct {
    cycle_time: u32,
    last_cycle_start: u32,

    fn init(self: *CycleActivity) void {
        self.cycle_time = 0;
        self.last_cycle_start = arm.microseconds.read();
    }

    fn update(self: *CycleActivity) void {
        const new_cycle_start = arm.microseconds.read();
        const k = 99;
        const d = 100;
        self.cycle_time = (k * self.cycle_time + (d - k) * (new_cycle_start - self.last_cycle_start)) / d;
        self.last_cycle_start = new_cycle_start;
    }
};

const ScreenActivity = struct {
    width: u32,
    height: u32,
    color: Color,
    color32: u32,
    top: u32,
    x: u32,
    y: u32,

    fn init(self: *ScreenActivity, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
        self.color = color_yellow;
        self.color32 = fb.color32(self.color);
        self.top = height + margin;
        self.x = 0;
        self.y = self.top;
    }

    fn update (self: *ScreenActivity) void {
        var batch: u32 = 0;
        while (batch < 20 and self.x < self.width) : (batch += 1) {
            fb.drawPixel32(self.x, self.y, self.color32);
            self.x += 1;
        }
        if (self.x == self.width) {
            self.x = 0;
            self.y += 1;
            if (self.y == self.top + self.height) {
                self.y = self.top;
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

const NoError = error{};
fn gridLine(comptime format: []const u8, args: ...) void {
    fmt.format({}, NoError, gridWrite, format, args) catch |e| switch (e) {};
    grid.line("");
}
fn gridWrite(context: void, bytes: []const u8) NoError!void {
    grid.write(bytes);
}

const SerialActivity = struct {
    prev_now: u32,

    fn init(self: *SerialActivity) void {
        self.prev_now = arm.seconds.read();
        tty.clearScreen();
        tty.setScrollingRegion(5, 999);
        tty.move(4, 1);
        log("keyboard input will be echoed below:");
        grid.home();
        gridLine("");
        if (build_options.is_qemu) {
            gridLine("qemu: no frame buffer cursor");
            gridLine("qemu: no tv remote controller");
        } else {
            gridLine("");
            gridLine("press a tv remote controller button!");
        }
    }

    fn update(self: *SerialActivity) void {
        const now = arm.seconds.read();
        if (now >= self.prev_now + 1) {
            const temperature = queries.getTemperature();
            tty.saveCursor();
            tty.hideCursor();
            tty.move(1, 1);
            tty.line("up {}s cycle {}us temperature {}mC", now, cycle_activity.cycle_time, temperature);
            tty.restoreCursor();
            tty.showCursor();
            grid.home();
            gridLine("up {}s cycle {}us temperature {}mC", now, cycle_activity.cycle_time, temperature);
            self.prev_now = now;
        }
        grid.limitedUpdate(1, 1);
        if (!serial.isReadByteReady()) {
            return;
        }
        const byte = serial.readByte();
        switch (byte) {
            '!' => {
                var x = @intToPtr(*u32, 2).*;
                log("ok {x}", x);
            },
            '\r' => {
                serial.writeText("\n");
            },
            else => serial.writeByteBlocking(byte),
        }
    }
};

const VchiActivity = struct {
    vchi: Vchi,
    cursor_x: u32,
    cursor_y: u32,

    fn init(self: *VchiActivity) void {
        self.vchi.init();
        self.cursor_x = fb.physical_width / 2;
        self.cursor_y = fb.physical_height / 2;
        fb.setCursor(&icon);
        fb.moveCursor(self.cursor_x, self.cursor_y);
        self.vchi.cecOpenNotificationService();
    }

    fn update(self: *VchiActivity) void {
        while (self.vchi.wasButtonPressedReceived()) {
            const button_code = self.vchi.receiveButtonPressedBlocking();
            grid.move(1, 0);
            gridLine("tv remote controller button code 0x{x}", button_code);
            gridLine("");
            var dx: i32 = 0;
            var dy: i32 = 0;
            if (button_code == 0x01) {
                dy = -1;
            } else if (button_code == 0x02) {
                dy = 1;
            } else if (button_code == 0x03) {
                dx = -1;
            } else if (button_code == 0x04) {
                dx = 1;
            }
            var new_cursor_x = self.cursor_x;
            var new_cursor_y = self.cursor_y;
            const scale = 64;
            const x = @intCast(i32, self.cursor_x) + dx * scale;
            if (x > 0 and x < @intCast(i32, fb.physical_width) - 1) {
                new_cursor_x = @intCast(u32, x);
            }
            const y = @intCast(i32, self.cursor_y) + dy * scale;
            if (y > 0 and y < @intCast(i32, fb.physical_height) - 1) {
                new_cursor_y = @intCast(u32, y);
            }
            if (new_cursor_x != self.cursor_x or new_cursor_y != self.cursor_y) {
                self.cursor_x = new_cursor_x;
                self.cursor_y = new_cursor_y;
                fb.moveCursor(self.cursor_x, self.cursor_y);
            }
        }
    }
};

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

fn exceptionHandler(entry_number: u32) noreturn {
    log("arm exception taken: entry number 0x{x}", entry_number);
    log("spsr  0x{x}", arm.spsr());
    log("cpsr  0x{x}", arm.cpsr());
    log("sp    0x{x}", arm.sp());
    log("sctlr 0x{x}", arm.sctlr());
    arm.hang("execution is now stopped in arm exception handler");
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("main.zig pub fn panic(): {}", message);
}

var cycle_activity: CycleActivity = undefined;
var fb: FrameBuffer = undefined;
var font: Spritesheet = undefined;
var font_bmp: Bitmap = undefined;
var font_bmp_file = @embedFile("../assets/font.bmp");
var grid: textGridOf(5, 40) = undefined;
var icon: Bitmap = undefined;
var icon_bmp_file = @embedFile("../assets/zig-icon.bmp");
var last_cycle_start: u32 = undefined;
var logo: Bitmap = undefined;
var logo_bmp_file = @embedFile("../assets/zig-logo.bmp");
var screen_activity: ScreenActivity = undefined;
var serial_activity: SerialActivity = undefined;
var vchi_activity: VchiActivity = undefined;

const margin = 10;

const color_red = Color{ .red = 255, .green = 0, .blue = 0, .alpha = 255 };
const color_green = Color{ .red = 0, .green = 255, .blue = 0, .alpha = 255 };
const color_blue = Color{ .red = 0, .green = 0, .blue = 255, .alpha = 255 };
const color_yellow = Color{ .red = 255, .green = 255, .blue = 0, .alpha = 255 };
const color_white = Color{ .red = 255, .green = 255, .blue = 255, .alpha = 255 };

const name = "zig-bare-metal-raspberry-pi";
const release_tag = "0.3";

const arm = @import("arm_assembly_code.zig");
const build_options = @import("build_options");
const builtin = @import("builtin");
const Bitmap = @import("video_core_frame_buffer.zig").Bitmap;
const Color = @import("video_core_frame_buffer.zig").Color;
const fmt = std.fmt;
const FrameBuffer = @import("video_core_frame_buffer.zig").FrameBuffer;
const log = serial.log;
const queries = @import("video_core_queries.zig");
const panicf = arm.panicf;
const serial = @import("serial.zig");
const Spritesheet = @import("video_core_frame_buffer.zig").Spritesheet;
const std = @import("std");
const textGridOf = @import("text_grid.zig").textGridOf;
const tty = @import("terminal.zig");
const Vchi = @import("video_core_vchi.zig").Vchi;
