const services_len_max = 2;
pub const Vchi = struct {
    cecs_service: *Service,
    cecn_service: *Service,
    is_connected: bool,
    rx_pos: u32,
    services_buf: [services_len_max]Service,
    services: []Service,
    slot_zero: *SlotZero,
    slots_address: u32,
    tx_pos: u32,

    pub fn init(self: *Vchi) void {
        self.rx_pos = 0;
        self.tx_pos = 0;
        self.is_connected = false;
        self.slots_address = @intCast(u32, @ptrToInt(&slots));
        self.slot_zero = @intToPtr(*SlotZero, self.slots_address);
        @memset(@intToPtr([*]u8, self.slots_address), 0, slots.len);
        self.slot_zero.init();
        var enable_status: u32 = undefined;
        var slots_bus_address = self.slots_address | 0xc0000000;
        callVideoCoreProperties(&[_]PropertiesArg{
            tag(TAG_ENABLE_VCHI, 4),
            in(&slots_bus_address),
            out(&enable_status),
        });
        if (enable_status != 0) {
            panicf("enable vchi failed 0x{x}", enable_status);
        }
        while (self.slot_zero.remote.initialized == 0) {}
        self.services = self.services_buf[0..0];
        self.cecn_service = self.addService("CECN", 1, 8, 0);
        self.cecs_service = self.addService("CECS", 2, 8, 0);
        self.connect();
        while (!self.is_connected) {
            _ = self.cecButtonPressed();
        }
        self.cecn_service.open(self);
        while (!self.cecn_service.is_open) {
            _ = self.cecButtonPressed();
        }
        self.cecs_service.open(self);
        while (!self.cecs_service.is_open) {
            _ = self.cecButtonPressed();
        }
        self.cecSetPassive();
    }

    fn addService(self: *Vchi, comptime name_str: [4]u8, local_port: u32, version: u32, min_version: u32) *Service {
        self.services = self.services_buf[0 .. self.services.len + 1];
        const i = self.services.len - 1;
        self.services[i] = Service.of(name_str, local_port, version, min_version);
        return &self.services[i];
    }

    fn sendMessage(self: *Vchi, id: u32, local_port: u32, remote_port: u32, args: []u32) void {
        const message_header = id << 24 | local_port << 12 | remote_port;
        const message_len = @truncate(u32, 4 * args.len);
        self.txU32(message_header);
        self.txU32(message_len);
        for (args) |arg| {
            self.txU32(arg);
        }
        arm.dsbSt();
        self.slot_zero.local.tx_pos += message_len + 8 + 7 & ~@as(u32, 7);
        arm.dsbSt();
        self.slot_zero.remote.rx_event_fired = 1;
        arm.dsbSt();
        arm.io(u32, DOORBELL_REGISTERS + DOORBELL2).* = 0;
    }

    fn connect(self: *Vchi) void {
        self.sendMessage(MESSAGE_CONNECT, 0, 0, &[_]u32{});
    }

    fn cecSetPassive(self: *Vchi) void {
        self.cecs_service.sendMessageData(self, &[_]u32{ 0x10, 0x01 });
    }

    fn cecButtonPressed(self: *Vchi) ?u8 {
        var button_code: ?u8 = null;
        if (self.rx_pos < self.slot_zero.remote.tx_pos) {
            const event = self.slot_zero.remote.peek(VchiMessage, self.rx_pos);
            if (event.isData() and event.localPort() == self.cecn_service.local_port) {
                const cec_event = self.slot_zero.remote.peek(CecNotificationEvent, self.rx_pos);
                if (cec_event.message_data_len == 20 and cec_event.cec_message_type == 0x04 and cec_event.cec_message_data_len == 3 and cec_event.cec_message_data[0] == 0x01) {
                    if (cec_event.cec_message_data[1] == 0x44) {
                        log("cec pressed     header 0x{x} length {} type 0x{x} data {x}", cec_event.message_header, cec_event.message_data_len, cec_event.cec_message_type, cec_event.dataSlice());
                        button_code = cec_event.buttonCode();
                    } else if (cec_event.cec_message_data[1] == 0x45) {
                        log("cec released    header 0x{x} length {} type 0x{x} data {x}", cec_event.message_header, cec_event.message_data_len, cec_event.cec_message_type, cec_event.dataSlice());
                    } else {
                        cec_event.log("skipped 1");
                    }
                } else {
                    cec_event.log("skipped 2");
                }
            } else if (event.isConnect()) {
                log("connect         header 0x{x}", event.message_header);
                self.is_connected = true;
            } else if (event.isOpenAck()) {
                log("open ack        header 0x{x} remote port 0x{x} local port 0x{x} length {}", event.message_header, event.message_data_len, event.remotePort(), event.localPort());
                for (self.services) |*service| {
                    if (event.localPort() == service.local_port) {
                        service.remote_port = event.remotePort();
                        service.is_open = true;
                    }
                }
            } else if (event.isPadding()) {
                log("skipped padding header 0x{x} length {}", event.message_header, event.message_data_len);
            } else {
                log("skipped unknown header 0x{x} length {} {x}", event.message_header, event.message_data_len, event.dataSlice());
            }
            self.updateRxPos();
        }
        return button_code;
    }

    fn updateRxPos(self: *Vchi) void {
        const event = self.slot_zero.remote.peek(VchiMessage, self.rx_pos);
        self.rx_pos += event.message_data_len + 8 + 7 & ~@as(u32, 7);
        if (self.rx_pos & SLOT_SIZE - 1 == 0) {
            const freed_slot_number = self.slot_zero.remote.tx_slot_queue[slotQueueIndex(self.rx_pos - 1)];
            self.slot_zero.remote.tx_slot_queue[self.slot_zero.remote.recycle_slot_queue_index & self.slot_zero.tx_slot_queue_length - 1] = freed_slot_number;
            arm.dsbSt();
            self.slot_zero.remote.recycle_slot_queue_index += 1;
            arm.dsbSt();
            self.slot_zero.remote.recycle_event_fired = 1;
        }
    }

    fn txU32(self: *Vchi, x: u32) void {
        @intToPtr(*u32, self.slot_zero.local.txAddress(self.tx_pos)).* = x;
        self.tx_pos += 4;
    }
};

const VchiMessage = struct {
    message_header: u32,
    message_data_len: u32,
    message_data: [64]u8,

    fn messageType(self: *VchiMessage) u32 {
        return (self.message_header & 0xff000000) >> 24;
    }

    fn localPort(self: *VchiMessage) u32 {
        return self.message_header & 0xfff;
    }

    fn remotePort(self: *VchiMessage) u32 {
        return (self.message_header & 0xfff000) >> 12;
    }

    fn isData(self: *VchiMessage) bool {
        return self.messageType() == MESSAGE_DATA;
    }

    fn isConnect(self: *VchiMessage) bool {
        return self.messageType() == MESSAGE_CONNECT and self.message_data_len == 0;
    }

    fn isPadding(self: *VchiMessage) bool {
        return self.messageType() == MESSAGE_PADDING;
    }

    fn isOpenAck(self: *VchiMessage) bool {
        return self.messageType() == MESSAGE_OPEN_ACK and self.message_data_len == 2;
    }

    fn dataSlice(self: *VchiMessage) []u8 {
        return self.message_data[0..self.message_data_len];
    }
};

const CecNotificationEvent = struct {
    message_header: u32,
    message_data_len: u32,
    cec_message_type: u16,
    cec_message_data_len: u16,
    cec_message_data: [16]u8,

    fn buttonCode(self: *CecNotificationEvent) u8 {
        return self.cec_message_data[2];
    }

    fn dataSlice(self: *CecNotificationEvent) []u8 {
        return self.cec_message_data[0..self.cec_message_data_len];
    }

    fn log(self: *CecNotificationEvent, text: []const u8) void {
        const route = self.cec_message_data[0];
        log("{} cec type {x} len {} initiator {x} destination {x} command {x:2} data {x}", text, self.cec_message_type, self.cec_message_data_len, (route & 0xf0) >> 4, route & 0x0f, self.cec_message_data[1], self.dataSlice());
    }
};

const QueueController = struct {
    initialized: u32,
    first_tx_slot_number: u32,
    last_tx_slot_number: u32,
    sync_slot_number: u32,
    rx_event_armed: u32,
    rx_event_fired: u32,
    rx_event_handle: u32,
    tx_pos: u32,
    recycle_event_armed: u32,
    recycle_event_fired: u32,
    recycle_event_handle: u32,
    recycle_slot_queue_index: u32,
    sync_rx_event_armed: u32,
    sync_rx_event__fired: u32,
    sync_rx_event_handle: u32,
    sync_release_event_armed: u32,
    sync_release_event_fired: u32,
    sync_release_event_handle: u32,
    tx_slot_queue: [SLOT_QUEUE_LENGTH]u32,
    extra: [EXTRA_LENGTH]u32,

    fn txAddress(self: *QueueController, byte_index: u32) u32 {
        const slot_number = self.tx_slot_queue[slotQueueIndex(byte_index)];
        const offset = byte_index & SLOT_SIZE - 1;
        const slots_address = @truncate(u32, @ptrToInt(self) & ~@as(u32, SLOT_SIZE) + 1);
        return slots_address + slot_number * SLOT_SIZE + offset;
    }

    fn peek(self: *QueueController, comptime t: type, byte_index: u32) *t {
        return @intToPtr(*t, self.txAddress(byte_index));
    }
};

fn slotQueueIndex(byte_index: u32) u32 {
    return (byte_index & ~@as(u32, SLOT_SIZE) + 1) >> SLOT_SIZE_WIDTH;
}

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

    fn init(self: *SlotZero) void {
        self.signature = makeName("VCHI");
        self.version_and_min_version = MIN_VERSION << 16 | VERSION;
        self.slot_zero_size = @sizeOf(SlotZero);
        self.slot_size = SLOT_SIZE;
        self.total_slots = TOTAL_SLOTS;
        self.tx_slot_queue_length = SLOT_QUEUE_LENGTH;

        self.local.initialized = 1;

        const mid_point = TOTAL_SLOTS / 2;

        self.remote.sync_slot_number = 1;
        self.remote.first_tx_slot_number = 2;
        self.remote.last_tx_slot_number = mid_point - 1;

        self.local.sync_slot_number = mid_point;
        self.local.first_tx_slot_number = mid_point + 2;
        self.local.last_tx_slot_number = TOTAL_SLOTS - 1;

        var queue_index: u32 = 0;
        var slot_number: u32 = self.local.first_tx_slot_number;
        while (slot_number <= self.local.last_tx_slot_number) {
            self.local.tx_slot_queue[queue_index] = slot_number;
            queue_index += 1;
            slot_number += 1;
        }
        self.local.recycle_slot_queue_index = queue_index;

        self.local.rx_event_armed = 1;
        self.local.recycle_event_armed = 1;
        self.local.sync_rx_event_armed = 1;
    }
};

const Service = struct {
    is_open: bool,
    local_port: u32,
    min_version: u32,
    name: u32,
    remote_port: u32,
    version: u32,

    fn of(comptime name_str: [4]u8, local_port: u32, version: u32, min_version: u32) Service {
        var service: Service = undefined;
        service.is_open = false;
        service.local_port = local_port;
        service.min_version = min_version;
        service.name = makeName(name_str);
        service.remote_port = undefined;
        service.version = version;
        return service;
    }

    fn open(self: *Service, vchi: *Vchi) void {
        const client_id = 0;
        vchi.sendMessage(MESSAGE_OPEN, self.local_port, @as(u32, 0), &[_]u32{ self.name, client_id, self.version, self.min_version });
    }

    fn sendMessageData(self: *Service, vchi: *Vchi, data: []u32) void {
        vchi.sendMessage(MESSAGE_DATA, self.local_port, self.remote_port, data);
    }
};

fn makeName(comptime s: [4]u8) u32 {
    return @as(u32, s[0]) << 24 | @as(u32, s[1]) << 16 | @as(u32, s[2]) << 8 | @as(u32, s[3]);
}

var slots: [SLOT_SIZE * TOTAL_SLOTS]u8 align(SLOT_SIZE) = undefined;

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
const MESSAGE_OPEN_ACK = 3;
const MESSAGE_DATA = 5;

const arm = @import("arm_assembly_code.zig");
const log = @import("serial.zig").log;
const mailboxes = @import("video_core_mailboxes.zig").mailboxes;
const mem = @import("std").mem;
const panicf = arm.panicf;

usingnamespace @import("video_core_properties.zig");
