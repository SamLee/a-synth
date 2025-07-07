const std = @import("std");
const clap = @cImport(@cInclude("clap/clap.h"));
const Plugin = @import("plugin.zig").Plugin;
const log = std.log.scoped(.parameters);

pub const Params = struct {
    osc1: Parameter(Wave) = Parameter(Wave){
        .value = Wave.sine,
        .meta = ParamMeta{
            .name = "Osc 1/Shape",
            .module = "Oscillator 1/",
            .displayFormat = "{s}",
            .min = 0,
            .max = @typeInfo(Wave).@"enum".fields.len - 1,
            .flags = clap.CLAP_PARAM_IS_ENUM | clap.CLAP_PARAM_IS_STEPPED | clap.CLAP_PARAM_IS_AUTOMATABLE,
        },
    },
    osc2: Parameter(Wave) = Parameter(Wave){
        .value = Wave.sine,
        .meta = ParamMeta{
            .name = "Osc 2/Shape",
            .module = "Oscillator 2/",
            .displayFormat = "{s}",
            .min = 0,
            .max = @typeInfo(Wave).@"enum".fields.len - 1,
            .flags = clap.CLAP_PARAM_IS_ENUM | clap.CLAP_PARAM_IS_STEPPED | clap.CLAP_PARAM_IS_AUTOMATABLE,
        },
    },
    attackDuration: Parameter(f64) = Parameter(f64){
        .value = 0.001,
        .meta = ParamMeta{
            .name = "Attack Duration",
            .module = "Envelope",
            .displayFormat = "{d:.3}s",
            .min = 0.001,
            .max = 30,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE,
        },
    },
    attackTarget: Parameter(f64) = Parameter(f64){
        .value = 1,
        .meta = ParamMeta{
            .name = "Attack Target",
            .module = "Envelope",
            .displayFormat = "{d:.3}x",
            .min = 0,
            .max = 2,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE,
        },
    },
    decayDuration: Parameter(f64) = Parameter(f64){
        .value = 0.001,
        .meta = ParamMeta{
            .name = "Decay Duration",
            .module = "Envelope",
            .displayFormat = "{d:.3}s",
            .min = 0.001,
            .max = 30,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE,
        },
    },
    decayTarget: Parameter(f64) = Parameter(f64){
        .value = 1,
        .meta = ParamMeta{
            .name = "Decay Target",
            .module = "Envelope",
            .displayFormat = "{d:.3}x",
            .min = 0,
            .max = 2,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE,
        },
    },
    releaseDuration: Parameter(f64) = Parameter(f64){
        .value = 0.002,
        .meta = ParamMeta{
            .name = "Release Duration",
            .module = "Envelope",
            .displayFormat = "{d:.3}s",
            .min = 0.001,
            .max = 30,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE,
        },
    },
    releaseTarget: Parameter(f64) = Parameter(f64){
        .value = 0,
        .meta = ParamMeta{
            .name = "Release Target",
            .module = "Envelope",
            .displayFormat = "{d:.3}x",
            .min = 0,
            .max = 2,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE,
        },
    },
    offset1: Parameter(f64) = Parameter(f64){
        .value = 0,
        .meta = ParamMeta{
            .name = "Osc 1/Offset",
            .module = "Oscillator 1/",
            .displayFormat = "{d}",
            .min = -24,
            .max = 24,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE | clap.CLAP_PARAM_IS_STEPPED,
        },
    },
    offset2: Parameter(f64) = Parameter(f64){
        .value = 0,
        .meta = ParamMeta{
            .name = "Osc 2/Offset",
            .module = "Oscillator 2/",
            .displayFormat = "{d}",
            .min = -24,
            .max = 24,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE | clap.CLAP_PARAM_IS_STEPPED,
        },
    },
    highQuality: Parameter(HighQuality) = Parameter(HighQuality){
        .value = HighQuality.off,
        .meta = ParamMeta{
            .name = "High Quality",
            .module = "Quality",
            .displayFormat = "{s}",
            .min = 0,
            .max = @typeInfo(HighQuality).@"enum".fields.len - 1,
            .flags = clap.CLAP_PARAM_IS_ENUM | clap.CLAP_PARAM_IS_STEPPED | clap.CLAP_PARAM_IS_AUTOMATABLE,
        },
    },
    vol1: Parameter(f64) = Parameter(f64){
        .value = 100,
        .meta = ParamMeta{
            .name = "Osc 1/Volume",
            .module = "Oscillator 1/",
            .displayFormat = "{d}%",
            .min = 0,
            .max = 200,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE | clap.CLAP_PARAM_IS_STEPPED,
        },
    },
    vol2: Parameter(f64) = Parameter(f64){
        .value = 100,
        .meta = ParamMeta{
            .name = "Osc 2/Volume",
            .module = "Oscillator 2/",
            .displayFormat = "{d}%",
            .min = 0,
            .max = 200,
            .flags = clap.CLAP_PARAM_IS_AUTOMATABLE | clap.CLAP_PARAM_IS_STEPPED,
        },
    },

    const Wave = enum { sine, siney, square, saw, triangle, noise };
    const HighQuality = enum { off, on };

    const ParamMeta = struct {
        name: []const u8,
        module: []const u8,
        displayFormat: []const u8 = "{}",
        flags: u32,
        min: f64,
        max: f64,
    };

    fn Parameter(comptime T: type) type {
        return struct {
            value: T,
            meta: ParamMeta,
        };
    }
};

pub fn handleEvent(event: clap.clap_event_param_value, params: *Params) void {
    const typeInfo = std.meta.fields(Params);
    inline for (typeInfo, 0..) |field, index| {
        if (event.param_id == index) {
            const param = &@field(params, field.name);
            const value = param.*.value;
            switch (@typeInfo(@TypeOf(value))) {
                .@"enum" => {
                    const enumId: usize = @intFromFloat(event.value);
                    const newValue = @as(@TypeOf(value), @enumFromInt(enumId));
                    log.debug("updating {s} {} => {}", .{ field.name, value, newValue });
                    param.*.value = newValue;
                },
                .float => {
                    log.debug("updating {s} {d:.2} => {d:.2}", .{ field.name, value, event.value });
                    param.*.value = event.value;
                },
                else => @compileError(std.fmt.comptimePrint("tried to update unexpected type {}", .{field.type})),
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
        return std.meta.fields(Params).len;
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
        clap_plugin: [*c]const clap.clap_plugin,
        param_index: u32,
        param_info: [*c]clap.clap_param_info,
    ) callconv(.C) bool {
        const plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        const typeInfo = std.meta.fields(Params);
        inline for (typeInfo, 0..) |field, index| {
            if (param_index == index) {
                const param = @field(plugin.params, field.name);

                log.debug("getting param info: {s}", .{field.name});
                param_info.* = clap.clap_param_info{
                    .id = param_index,
                    .flags = param.meta.flags,
                    .min_value = param.meta.min,
                    .max_value = param.meta.max,
                };
                _ = std.fmt.bufPrint(&param_info.*.name, "{s}", .{param.meta.name}) catch unreachable;
                _ = std.fmt.bufPrint(&param_info.*.module, "{s}", .{param.meta.module}) catch unreachable;
                return true;
            }
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
                const paramValue: f64 = switch (@typeInfo(@TypeOf(param.value))) {
                    .@"enum" => @floatFromInt(@intFromEnum(param.value)),
                    .float => param.value,
                    else => @compileError(std.fmt.comptimePrint("UNEXPECTED TYPE {}", .{field.type})),
                };

                log.debug("getting value: {s} {d}", .{ field.name, paramValue });

                value.* = paramValue;
                return true;
            }
        }

        return false;
    }

    fn value_to_text(
        clap_plugin: [*c]const clap.clap_plugin,
        id: clap.clap_id,
        value: f64,
        out: [*c]u8,
        size: u32,
    ) callconv(.C) bool {
        const buf = out[0..size];

        const plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        const typeInfo = std.meta.fields(Params);
        inline for (typeInfo, 0..) |field, index| {
            if (id == index) {
                const param = @field(plugin.params, field.name);
                const format = field.defaultValue().?.meta.displayFormat;
                switch (@typeInfo(@TypeOf(param.value))) {
                    .@"enum" => {
                        const enumId: usize = @intFromFloat(value);
                        const enumValue: @TypeOf(param.value) = @enumFromInt(enumId);
                        _ = std.fmt.bufPrint(buf, format, .{@tagName(enumValue)}) catch unreachable;
                    },
                    .float => {
                        _ = std.fmt.bufPrint(buf, format, .{value}) catch unreachable;
                    },
                    else => @compileError(std.fmt.comptimePrint("UNEXPECTED TYPE {}", .{field.type})),
                }

                return true;
            }
        }

        return false;
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
                const displayFormat = param.meta.displayFormat;
                const before = std.mem.indexOf(u8, displayFormat, "{").?;
                const after = displayFormat.len - std.mem.indexOf(u8, displayFormat, "}").? - 1;
                const clean = string[before .. string.len - after];

                const value: f64 = switch (@typeInfo(@TypeOf(param.value))) {
                    .@"enum" => block: {
                        const enumValue = std.meta.stringToEnum(@TypeOf(param.value), clean);
                        if (enumValue == null) return false;
                        break :block @floatFromInt(@intFromEnum(enumValue.?));
                    },
                    .float => std.fmt.parseFloat(f64, clean) catch return false,
                    else => @compileError(std.fmt.comptimePrint("UNEXPECTED TYPE {}", .{field.type})),
                };

                log.debug("converting text to value: {s} {s} => {d}", .{ field.name, string, value });
                out.* = value;

                return true;
            }
        }

        return false;
    }
};
