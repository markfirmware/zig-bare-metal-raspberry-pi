pub const mailboxes = [_]*volatile MailboxRegisters{ MailboxRegisters.init(0), MailboxRegisters.init(1) };

const MailboxRegisters = packed struct {
    push_pull_register: u32,
    unused1: u32,
    unused2: u32,
    unused3: u32,
    unused4: u32,
    unused5: u32,
    status_register: u32,
    unused6: u32,

    fn init(index: u32) *volatile MailboxRegisters {
        assert(@sizeOf(MailboxRegisters) == 0x20);
        if (index > 1) {
            panicf("mailbox index {} exceeds 1", index);
        }
        const MAILBOXES_OFFSET = 0xB880;
        return @intToPtr(*volatile MailboxRegisters, arm.PERIPHERAL_BASE + MAILBOXES_OFFSET + index * @sizeOf(MailboxRegisters));
    }

    fn pushRequestBlocking(this: *volatile MailboxRegisters, request: u32) void {
        const MAILBOX_IS_FULL = 0x80000000;
        this.blockWhile(MAILBOX_IS_FULL);
        arm.dsbSt();
        this.push_pull_register = request;
    }

    fn pullResponseBlocking(this: *volatile MailboxRegisters, request: u32) void {
        const MAILBOX_IS_EMPTY = 0x40000000;
        this.blockWhile(MAILBOX_IS_EMPTY);
        const response = this.push_pull_register;
        if (response != request) {
            panicf("buffer address and channel response was {x} expecting {x}", response, request);
        }
    }

    fn blockWhile(this: *volatile MailboxRegisters, condition: u32) void {
//      time.update();
//      const start = time.seconds;
        while (this.status_register & condition != 0) {
//          time.update();
//          if (time.seconds - start >= 0.1) {
//              panicf("time out waiting for video core mailbox");
//          }
        }
    }
};

const arm = @import("arm_assembly_code.zig");
const assert = std.debug.assert;
const panicf = arm.panicf;
const std = @import("std");
//const time = @import("time.zig");
