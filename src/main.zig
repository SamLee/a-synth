const std = @import("std");
const clap = @cImport(@cInclude("clap/clap.h"));
const Plugin = @import("plugin.zig").Plugin;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

pub const std_options = .{ .logFn = logFn };

const pluginDescriptor = clap.clap_plugin_descriptor{
    .clap_version = clap.CLAP_VERSION,
    .name = "A Synth",
    .id = "cksum.a-synth",
    .vendor = "cksum",
    .url = "https://cksum.co.uk",
    .manual_url = "https://cksum.co.uk",
    .support_url = "https://cksum.co.uk",
    .version = "0.1.0",
    .description = "A synth",
    .features = &[_][*c]const u8{
        clap.CLAP_PLUGIN_FEATURE_INSTRUMENT,
        clap.CLAP_PLUGIN_FEATURE_SYNTHESIZER,
        clap.CLAP_PLUGIN_FEATURE_STEREO,
        null,
    },
};

fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

fn init(_: [*c]const u8) callconv(.C) bool {
    allocator = gpa.allocator();

    return true;
}

fn deinit() callconv(.C) void {}

fn get_factory(factoryId: [*c]const u8) callconv(.C) ?*const anyopaque {
    if (std.mem.orderZ(u8, factoryId, &clap.CLAP_PLUGIN_FACTORY_ID) == .eq) {
        return &pluginFactory;
    } else {
        return null;
    }
}

fn get_plugin_count(_: [*c]const clap.clap_plugin_factory) callconv(.C) u32 {
    return 1;
}

fn get_plugin_descriptor(
    _: [*c]const clap.clap_plugin_factory,
    _: u32,
) callconv(.C) *const clap.clap_plugin_descriptor {
    return &pluginDescriptor;
}

fn create_plugin(
    _: [*c]const clap.clap_plugin_factory,
    host: [*c]const clap.clap_host,
    pluginId: [*c]const u8,
) callconv(.C) [*c]const clap.clap_plugin {
    if (!clap.clap_version_is_compatible(host.*.clap_version) or
        std.mem.orderZ(u8, pluginId, pluginDescriptor.id) != .eq)
    {
        return null;
    }

    return Plugin.create(host, allocator, &pluginDescriptor);
}

const pluginFactory = clap.clap_plugin_factory{
    .get_plugin_count = &get_plugin_count,
    .get_plugin_descriptor = &get_plugin_descriptor,
    .create_plugin = &create_plugin,
};

export const clap_entry = clap.clap_plugin_entry_t{
    .clap_version = clap.CLAP_VERSION,
    .init = &init,
    .deinit = &deinit,
    .get_factory = &get_factory,
};
