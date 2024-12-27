const std = @import("std");

const c_time_h = @cImport({
    @cInclude("time.h");
});

const time_t = c_time_h.time_t;
const tm_t = c_time_h.struct_tm;
//const gmtime = c_time_h.gmtime;
const localtime = c_time_h.localtime;
const strftime = c_time_h.strftime;

pub fn formatNanosecondTimestamp(buffer: []u8, timestamp_nanoseconds: i128) []const u8 {
    const timestamp_seconds: i128 = @divTrunc(timestamp_nanoseconds, 1_000_000_000);

    const time: time_t = @intCast(timestamp_seconds);

    //const tm: *const tm_t = gmtime(&time);
    const tm: *const tm_t = c_time_h.localtime(&time);

    const format = "%Y-%m-%d %H:%M:%S";

    const len = strftime(buffer.ptr, buffer.len, format, tm);

    const s = buffer[0..len];

    return s;
}

pub fn formatFileSize(buffer: []u8, size: u64) []const u8 {
    if (size > 1024) {
        return std.fmt.bufPrint(buffer, "{d} KiB", .{@divTrunc(size, 1024)}) catch unreachable;
    } else {
        return std.fmt.bufPrint(buffer, "{d} Bytes", .{size}) catch unreachable;
    }
}
