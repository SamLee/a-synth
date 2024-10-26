const std = @import("std");
const clap = @cImport(@cInclude("clap/clap.h"));
const Plugin = @import("plugin.zig").Plugin;
const log = std.log.scoped(.parameters);

pub const Params = struct {
    osc1: Wave = Wave.sine,
    osc2: Wave = Wave.sine,
    attackDuration: f64 = 0.001,
    attackTarget: f64 = 1,
    decayDuration: f64 = 0.001,
    decayTarget: f64 = 1,
    releaseDuration: f64 = 0.002,
    releaseTarget: f64 = 0,
    offset: f64 = 0,
    offset1: f64 = 0,
    highQuality: HighQuality = HighQuality.off,

    pub const Params = enum {
        osc1,
        osc2,
        attackDuration,
        attackTarget,
        decayDuration,
        decayTarget,
        releaseDuration,
        releaseTarget,
        offset,
        offset1,
        highQuality,
    };
    const Wave = enum { sine, siney, square, saw, triangle, noise };
    const HighQuality = enum { off, on };
};

pub fn handleEvent(event: clap.clap_event_param_value, params: *Params) void {
    const typeInfo = std.meta.fields(Params);
    inline for (typeInfo, 0..) |field, index| {
        if (event.param_id == index) {
            // Make a ref and dref it to update
            const param = &@field(params, field.name);
            switch (@typeInfo(@TypeOf(param.*))) {
                .Enum => {
                    const enumId: usize = @intFromFloat(event.value);
                    const newValue = @as(@TypeOf(param.*), @enumFromInt(enumId));
                    log.debug("updating {s} {} => {}", .{ field.name, param.*, newValue });
                    param.* = newValue;
                },
                .Float => {
                    log.debug("updating {s} {d:.2} => {d:.2}", .{ field.name, param.*, event.value });
                    param.* = event.value;
                },
                else => @panic(std.fmt.comptimePrint("TRIED TO UPDATED UNEXPECTED TYPE {}", .{field.type})),
            }
        }
    }
}

pub const extensionParams = struct {
    pub const extension = clap.clap_plugin_params{
        .count = count,
        .flush = flush,
        .get_info = get_info,
        .get_value = get_value,
        .value_to_text = value_to_text,
        .text_to_value = text_to_value,
    };

    fn count(_: [*c]const clap.clap_plugin) callconv(.C) u32 {
        return @typeInfo(Params.Params).Enum.fields.len;
    }

    fn flush(
        clap_plugin: [*c]const clap.clap_plugin,
        in: [*c]const clap.clap_input_events,
        _: [*c]const clap.clap_output_events,
    ) callconv(.C) void {
        const plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        const eventCount = in.*.size.?(in);
        var eventIndex: u32 = 0;

        while (eventIndex < eventCount) : (eventIndex += 1) {
            plugin.process_event(in.*.get.?(in, eventIndex));
        }
    }

    fn get_info(
        _: [*c]const clap.clap_plugin,
        param_index: u32,
        param_info: [*c]clap.clap_param_info,
    ) callconv(.C) bool {
        const param: Params.Params = @enumFromInt(param_index);
        switch (param) {
            .osc1 => {
                param_info.* = clap.clap_param_info{
                    .id = param_index,
                    .flags = clap.CLAP_PARAM_IS_ENUM | clap.CLAP_PARAM_IS_STEPPED | clap.CLAP_PARAM_IS_AUTOMATABLE,
                    .min_value = 0,
                    .max_value = @typeInfo(Params.Wave).Enum.fields.len - 1,
                };
                _ = std.fmt.bufPrint(&param_info.*.name, "Osc 1/Shape", .{}) catch unreachable;
                _ = std.fmt.bufPrint(&param_info.*.module, "Oscillator 1/", .{}) catch unreachable;
                return true;
            },
            .osc2 => {
                param_info.* = clap.clap_param_info{
                    .id = param_index,
                    .flags = clap.CLAP_PARAM_IS_ENUM | clap.CLAP_PARAM_IS_STEPPED | clap.CLAP_PARAM_IS_AUTOMATABLE,
                    .min_value = 0,
                    .max_value = @typeInfo(Params.Wave).Enum.fields.len - 1,
                };
                _ = std.fmt.bufPrint(&param_info.*.name, "Osc 2/Shape", .{}) catch unreachable;
                _ = std.fmt.bufPrint(&param_info.*.module, "Oscillator 2/", .{}) catch unreachable;
                return true;
            },
            .highQuality => {
                param_info.* = clap.clap_param_info{
                    .id = param_index,
                    .flags = clap.CLAP_PARAM_IS_ENUM | clap.CLAP_PARAM_IS_STEPPED | clap.CLAP_PARAM_IS_AUTOMATABLE,
                    .min_value = 0,
                    .max_value = @typeInfo(Params.HighQuality).Enum.fields.len - 1,
                };
                _ = std.fmt.bufPrint(&param_info.*.name, "High Quality", .{}) catch unreachable;
                _ = std.fmt.bufPrint(&param_info.*.module, "Quality", .{}) catch unreachable;
                return true;
            },
            .attackDuration, .decayDuration, .releaseDuration => {
                param_info.* = clap.clap_param_info{
                    .id = param_index,
                    .flags = clap.CLAP_PARAM_IS_AUTOMATABLE,
                    .min_value = 0.001,
                    .max_value = 30,
                };
                _ = std.fmt.bufPrint(&param_info.*.name, "{s}", .{@tagName(param)}) catch unreachable;
                _ = std.fmt.bufPrint(&param_info.*.module, "Envelope", .{}) catch unreachable;
                return true;
            },
            .attackTarget, .decayTarget, .releaseTarget => {
                param_info.* = clap.clap_param_info{
                    .id = param_index,
                    .flags = clap.CLAP_PARAM_IS_AUTOMATABLE,
                    .min_value = 0,
                    .max_value = 2,
                };
                _ = std.fmt.bufPrint(&param_info.*.name, "{s}", .{@tagName(param)}) catch unreachable;
                _ = std.fmt.bufPrint(&param_info.*.module, "Envelope", .{}) catch unreachable;
                return true;
            },
            .offset, .offset1 => {
                param_info.* = clap.clap_param_info{
                    .id = param_index,
                    .flags = clap.CLAP_PARAM_IS_AUTOMATABLE | clap.CLAP_PARAM_IS_STEPPED,
                    .min_value = -24,
                    .max_value = 24,
                };
                _ = std.fmt.bufPrint(&param_info.*.name, "{s}", .{@tagName(param)}) catch unreachable;
                _ = std.fmt.bufPrint(&param_info.*.module, "Oscillator", .{}) catch unreachable;
                return true;
            },
        }

        return false;
    }

    fn get_value(
        clap_plugin: [*c]const clap.clap_plugin,
        id: clap.clap_id,
        value: [*c]f64,
    ) callconv(.C) bool {
        const plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        const typeInfo = std.meta.fields(Params);
        inline for (typeInfo, 0..) |field, index| {
            if (id == index) {
                const param = @field(plugin.params, field.name);
                const paramValue: f64 = switch (@typeInfo(@TypeOf(param))) {
                    .Enum => @floatFromInt(@intFromEnum(param)),
                    .Float => param,
                    else => @panic(std.fmt.comptimePrint("UNEXPECTED TYPE {}", .{field})),
                };

                log.debug("getting value: {s} {d}", .{ field.name, paramValue });

                value.* = paramValue;
                return true;
            }
        }

        return false;
    }

    fn value_to_text(
        _: [*c]const clap.clap_plugin,
        id: clap.clap_id,
        value: f64,
        out: [*c]u8,
        size: u32,
    ) callconv(.C) bool {
        const buf = out[0..size];
        const param: Params.Params = @enumFromInt(id);
        switch (param) {
            Params.Params.osc1, .osc2 => {
                const enumId: usize = @intFromFloat(value);
                const wave: Params.Wave = @enumFromInt(enumId);
                _ = std.fmt.bufPrint(buf, "{s}", .{@tagName(wave)}) catch unreachable;
            },
            .highQuality => {
                const enumId: usize = @intFromFloat(value);
                const mode: Params.HighQuality = @enumFromInt(enumId);
                _ = std.fmt.bufPrint(buf, "{s}", .{@tagName(mode)}) catch unreachable;
            },
            Params.Params.attackDuration, Params.Params.decayDuration, Params.Params.releaseDuration => {
                _ = std.fmt.bufPrint(buf, "{d:.3}", .{value}) catch unreachable;
            },
            Params.Params.attackTarget, Params.Params.decayTarget, Params.Params.releaseTarget => {
                _ = std.fmt.bufPrint(buf, "{d:.3}", .{value}) catch unreachable;
            },
            Params.Params.offset, .offset1 => {
                _ = std.fmt.bufPrint(buf, "{d}", .{value}) catch unreachable;
            },
        }

        return true;
    }

    fn text_to_value(
        clap_plugin: [*c]const clap.clap_plugin,
        id: clap.clap_id,
        in: [*c]const u8,
        out: [*c]f64,
    ) callconv(.C) bool {
        const plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        const typeInfo = std.meta.fields(Params);
        inline for (typeInfo, 0..) |field, index| {
            if (id == index) {
                const param = @field(plugin.params, field.name);
                const string = std.mem.span(in);
                const value: f64 = switch (@typeInfo(@TypeOf(param))) {
                    .Enum => block: {
                        const enumValue = std.meta.stringToEnum(@TypeOf(param), string);
                        break :block @floatFromInt(@intFromEnum(enumValue.?));
                    },
                    .Float => std.fmt.parseFloat(f64, string) catch unreachable,
                    else => @panic(std.fmt.comptimePrint("UNEXPECTED TYPE {}", .{field})),
                };

                log.debug("converting text to value: {s} {s} => {d}", .{ field.name, string, value });
                out.* = value;

                return true;
            }
        }

        return false;
    }
};
