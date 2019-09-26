pub const FrameBuffer = struct {
    alignment: u32,
    alpha_mode: u32,
    depth: u32,
    physical_width: u32,
    physical_height: u32,
    pitch: u32,
    pixel_order: u32,
    address: u32,
    size: u32,
    virtual_height: u32,
    virtual_width: u32,
    virtual_offset_x: u32,
    virtual_offset_y: u32,
    overscan_top: u32,
    overscan_bottom: u32,
    overscan_left: u32,
    overscan_right: u32,
    words: [*]u32,
    bytes: [*]u8,
    fn clear(fb: *FrameBuffer, color: Color) void {
        var y: u32 = 0;
        while (y < fb.virtual_height) : (y += 1) {
            var x: u32 = 0;
            while (x < fb.virtual_width) : (x += 1) {
                fb.drawPixel(x, y, color);
            }
        }
    }

    fn drawPixel(fb: *FrameBuffer, x: u32, y: u32, color: Color) void {
        if (x >= fb.virtual_width or y >= fb.virtual_height) {
            panicf("frame buffer index {}, {} does not fit in {}x{}", x, y, fb.virtual_width, fb.virtual_height);
        }
        const offset = y * fb.pitch + x * 4;
        fb.bytes[offset + 0] = color.blue;
        fb.bytes[offset + 1] = color.green;
        fb.bytes[offset + 2] = color.red;
        fb.bytes[offset + 3] = @intCast(u8, 255 - @intCast(i32, color.alpha));
    }

    fn color32(fb: *FrameBuffer, color: Color) u32 {
        return (255 - @intCast(u32, color.alpha) << 24) | @intCast(u32, color.red) << 16 | @intCast(u32, color.green) << 8 | @intCast(u32, color.blue) << 0;
    }

    fn drawPixel32(fb: *FrameBuffer, x: u32, y: u32, color: u32) void {
        if (x >= fb.virtual_width or y >= fb.virtual_height) {
            panicf("frame buffer index {}, {} does not fit in {}x{}", x, y, fb.virtual_width, fb.virtual_height);
        }
        fb.words[y * fb.pitch / 4 + x] = color;
    }

    pub fn init(fb: *FrameBuffer) void {
        const width: u32 = 1920;
        const height: u32 = 1080;
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
            tag(TAG_ALLOCATE_FRAME_BUFFER, 8),
            in(&fb.alignment),
            out(&fb.address),
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

        if (fb.address == 0) {
            panicf("frame buffer address is zero");
        }
        fb.address &= 0x3FFFFFFF;
        fb.bytes = @intToPtr([*]u8, fb.address);
        fb.words = @intToPtr([*]u32, fb.address);
//      log("fb align {} addr {x} alpha {} pitch {} order {} size {} physical {}x{} virtual {}x{} offset {},{} overscan t {} b {} l {} r {}", fb.alignment, @ptrToInt(fb.bytes), fb.alpha_mode, fb.pitch, fb.pixel_order, fb.size, fb.physical_width, fb.physical_height, fb.virtual_width, fb.virtual_height, fb.virtual_offset_x, fb.virtual_offset_y, fb.overscan_top, fb.overscan_bottom, fb.overscan_left, fb.overscan_right);
    }
};

pub const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
};

pub const Bitmap = struct {
    frame_buffer: *FrameBuffer,
    pixel_array: [*]u8,
    width: u32,
    height: u32,

    fn drawRect(self: *Bitmap, width: u32, height: u32, x1: u32, y1: u32, x2: u32, y2: u32) void {
        var y: u32 = 0;
        while( y < height) : (y += 1) {
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                var argb = getUnalignedU32(self.pixel_array, ((self.height - 1 - y + y1) * self.width + x + x1) * @sizeOf(u32));
                argb = argb & 0xffffff | 0xff000000 - (argb & 0xff000000);
                self.frame_buffer.drawPixel32(x + x2, y + y2, argb);
            }
        }
    }

    pub fn init(bitmap: *Bitmap, frame_buffer: *FrameBuffer, file: []u8) void {
        bitmap.frame_buffer = frame_buffer;
        bitmap.pixel_array = @intToPtr([*]u8, @ptrToInt(file.ptr) + getUnalignedU32(file.ptr, 0x0A));
        bitmap.width = getUnalignedU32(file.ptr, 0x12);
        bitmap.height = getUnalignedU32(file.ptr, 0x16);
    }

    fn getUnalignedU32(base: [*]u8, offset: u32) u32 {
        var word: u32 =0;
        var i: u32 = 0;
        while (i <= 3) : (i += 1) {
            word >>= 8;
            word |= @intCast(u32, @intToPtr(*u8, @ptrToInt(base) + offset + i).*) << 24;
        }
        return word;
    }
};

const TAG_ALLOCATE_FRAME_BUFFER = 0x40001;

const TAG_GET_OVERSCAN = 0x4000A;
const TAG_GET_PITCH = 0x40008;

const TAG_SET_ALPHA_MODE = 0x48007;
const TAG_SET_DEPTH = 0x48005;
const TAG_SET_PHYSICAL_WIDTH_HEIGHT = 0x48003;
const TAG_SET_PIXEL_ORDER = 0x48006;
const TAG_SET_VIRTUAL_OFFSET = 0x48009;
const TAG_SET_VIRTUAL_WIDTH_HEIGHT = 0x48004;

const arm = @import("arm_assembly_code.zig");
const log = @import("serial.zig").log;
const panicf = arm.panicf;
use @import("video_core_properties.zig");
