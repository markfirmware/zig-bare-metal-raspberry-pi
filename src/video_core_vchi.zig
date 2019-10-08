pub const Vchi = struct {
    put_index: u32,
    slots_address: u32,
    slot_zero: *SlotZero,
    rx_pos: u32,

    pub fn init(self: *Vchi) void {
        self.rx_pos = 0;
        self.slots_address = @intCast(u32, @ptrToInt(&slots));
        self.slot_zero = @intToPtr(*SlotZero, self.slots_address);
        @memset(@intToPtr([*]u8, self.slots_address), 0, slots.len);
        self.initSlotZero();
        var enable_status: u32 = undefined;
        var slots_bus_address = self.slots_address | 0xc0000000;
        callVideoCoreProperties(&[_]PropertiesArg{
            tag(TAG_ENABLE_VCHI, 4),
            in(&slots_bus_address),
            out(&enable_status),
            lastTagSentinel(),
        });
        if (enable_status != 0) {
            panicf("enable vchi failed 0x{x}", enable_status);
        }
        while (self.slot_zero.remote.initialized == 0) {
        }
        arm.delay(100*1000);
        self.connect();
    }

    fn addMessage(self: *Vchi, id: u32, local_port: u32, remote_port: u32, args: []u32) void {
        const size = u32(args.len) * 4;
        self.put_index = (self.slot_zero.local.first_tx_slot_number * SLOT_SIZE + self.slot_zero.local.tx_pos) / 4;
        self.put(id << 24 | local_port << 12 | remote_port);
        self.put(size);
        for (args) |arg| {
            self.put(arg);
        }
        arm.dsbSt();
        self.slot_zero.local.tx_pos += (size + 8 + 7) & ~u32(7);
        arm.dsbSt();
        self.slot_zero.remote.rx_event_fired = 1;
        arm.dsbSt();
        arm.io(u32, DOORBELL_REGISTERS + DOORBELL2).* = 0;
    }

    fn openService(self: *Vchi, service_name: u32, port: u12, version: u32, min_version: u32) void {
        const client_id = 0;
        self.addMessage(MESSAGE_OPEN, port, u32(0), &[_]u32{ service_name, client_id, version, min_version });
    }

    fn connect(self: *Vchi) void {
        self.addMessage(MESSAGE_CONNECT, 0, 0, &[_]u32{ });
    }

    fn cecOpenNotificationService(self: *Vchi) void {
        self.openService(name("CECN"), 1, 8, 0);
    }

    fn initSlotZero(self: *Vchi) void {
        self.slot_zero.signature = name("VCHI");
        self.slot_zero.version_and_min_version = (MIN_VERSION << 16) | VERSION;
        self.slot_zero.slot_zero_size = @sizeOf(SlotZero);
        self.slot_zero.slot_size = SLOT_SIZE;
        self.slot_zero.total_slots = TOTAL_SLOTS;
        self.slot_zero.tx_slot_queue_length = SLOT_QUEUE_LENGTH;

        self.slot_zero.local.initialized = 1;

        const mid_point = TOTAL_SLOTS / 2;

        self.slot_zero.remote.sync_slot_number = 1;
        self.slot_zero.remote.first_tx_slot_number = 2;
        self.slot_zero.remote.last_tx_slot_number = mid_point - 1;

        self.slot_zero.local.sync_slot_number = mid_point;
        self.slot_zero.local.first_tx_slot_number = mid_point + 2;
        self.slot_zero.local.last_tx_slot_number = TOTAL_SLOTS - 1;

        var queue_index: u32 = 0;
        var slot_number: u32 = self.slot_zero.local.first_tx_slot_number;
        while (slot_number <= self.slot_zero.local.last_tx_slot_number) {
            self.slot_zero.local.tx_slot_queue[queue_index] = slot_number;
            queue_index += 1;
            slot_number += 1;
        }
        self.slot_zero.local.recycle_slot_queue_index = queue_index;

        self.slot_zero.local.rx_event_armed = 1;
        self.slot_zero.local.recycle_event_armed = 1;
        self.slot_zero.local.sync_rx_event_armed = 1;
    }

    fn wasButtonPressedReceived(self: *Vchi) bool {
        if (self.rx_pos < self.slot_zero.remote.tx_pos) {
            const message_header = self.peekWord(0);
            const message_data_length = self.peekWord(1);
            const cec_message_id = self.peekWord(2);
            if (message_header & 0xff000fff == 0x05000001 and message_data_length == 20 and cec_message_id == 0x30004) {
                return true;
            } else if (message_header == MESSAGE_PADDING) {
                self.updateRxPos();
            } else {
                self.updateRxPos();
            }
        }
        return false;
    }

    fn receiveButtonPressedBlocking(self: *Vchi) u32 {
        while (!self.wasButtonPressedReceived()) {
        }
        const button_code = (self.peekWord(3) & 0x00ff0000) >> 16;
        self.updateRxPos();
        return button_code;
    }

    fn updateRxPos(self: *Vchi) void {
        const message_data_length = self.peekWord(1);
        self.rx_pos += (message_data_length + 8 + 7) & ~u32(7);
        if (self.rx_pos & (SLOT_SIZE - 1) == 0) {
            const freed_slot_number = self.slot_zero.remote.tx_slot_queue[slotIndex(self.rx_pos - 1)];
            self.slot_zero.remote.tx_slot_queue[self.slot_zero.remote.recycle_slot_queue_index & (self.slot_zero.tx_slot_queue_length - 1)] = freed_slot_number;
            arm.dsbSt();
            self.slot_zero.remote.recycle_slot_queue_index += 1;
            arm.dsbSt();
            self.slot_zero.remote.recycle_event_fired = 1;
        }
    }

    fn slotIndex(byte_index: u32) u32 {
        return (byte_index & (~u32(SLOT_SIZE) + 1)) >> SLOT_SIZE_WIDTH;
    }

    fn peekWord(self: *Vchi, at: u32) u32 {
        const byte_index = self.rx_pos + at * 4;
        const slot_queue_index = slotIndex(byte_index);
        const offset = byte_index & (SLOT_SIZE - 1);
        const slot_number = self.slot_zero.remote.tx_slot_queue[slot_queue_index];
        const word = @intToPtr(*u32, self.slots_address + slot_number * SLOT_SIZE + offset).*;
        return word;
    }

    fn wasWordReceived(self: *Vchi) bool {
        return self.rx_pos < self.slot_zero.remote.tx_pos;
    }

    fn receiveWord(self: *Vchi) u32 {
        const word = @intToPtr(*u32, self.slots_address + self.slot_zero.remote.first_tx_slot_number * SLOT_SIZE + self.rx_pos).*;
        self.rx_pos += 4;
        return word;
    }

    fn getAt(self: *Vchi, i: usize) u32 {
        return @intToPtr(*u32, self.slots_address + i * 4).*;
    }

    fn putAt(self:*Vchi, i: u32, x: u32) void {
        @intToPtr(*u32, self.slots_address + i * 4).* = x;
    }

    fn put(self: *Vchi, x: u32) void {
        self.putAt(self.put_index, x);
        self.put_index += 1;
    }
};

const QueueController = struct {
    initialized: u32,
    first_tx_slot_number: u32,
    last_tx_slot_number: u32,
    sync_slot_number: u32,
    rx_event_armed: u32, rx_event_fired: u32, rx_event_handle: u32,
    tx_pos: u32,
    recycle_event_armed: u32, recycle_event_fired: u32, recycle_event_handle: u32,
    recycle_slot_queue_index: u32,
    sync_rx_event_armed: u32, sync_rx_event__fired: u32, sync_rx_event_handle: u32,
    sync_release_event_armed: u32, sync_release_event_fired: u32, sync_release_event_handle: u32,
    tx_slot_queue: [SLOT_QUEUE_LENGTH]u32,
    extra: [EXTRA_LENGTH]u32,
};

const SlotZero = struct {
    signature: u32,
    version_and_min_version: u32,
    slot_zero_size: u32,
    slot_size: u32,
    total_slots: u32,
    tx_slot_queue_length: u32,
    extra: [2]u32,
    remote: QueueController,
    local: QueueController,
    slots_use_count_and_release_count: [TOTAL_SLOTS]u32,
};

fn name(comptime s: [4]u8) u32 {
    return u32(s[0]) << 24 | u32(s[1]) << 16 | u32(s[2]) << 8 | u32(s[3]);
}

var slots: [SLOT_SIZE * TOTAL_SLOTS]u8 align(SLOT_SIZE)= undefined;

const DOORBELL_REGISTERS = 0xB840;
const DOORBELL2 = 0x8;

const TAG_ENABLE_VCHI = 0x48010;

const SLOT_SIZE = 4096;
const SLOT_SIZE_WIDTH = 12;

const VERSION = 8;
const MIN_VERSION = 3;

const SLOT_QUEUE_LENGTH = 64;
const TOTAL_SLOTS = 128;
const EXTRA_LENGTH = 11;

const MESSAGE_PADDING = 0;
const MESSAGE_CONNECT = 1;
const MESSAGE_OPEN = 2;
const MESSAGE_DATA = 5;

const arm = @import("arm_assembly_code.zig");
const mailboxes = @import("video_core_mailboxes.zig").mailboxes;
const mem = @import("std").mem;
const panicf = arm.panicf;

use @import("video_core_properties.zig");
