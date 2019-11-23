export fn kernelMain() noreturn {
    if (build_options.subarch <= 7) {
        // set exception stacks
        asm volatile (
            \\ cps #0x17 // enter data abort mode
            \\ mov r0,#0x080000000
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
    }
    if (!build_options.is_qemu) {
        arm.setCntfrq(1 * 1000 * 1000);
    }
    arm.setBssToZero();
    arm.seconds.initScale(1);
    arm.milliseconds.initScale(1000);
    arm.microseconds.initScale(1000 * 1000);

    serial.init();
    log("\n{} {} ...", name, release_tag);

    fb.init();
    log("drawing logo ...");
    logo.init(&fb, &logo_bmp_file);
    logo.drawRect(logo.width, logo.height, 0, 0, 0, 0);

    icon.init(&fb, &icon_bmp_file);

    font_bmp.init(&fb, &font_bmp_file);
    font.init(&font_bmp, 7, 9, 32, 127);
    grid.init(&font, margin, 2 * (logo.height + margin));

    ble_activity.init();
    cycle_activity.init();
    pixel_banner_activity.init(logo.width, logo.height);
    serial_activity.init();
    status_activity.init();
    vchi_activity.init();

    while (true) {
        ble_activity.update();
        cycle_activity.update();
        pixel_banner_activity.update();
        serial_activity.update();
        status_activity.update();
        vchi_activity.update();
    }
}

const key_len_max = 20;
const BleTracker = struct {
    count: u32,
    key_buf: [key_len_max]u8,
    key: []u8,
    last_rssi: u8,
};

const trackers_len_max = 50;
const BleActivity = struct {
    messages_received: u32,
    discarded_count: u32,
    error_count: u32,
    max_read_run: u32,
    trackers_buf: [trackers_len_max]BleTracker,
    trackers: []BleTracker,
    grid: textGridOf(trackers_len_max + 1, 120),

    fn init(self: *BleActivity) void {
        if (build_options.is_qemu) {
            return;
        }
        self.messages_received = ble.init();
        self.trackers = self.trackers[0..0];
        self.grid.init(&font, fb.physical_width / 2, margin);
        self.grid.home();
        bleGridLine("count  rssi from address     mfr       data");
    }

    fn update(self: *BleActivity) void {
        if (build_options.is_qemu) {
            return;
        }
        nextMessage: while (ble.poll()) |buf| {
            if (!(buf.len >= 2)) {
                continue :nextMessage;
            }
            const subevent_code = buf[0];
            if (subevent_code == 0x02) {
                const num_reports = buf[1];
                if (num_reports == 1) {
                    if (!(buf.len >= 4 + 6 + 1)) {
                        continue :nextMessage;
                    }
                    const event_type = buf[2];
                    const address_type = buf[3];
                    const address = buf[4 .. 4 + 6];
                    const key = buf[2..math.min(2 + key_len_max, buf.len - 1)];
                    const data_length = buf[4 + 6];
                    if (!(4 + 6 + data_length + 1 == buf.len - 1)) {
                        continue :nextMessage;
                    }
                    const data_with_rssi = buf[4 + 6 + 1 ..];
                    const rssi: u8 = data_with_rssi[data_length];
                    const data = data_with_rssi[0..data_length];
                    var ad_len: u8 = undefined;
                    while (data.len > 0) : (data = data[ad_len..]) {
                        ad_len = data[0];
                        if (!(ad_len >= 2 and data.len >= 2 and ad_len <= data.len)) {
                            continue :nextMessage;
                        }
                        const ad_type = data[1];
                        const ad_data = data[2..ad_len];
                        if (ad_type == 0xff) {
                            if (!(ad_data.len >= 2)) {
                                break :nextMessage;
                            }
                            const mfr = @intCast(u16, ad_data[1]) << 8 | ad_data[0];
                            const mfr_data = ad_data[2..];
                            var i: u32 = 0;
                            while (i < self.trackers.len) : (i += 1) {
                                if (mem.eql(u8, self.trackers[i].key, key)) {
                                    self.trackers[i].count += 1;
                                    self.grid.move(i + 1, 0);
                                    bleGridSome("{:5}", self.trackers[i].count);
                                    if (rssi != self.trackers[i].last_rssi) {
                                        self.trackers[i].last_rssi = rssi;
                                        self.grid.move(i + 1, 7);
                                        bleGridSome("{:4}", rssi);
                                    }
                                    break;
                                }
                            }
                            if (i == self.trackers.len and self.trackers.len < trackers_len_max) {
                                self.trackers = self.trackers_buf[0 .. i + 1];
                                self.trackers[i].key = self.trackers[i].key_buf[0..key.len];
                                mem.copy(u8, self.trackers[i].key, key);
                                self.trackers[i].count = 1;
                                self.trackers[i].last_rssi = rssi;
                                self.grid.move(i + 1, 0);
                                bleGridSome("{:5}  {:4} {x} {} {x}", @as(u32, 1), rssi, key[0 .. 2 + 6], self.mfrToString(mfr), data);
                            }
                        }
                    }
                }
            }
        }
        self.messages_received = ble.messages_received;
        self.discarded_count = ble.discarded_count;
        self.error_count = ble.error_count;
        self.max_read_run = ble.max_read_run;
    }

    fn mfrToString(self: *BleActivity, mfr: u16) []u8 {
        if (mfr == 0x0006) {
            return &"Microsoft";
        } else if (mfr == 0x004c) {
            return &"Apple    ";
        } else if (mfr == 0x015d) {
            return &"Estimote ";
        } else if (mfr == 0x01da) {
            return &"Logitech ";
        } else if (mfr == 0x021a) {
            return &"Blue Spec";
        } else if (mfr == 0x0305) {
            return &"Swipp    ";
        } else if (mfr == 0x030f) {
            return &"Flic     ";
        } else if (mfr == 0xffff) {
            return &"Testing  ";
        } else {
            return &"Unknown  ";
        }
    }
};

const CycleActivity = struct {
    cycle_time: u32,
    last_cycle_start: u32,
    max_cycle_time: u32,

    fn init(self: *CycleActivity) void {
        self.cycle_time = 0;
        self.last_cycle_start = arm.microseconds.read();
        self.max_cycle_time = 0;
    }

    fn update(self: *CycleActivity) void {
        const new_cycle_start = arm.microseconds.read();
        const k = 1;
        const d = 10;
        self.cycle_time = (k * self.cycle_time + (d - k) * (new_cycle_start - self.last_cycle_start)) / d;
        self.last_cycle_start = new_cycle_start;
        self.max_cycle_time = math.max(self.cycle_time, self.max_cycle_time);
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

fn bleGridLine(comptime format: []const u8, args: ...) void {
    bleGridSome(format, args);
    ble_activity.grid.line("");
}
fn bleGridSome(comptime format: []const u8, args: ...) void {
    fmt.format({}, NoError, bleGridWrite, format, args) catch |e| switch (e) {};
}
fn bleGridWrite(context: void, bytes: []const u8) NoError!void {
    ble_activity.grid.write(bytes);
}

const StatusActivity = struct {
    prev_now: u32,

    fn init(self: *StatusActivity) void {
        self.prev_now = arm.seconds.read();
        tty.clearScreen();
        tty.setScrollingRegion(5, 999);
        tty.move(4, 1);
        log("keyboard input will be echoed below:");
        grid.home();
        gridLine("");
        if (build_options.is_qemu) {
            gridLine("fyi - qemu has no frame buffer cursor");
            gridLine("fyi - qemu has no tv remote controller");
        } else {
            gridLine("");
            gridLine("press a tv remote controller button!");
        }
    }

    fn update(self: *StatusActivity) void {
        const now = arm.seconds.read();
        if (now >= self.prev_now + 1) {
            const temperature = queries.getTemperature();
            tty.saveCursor();
            tty.hideCursor();
            tty.move(1, 1);
            tty.line("up {}s max cycle {}us temperature {}mC", arm.seconds.read(), cycle_activity.max_cycle_time, temperature);
            tty.restoreCursor();
            tty.showCursor();
            grid.home();
            gridLine("max {}us ble {} disc {} err {} fifo {}", cycle_activity.max_cycle_time, ble_activity.messages_received, ble_activity.discarded_count, ble_activity.error_count, ble_activity.max_read_run);
            self.prev_now = now;
        }
        grid.limitedUpdate(1, 10);
        ble_activity.grid.limitedUpdate(2, 10);
    }
};

const PixelBannerActivity = struct {
    width: u32,
    height: u32,
    color: Color,
    color32: u32,
    top: u32,
    x: u32,
    y: u32,

    fn init(self: *PixelBannerActivity, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
        self.color = color_yellow;
        self.color32 = fb.color32(self.color);
        self.top = height + margin;
        self.x = 0;
        self.y = self.top;
    }

    fn update(self: *PixelBannerActivity) void {
        const pixels_rendered_limit = 20;
        var pixels_rendered: u32 = 0;
        while (pixels_rendered < pixels_rendered_limit and self.x < self.width) : (pixels_rendered += 1) {
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

const SerialActivity = struct {
    fn init(self: *SerialActivity) void {}

    fn update(self: *SerialActivity) void {
        serial.loadOutputFifo();
        if (!serial.isReadByteReady()) {
            return;
        }
        const byte = serial.readByte();
        switch (byte) {
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
        if (build_options.is_qemu) {
            return;
        }
        self.vchi.init();
        self.cursor_x = fb.physical_width / 2;
        self.cursor_y = fb.physical_height / 2;
        fb.setCursor(&icon);
        fb.moveCursor(self.cursor_x, self.cursor_y);
    }

    fn update(self: *VchiActivity) void {
        if (build_options.is_qemu) {
            return;
        }
        while (self.vchi.cecButtonPressed()) |button_code| {
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
    if (build_options.subarch <= 7) {
        log("arm exception taken: entry number 0x{x}", entry_number);
        log("spsr  0x{x}", arm.spsr());
        log("cpsr  0x{x}", arm.cpsr());
        log("sp    0x{x}", arm.sp());
        log("sctlr 0x{x}", arm.sctlr());
    } else {
        var current_el = asm ("mrs %[current_el], CurrentEL"
            : [current_el] "=r" (-> usize)
        );
        var sctlr_el3 = asm ("mrs %[sctlr_el3], sctlr_el3"
            : [sctlr_el3] "=r" (-> usize)
        );
        var esr_el3 = asm ("mrs %[esr_el3], esr_el3"
            : [esr_el3] "=r" (-> usize)
        );
        var elr_el3 = asm ("mrs %[elr_el3], elr_el3"
            : [elr_el3] "=r" (-> usize)
        );
        var spsr_el3 = asm ("mrs %[spsr_el3], spsr_el3"
            : [spsr_el3] "=r" (-> usize)
        );
        var far_el3 = asm ("mrs %[far_el3], far_el3"
            : [far_el3] "=r" (-> usize)
        );
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
    }
    arm.hang("core 0 is now idle in arm exception handler (other cores were already idle from start up)");
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("main.zig pub fn panic(): {}", message);
}

var ble_activity: BleActivity = undefined;
var cycle_activity: CycleActivity = undefined;
var fb: FrameBuffer = undefined;
var font: Spritesheet = undefined;
var font_bmp: Bitmap = undefined;
var font_bmp_file = @embedFile("../assets/small_font.bmp");
var grid: textGridOf(10, 80) = undefined;
var icon: Bitmap = undefined;
var icon_bmp_file = @embedFile("../assets/zig-icon.bmp");
var last_cycle_start: u32 = undefined;
var logo: Bitmap = undefined;
var logo_bmp_file = @embedFile("../assets/zig-logo.bmp");
var pixel_banner_activity: PixelBannerActivity = undefined;
var serial_activity: SerialActivity = undefined;
var status_activity: StatusActivity = undefined;
var vchi_activity: VchiActivity = undefined;

const margin = 10;

const color_red = Color{ .red = 255, .green = 0, .blue = 0, .alpha = 255 };
const color_green = Color{ .red = 0, .green = 255, .blue = 0, .alpha = 255 };
const color_blue = Color{ .red = 0, .green = 0, .blue = 255, .alpha = 255 };
const color_yellow = Color{ .red = 255, .green = 255, .blue = 0, .alpha = 255 };
const color_white = Color{ .red = 255, .green = 255, .blue = 255, .alpha = 255 };

const name = "zig-bare-metal-raspberry-pi";
const release_tag = "0.4";

const arm = @import("arm_assembly_code.zig");
const assert = std.debug.assert;
const ble = @import("ble.zig");
const build_options = @import("build_options");
const builtin = @import("builtin");
const Bitmap = @import("video_core_frame_buffer.zig").Bitmap;
const Color = @import("video_core_frame_buffer.zig").Color;
const fmt = std.fmt;
const FrameBuffer = @import("video_core_frame_buffer.zig").FrameBuffer;
const literal = serial.literal;
const log = serial.log;
const math = std.math;
const mem = std.mem;
const queries = @import("video_core_queries.zig");
const panicf = arm.panicf;
const serial = @import("serial.zig");
const Spritesheet = @import("video_core_frame_buffer.zig").Spritesheet;
const std = @import("std");
const textGridOf = @import("text_grid.zig").textGridOf;
const tty = @import("terminal.zig");
const Vchi = @import("video_core_vchi.zig").Vchi;
