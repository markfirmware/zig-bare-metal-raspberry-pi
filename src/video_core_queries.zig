pub fn getTemperature() u32 {
    var temperature_id: u32 = 0;
    var temperature: u32 = undefined;
    const TAG_GET_TEMPERATURE = 0x30006;
    callVideoCoreProperties(&[_]PropertiesArg{
        tag2(TAG_GET_TEMPERATURE, 4, 8),
        set(&temperature_id),
        out(&temperature),
    });
    return temperature;
}

usingnamespace @import("video_core_properties.zig");
