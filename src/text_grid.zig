
pub fn textGridOf(rows: u32, columns: u32) type {
    var SomeTextGrid = struct {
        const Self = @This();
        font: *Spritesheet,
        fb_x: u32,
        fb_y: u32,
        pending_buf: [rows * columns]u8,
        pending_index: u32,
        rendered_buf: [rows * columns]u8,
        rendered_index: u32,

        fn write(self: *Self, bytes: []const u8) void {
            for (bytes) |c| {
                self.pending_buf[self.pending_index] = c;
                self.pending_index += 1;
                if (self.pending_index == self.pending_buf.len) {
                    self.pending_index = 0;
                }
            }
        }

        fn line(self: *Self, bytes: []const u8) void {
            self.write(bytes);
            const next_line_index = (self.pending_index + columns) / columns * columns;
            while (self.pending_index < next_line_index) : (self.pending_index += 1) {
                self.pending_buf[self.pending_index] = ' ';
            }
            if (self.pending_index == self.pending_buf.len) {
                self.pending_index = 0;
            }
        }

        fn home(self: *Self) void {
            self.move(0, 0);
        }

        fn move(self: *Self, row: u32, column: u32) void {
            self.pending_index = row * columns + column;
            if (self.pending_index >= self.pending_buf.len) {
                panicf("TextGrid move ({}, {}) does not fit in ({}, {})", row, column, rows, columns);
            }
        }

        fn limitedUpdate(self: *Self, render_limit: u32, scan_limit: u32) void {
            var scanned: u32 = 0;
            var rendered: u32 = 0;
            while (rendered < render_limit and scanned < scan_limit) : (scanned += 1) {
                 const pending = self.pending_buf[self.rendered_index];
                 if (pending != self.rendered_buf[self.rendered_index]) {
                     const row = self.rendered_index / columns;
                     const column = self.rendered_index - row * columns;
                     const fb_x = self.fb_x + column * self.font.sprite_width;
                     const fb_y = self.fb_y + row * self.font.sprite_height;
                     self.font.draw(pending, fb_x, fb_y);
                     self.rendered_buf[self.rendered_index] = pending;
                     rendered += 1;
                 }
                 self.rendered_index += 1;
                 if (self.rendered_index == self.rendered_buf.len) {
                     self.rendered_index = 0;
                 }
            }
        }

        fn init(self: *Self, font: *Spritesheet, fb_x: u32, fb_y: u32) void {
            self.font = font;
            self.fb_x = fb_x;
            self.fb_y = fb_y;
            self.pending_index = 0;
            self.rendered_index = 0;
            var i: u32 = 0;
            while(i < self.rendered_buf.len) : (i += 1) {
                self.rendered_buf[i] = ' ';
                self.pending_buf[i] = ' ';
            }
        }
    };
    return SomeTextGrid;
}

const arm = @import("arm_assembly_code.zig");
const math = @import("std").math;
const panicf = arm.panicf;
const Spritesheet = @import("video_core_frame_buffer.zig").Spritesheet;
