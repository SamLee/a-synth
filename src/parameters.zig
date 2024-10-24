const std = @import("std");
const clap = @cImport(@cInclude("clap/clap.h"));
const Plugin = @import("plugin.zig").Plugin;

pub const Params = struct {
    wave: Wave = Wave.sine,
    attackDuration: f64 = 0.001,
    attackTarget: f64 = 1,
    decayDuration: f64 = 0.001,
    decayTarget: f64 = 1,
    releaseDuration: f64 = 0.002,
    releaseTarget: f64 = 0,
    offset: f64 = 0,

    pub const Params = enum {
        wave,
        attackDuration,
        attackTarget,
        decayDuration,
        decayTarget,
        releaseDuration,
        releaseTarget,
        offset,
    };
    const Wave = enum { sine, siney, square, saw, triangle, noise };
};

pub fn handleEvent(event: clap.clap_event_param_value, params: *Params) void {
    const param: Params.Params = @enumFromInt(event.param_id);

    switch (param) {
        Params.Params.wave => {
            const enumId: usize = @intFromFloat(event.value);
            params.wave = @enumFromInt(enumId);
        },
        Params.Params.attackTarget => params.attackTarget = event.value,
        Params.Params.attackDuration => params.attackDuration = event.value,
        Params.Params.decayTarget => params.decayTarget = event.value,
        Params.Params.decayDuration => params.decayDuration = event.value,
        Params.Params.releaseTarget => params.releaseTarget = event.value,
        Params.Params.releaseDuration => params.releaseDuration = event.value,
        Params.Params.offset => params.offset = event.value,
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
            Params.Params.wave => {
                param_info.* = clap.clap_param_info{
                    .id = param_index,
                    .flags = clap.CLAP_PARAM_IS_ENUM | clap.CLAP_PARAM_IS_STEPPED | clap.CLAP_PARAM_IS_AUTOMATABLE,
                    .min_value = 0,
                    .max_value = @typeInfo(Params.Wave).Enum.fields.len - 1,
                };
                _ = std.fmt.bufPrint(&param_info.*.name, "Shape", .{}) catch unreachable;
                _ = std.fmt.bufPrint(&param_info.*.module, "Oscillator", .{}) catch unreachable;
                return true;
            },
            Params.Params.attackDuration,
            Params.Params.decayDuration,
            Params.Params.releaseDuration,
            => {
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
            Params.Params.attackTarget,
            Params.Params.decayTarget,
            Params.Params.releaseTarget,
            => {
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
            Params.Params.offset => {
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
        const param: Params.Params = @enumFromInt(id);
        const paramValue: f64 = switch (param) {
            Params.Params.wave => @floatFromInt(@intFromEnum(plugin.params.wave)),
            Params.Params.attackTarget => plugin.params.attackTarget,
            Params.Params.attackDuration => plugin.params.attackDuration,
            Params.Params.decayTarget => plugin.params.decayTarget,
            Params.Params.decayDuration => plugin.params.decayDuration,
            Params.Params.releaseTarget => plugin.params.releaseTarget,
            Params.Params.releaseDuration => plugin.params.releaseDuration,
            Params.Params.offset => plugin.params.offset,
        };

        value.* = paramValue;

        return true;
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
            Params.Params.wave => {
                const enumId: usize = @intFromFloat(value);
                const wave: Params.Wave = @enumFromInt(enumId);
                _ = std.fmt.bufPrint(buf, "{s}", .{@tagName(wave)}) catch unreachable;
            },
            Params.Params.attackDuration, Params.Params.decayDuration, Params.Params.releaseDuration => {
                _ = std.fmt.bufPrint(buf, "{d:.3}", .{value}) catch unreachable;
            },
            Params.Params.attackTarget, Params.Params.decayTarget, Params.Params.releaseTarget => {
                _ = std.fmt.bufPrint(buf, "{d:.3}", .{value}) catch unreachable;
            },
            Params.Params.offset => {
                _ = std.fmt.bufPrint(buf, "{d}", .{value}) catch unreachable;
            },
        }

        return true;
    }

    fn text_to_value(
        _: [*c]const clap.clap_plugin,
        id: clap.clap_id,
        in: [*c]const u8,
        out: [*c]f64,
    ) callconv(.C) bool {
        const param: Params.Params = @enumFromInt(id);
        const string = std.mem.span(in);
        const value: f64 = switch (param) {
            Params.Params.wave => block: {
                const wave = std.meta.stringToEnum(Params.Wave, string);
                break :block @floatFromInt(@intFromEnum(wave.?));
            },
            Params.Params.attackDuration,
            Params.Params.decayDuration,
            Params.Params.releaseDuration,
            Params.Params.attackTarget,
            Params.Params.decayTarget,
            Params.Params.releaseTarget,
            Params.Params.offset,
            => std.fmt.parseFloat(f64, string) catch unreachable,
        };

        out.* = value;

        return true;
    }
};
