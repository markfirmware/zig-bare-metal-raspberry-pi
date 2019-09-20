pub fn callVideoCoreProperties(args: []PropertiesArg) void {
    if(args[args.len - 1].TagAndLength.tag != TAG_LAST_SENTINEL) {
        panicf("video core mailbox buffer missing last tag sentinel");
    }

    buf_index = 0;

    var buffer_length_in_bytes: u32 = 0;
    add(buffer_length_in_bytes);
    const BUFFER_REQUEST = 0;
    add(BUFFER_REQUEST);
    var next_tag_index = buf_index;
    for (args) |arg| {
        switch(arg) {
            PropertiesArg.TagAndLength => |tag_and_length| {
                if (tag_and_length.tag != 0) {
//                  log("prepare tag {x} length {}", tag_and_length.tag, tag_and_length.length);
                }
                buf_index = next_tag_index;
                add(tag_and_length.tag);
                if (tag_and_length.tag != TAG_LAST_SENTINEL) {
                    add(tag_and_length.length);
                    const TAG_REQUEST = 0;
                    add(TAG_REQUEST);
                    next_tag_index = buf_index + tag_and_length.length / 4;
                }
            },
            PropertiesArg.Out => {
            },
            PropertiesArg.In => |ptr| {
                add(ptr.*);
            },
            PropertiesArg.Set => |ptr| {
                add(ptr.*);
            },
        }
    }
    buffer_length_in_bytes = buf_index * 4;
    buf_index = 0;
    add(buffer_length_in_bytes);

    var buffer_pointer = @ptrToInt(&words);
    if (buffer_pointer & 0xF != 0) {
        panicf("video core mailbox buffer not aligned to 16 bytes");
    }
    const PROPERTY_CHANNEL = 8;
    const request = PROPERTY_CHANNEL | @intCast(u32, buffer_pointer);
    mailboxes[1].pushRequestBlocking(request);
//  log("pull mailbox response");
    mailboxes[0].pullResponseBlocking(request);

    buf_index = 0;
    check(buffer_length_in_bytes);
    const BUFFER_RESPONSE_OK = 0x80000000;
    check(BUFFER_RESPONSE_OK);
    next_tag_index = buf_index;
    for (args) |arg| {
        switch(arg) {
            PropertiesArg.TagAndLength => |tag_and_length| {
                if (tag_and_length.tag != 0) {
//                  log("parse   tag {x} length {}", tag_and_length.tag, tag_and_length.length);
                }
                buf_index = next_tag_index;
                check(tag_and_length.tag);
                if (tag_and_length.tag != TAG_LAST_SENTINEL) {
                    check(tag_and_length.length);
                    const TAG_RESPONSE_OK = 0x80000000;
                    check(TAG_RESPONSE_OK | tag_and_length.length);
                    next_tag_index = buf_index + tag_and_length.length / 4;
                }
            },
            PropertiesArg.Out => |ptr| {
                ptr.* = next();
            },
            PropertiesArg.In => {
            },
            PropertiesArg.Set => |ptr| {
                check(ptr.*);
            },
        }
    }
//  log("properties done");
}

var words: [1024]u32 align(16) = undefined;

pub fn out(ptr: *u32) PropertiesArg {
    return PropertiesArg{ .Out = ptr };
}

pub fn in(ptr: *u32) PropertiesArg {
    return PropertiesArg{ .In = ptr };
}

const TAG_LAST_SENTINEL = 0;
pub fn lastTagSentinel() PropertiesArg {
    return tag(TAG_LAST_SENTINEL, 0);
}

pub fn set(ptr: *u32) PropertiesArg {
    return PropertiesArg{ .Set = ptr };
}

pub fn tag(the_tag: u32, length: u32) PropertiesArg {
    return PropertiesArg{ .TagAndLength = TagAndLength{ .tag = the_tag, .length = length } };
}

pub const PropertiesArg = union(enum) {
    In: *u32,
    Out: *u32,
    Set: *u32,
    TagAndLength: TagAndLength,
};

const TagAndLength = struct {
    tag: u32,
    length: u32,
};

var buf_index: u32 = undefined;

fn check(word: u32) void {
    const was = next();
    if (was != word) {
        panicf("video core mailbox failed index {} was {}/{x} expected {}/{x}", buf_index - 1, was, was, word, word);
    }
}

fn add(item: u32) void {
    advance();
    words[buf_index - 1] = item;
}

fn next() u32 {
    advance();
    return words[buf_index - 1];
}

fn advance() void {
    if (buf_index < words.len) {
        buf_index += 1;
    } else {
        panicf("BufferExhausted");
    }
}

const arm = @import("arm_assembly_code.zig");
const log = @import("serial.zig").log;
const mailboxes = @import("video_core_mailboxes.zig").mailboxes;
const panicf = arm.panicf;
const std = @import("std");
