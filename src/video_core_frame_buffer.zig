pub const FrameBuffer = struct {
    alignment: u32,
    alpha_mode: u32,
    depth: u32,
    physical_width: u32,
    physical_height: u32,
    pitch: u32,
    pixel_order: u32,
    bytes: [*]u8,
    words: [*]u32,
    size: u32,
    virtual_height: u32,
    virtual_width: u32,
    virtual_offset_x: u32,
    virtual_offset_y: u32,
    overscan_top: u32,
    overscan_bottom: u32,
    overscan_left: u32,
    overscan_right: u32,

    fn clear(fb: *FrameBuffer, color: Color) void {
        const color32: u32 = self.color32(Color);
        var y: u32 = 0;
        while (y < fb.virtual_height) : (y += 1) {
            var x: u32 = 0;
            while (x < fb.virtual_width) : (x += 1) {
                fb.drawPixel32(x, y, color32);
            }
        }
    }

    fn drawPixel(fb: *FrameBuffer, x: u32, y: u32, color: Color) void {
        drawPixel32(x, y, fb.color32(color));
    }

    fn color32(fb: *FrameBuffer, color: Color) u32 {
        return 255 - @intCast(u32, color.alpha) << 24 | @intCast(u32, color.red) << 16 | @intCast(u32, color.green) << 8 | @intCast(u32, color.blue) << 0;
    }

    fn drawPixel32(fb: *FrameBuffer, x: u32, y: u32, color: u32) void {
        if (x >= fb.virtual_width or y >= fb.virtual_height) {
            panicf("frame buffer index {}, {} does not fit in {}x{}", x, y, fb.virtual_width, fb.virtual_height);
        }
        fb.words[y * fb.pitch / 4 + x] = color;
    }

    pub fn setCursor(self: *FrameBuffer, bitmap: *Bitmap) void {
        var width: u32 = CURSOR_WIDTH;
        var height: u32 = CURSOR_HEIGHT;
        var unused: u32 = 0;
        var pointer_to_pixels = @truncate(u32, @ptrToInt(&cursor));
        var hot_spot_x: u32 = 0;
        var hot_spot_y: u32 = 0;
        var status: u32 = undefined;
        var i: u32 = 0;
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                if (x < bitmap.width and y < bitmap.height) {
                    cursor[i] = bitmap.getPixel32(x, y);
                } else {
                    cursor[i] = 0x00000000;
                }
                i += 1;
            }
        }
        callVideoCoreProperties(&[_]PropertiesArg{
            tag2(TAG_SET_CURSOR_INFO, 24, 4),
            in(&width),
            in(&height),
            in(&unused),
            in(&pointer_to_pixels),
            in(&hot_spot_x),
            in(&hot_spot_y),
            out(&status),
        });
        if (status != 0) {
            panicf("could not set frame buffer cursor");
        }
    }

    pub fn moveCursor(self: *FrameBuffer, x: u32, y: u32) void {
        var enable: u32 = 1;
        var x_pos = x;
        var y_pos = y;
        var flags: u32 = 1;
        var status: u32 = undefined;
        callVideoCoreProperties(&[_]PropertiesArg{
            tag2(TAG_SET_CURSOR_STATE, 16, 4),
            in(&enable),
            in(&x_pos),
            in(&y_pos),
            in(&flags),
            out(&status),
        });
        if (status != 0) {
            panicf("could not move frame buffer cursor");
        }
    }

    pub fn init(fb: *FrameBuffer) void {
        var width: u32 = if (build_options.is_qemu) 800 else 1920;
        var height: u32 = if (build_options.is_qemu) 600 else 1080;
        fb.alignment = 256;
        fb.physical_width = width;
        fb.physical_height = height;
        fb.virtual_width = width;
        fb.virtual_height = height;
        fb.virtual_offset_x = 0;
        fb.virtual_offset_y = 0;
        fb.depth = 32;
        fb.pixel_order = 0;
        fb.alpha_mode = 0;

        callVideoCoreProperties(&[_]PropertiesArg{
            tag2(TAG_ALLOCATE_FRAME_BUFFER, 4, 8),
            in(&fb.alignment),
            out(@ptrCast(*u32, &fb.bytes)),
            out(&fb.size),
            tag(TAG_SET_DEPTH, 4),
            set(&fb.depth),
            tag(TAG_SET_PHYSICAL_WIDTH_HEIGHT, 8),
            set(&fb.physical_width),
            set(&fb.physical_height),
            tag(TAG_SET_PIXEL_ORDER, 4),
            set(&fb.pixel_order),
            tag(TAG_SET_VIRTUAL_WIDTH_HEIGHT, 8),
            set(&fb.virtual_width),
            set(&fb.virtual_height),
            tag(TAG_SET_VIRTUAL_OFFSET, 8),
            set(&fb.virtual_offset_x),
            set(&fb.virtual_offset_y),
            tag(TAG_SET_ALPHA_MODE, 4),
            set(&fb.alpha_mode),
            tag(TAG_GET_PITCH, 4),
            out(&fb.pitch),
            tag(TAG_GET_OVERSCAN, 16),
            out(&fb.overscan_top),
            out(&fb.overscan_bottom),
            out(&fb.overscan_left),
            out(&fb.overscan_right),
        });

        if (@ptrToInt(fb.bytes) == 0) {
            panicf("frame buffer pointer is zero");
        }
        fb.bytes = @intToPtr([*]u8, @ptrToInt(fb.bytes) & 0x3FFFFFFF);
        fb.words = @intToPtr([*]u32, @ptrToInt(fb.bytes));
        //      log("fb align {} addr {x} alpha {} pitch {} order {} size {} physical {}x{} virtual {}x{} offset {},{} overscan t {} b {} l {} r {}", fb.alignment, @ptrToInt(fb.bytes), fb.alpha_mode, fb.pitch, fb.pixel_order, fb.size, fb.physical_width, fb.physical_height, fb.virtual_width, fb.virtual_height, fb.virtual_offset_x, fb.virtual_offset_y, fb.overscan_top, fb.overscan_bottom, fb.overscan_left, fb.overscan_right);
    }
};

pub const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
};

pub const Spritesheet = struct {
    bitmap: *Bitmap,
    columns: u32,
    max: u32,
    min: u32,
    rows: u32,
    sprite_height: u32,
    sprite_width: u32,

    fn init(self: *Spritesheet, bitmap: *Bitmap, sprite_width: u32, sprite_height: u32, min: u32, max: u32) void {
        self.bitmap = bitmap;
        self.sprite_width = sprite_width;
        self.sprite_height = sprite_height;
        self.rows = bitmap.height / sprite_height;
        self.columns = bitmap.width / sprite_width;
        self.min = min;
        self.max = max;
    }

    fn draw(self: Spritesheet, index: u32, fb_x: u32, fb_y: u32) void {
        assert(index >= self.min and index <= self.max);
        const entry = index - self.min;
        const row = entry / self.columns;
        const column = entry - row * self.columns;
        assert(row < self.rows);
        assert(column < self.columns);
        const sheet_x = column * self.sprite_width;
        const sheet_y = row * self.sprite_height;
        self.bitmap.drawRect(self.sprite_width, self.sprite_height, sheet_x, sheet_y, fb_x, fb_y);
    }
};

pub const Bitmap = struct {
    frame_buffer: *FrameBuffer,
    pixel_array: [*]u8,
    width: u32,
    height: u32,

    fn init(bitmap: *Bitmap, frame_buffer: *FrameBuffer, file: [*]u8) void {
        bitmap.frame_buffer = frame_buffer;
        bitmap.pixel_array = @intToPtr([*]u8, @ptrToInt(file) + arm.getUnalignedU32(file, 0x0A));
        bitmap.width = arm.getUnalignedU32(file, 0x12);
        bitmap.height = arm.getUnalignedU32(file, 0x16);
    }

    fn getPixel32(self: *Bitmap, x: u32, y: u32) u32 {
        return arm.getUnalignedU32(self.pixel_array, ((self.height - 1 - y) * self.width + x) * 4);
    }

    fn drawRect(self: *Bitmap, width: u32, height: u32, x1: u32, y1: u32, x2: u32, y2: u32) void {
        var y: u32 = 0;
        while (y < height) : (y += 1) {
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                self.frame_buffer.drawPixel32(x + x2, y + y2, self.getPixel32(x + x1, y + y1));
            }
        }
    }
};

const CURSOR_WIDTH = 16;
const CURSOR_HEIGHT = 16;
var cursor: [CURSOR_WIDTH * CURSOR_HEIGHT]u32 = undefined;

const TAG_ALLOCATE_FRAME_BUFFER = 0x40001;

const TAG_GET_OVERSCAN = 0x4000A;
const TAG_GET_PITCH = 0x40008;

const TAG_SET_ALPHA_MODE = 0x48007;
const TAG_SET_CURSOR_INFO = 0x8010;
const TAG_SET_CURSOR_STATE = 0x8011;
const TAG_SET_DEPTH = 0x48005;
const TAG_SET_PHYSICAL_WIDTH_HEIGHT = 0x48003;
const TAG_SET_PIXEL_ORDER = 0x48006;
const TAG_SET_VIRTUAL_OFFSET = 0x48009;
const TAG_SET_VIRTUAL_WIDTH_HEIGHT = 0x48004;

const arm = @import("arm_assembly_code.zig");
const assert = std.debug.assert;
const build_options = @import("build_options");
const log = @import("serial.zig").log;
const panicf = arm.panicf;
const std = @import("std");
usingnamespace @import("video_core_properties.zig");
