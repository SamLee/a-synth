const std = @import("std");
const clap = @cImport(@cInclude("clap/clap.h"));

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: std.mem.Allocator = undefined;

const Voice = struct {
    held: bool,
    noteId: i32,
    channel: i16,
    key: i16,
    phase: f32,
    velocity: f32,
};

const Plugin = struct {
    plugin: clap.clap_plugin,
    host: [*c]const clap.clap_host,
    sampleRate: f64 = 44100,
    voices: std.ArrayList(Voice),

    fn create(host: [*c]const clap.clap_host) [*c]clap.clap_plugin {
        var p = allocator.create(Plugin) catch unreachable;

        p.* = .{
            .plugin = clap.clap_plugin{
                .desc = &pluginDescriptor,
                .plugin_data = p,
                .init = Plugin.init,
                .destroy = destroy,
                .activate = activate,
                .deactivate = deactivate,
                .start_processing = start_processing,
                .stop_processing = stop_processing,
                .reset = reset,
                .process = process,
                .get_extension = get_extension,
                .on_main_thread = on_main_thread,
            },
            .host = host,
            .voices = std.ArrayList(Voice).init(allocator),
        };

        return &p.plugin;
    }

    fn init(_: [*c]const clap.clap_plugin) callconv(.C) bool {
        return true;
    }

    fn destroy(clap_plugin: [*c]const clap.clap_plugin) callconv(.C) void {
        const plugin: *Plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        allocator.destroy(plugin);
    }

    fn activate(
        clap_plugin: [*c]const clap.clap_plugin,
        sampleRate: f64,
        minFramesCount: u32,
        maxFramesCount: u32,
    ) callconv(.C) bool {
        const plugin: *Plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        plugin.sampleRate = sampleRate;
        _ = minFramesCount;
        _ = maxFramesCount;

        return true;
    }

    fn deactivate(_: [*c]const clap.clap_plugin) callconv(.C) void {}

    fn start_processing(_: [*c]const clap.clap_plugin) callconv(.C) bool {
        return true;
    }

    fn stop_processing(_: [*c]const clap.clap_plugin) callconv(.C) void {}

    fn reset(_: [*c]const clap.clap_plugin) callconv(.C) void {}

    fn on_main_thread(_: [*c]const clap.clap_plugin) callconv(.C) void {}

    fn get_extension(
        _: [*c]const clap.clap_plugin,
        id: [*c]const u8,
    ) callconv(.C) ?*const anyopaque {
        if (std.mem.orderZ(u8, id, &clap.CLAP_EXT_NOTE_PORTS) == .eq) {
            return &extensionNotePorts.extension;
        }

        if (std.mem.orderZ(u8, id, &clap.CLAP_EXT_AUDIO_PORTS) == .eq) {
            return &extensionAudioPorts.extension;
        }

        return null;
    }

    fn process(
        clap_plugin: [*c]const clap.clap_plugin,
        clap_process: [*c]const clap.clap_process,
    ) callconv(.C) clap.clap_process_status {
        const plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);

        if (clap_process.*.audio_inputs_count != 0) @panic("WHAT THE FUCK INPUTS");
        if (clap_process.*.audio_outputs_count != 1) @panic("WHAT THE FUCK OUTPUTS");

        const frameCount = clap_process.*.frames_count;
        const eventCount = clap_process.*.in_events.*.size.?(clap_process.*.in_events);
        var frameIndex: u32 = 0;
        var eventIndex: u32 = 0;
        var nextEventFrame = if (eventCount > 0) 0 else frameCount;

        while (frameIndex < frameCount) {
            while (eventIndex < eventCount and frameIndex == nextEventFrame) {
                const event = clap_process.*.in_events.*.get.?(clap_process.*.in_events, eventIndex);

                if (event.*.time != frameIndex) {
                    nextEventFrame = event.*.time;
                    break;
                }

                process_event(plugin, event);
                eventIndex += 1;

                if (eventIndex == eventCount) {
                    nextEventFrame = frameCount;
                }
            }

            render_audio(
                plugin,
                frameIndex,
                nextEventFrame,
                clap_process.*.audio_outputs[0].data32[0],
                clap_process.*.audio_outputs[0].data32[1],
            );

            frameIndex = nextEventFrame;
        }

        for (plugin.voices.items, 0..) |voice, i| {
            if (!voice.held) {
                const event = clap.clap_event_note{
                    .header = clap.clap_event_header{
                        .size = @sizeOf(clap.clap_event_note),
                        .time = 0,
                        .space_id = clap.CLAP_CORE_EVENT_SPACE_ID,
                        .type = clap.CLAP_EVENT_NOTE_END,
                        .flags = 0,
                    },
                    .key = voice.key,
                    .note_id = voice.noteId,
                    .channel = voice.channel,
                    .port_index = 0,
                };

                _ = clap_process.*.out_events.*.try_push.?(clap_process.*.out_events, &event.header);
                plugin.voices.items[i] = undefined;
            }
        }

        return clap.CLAP_PROCESS_CONTINUE;
    }

    fn process_event(plugin: *Plugin, event: [*c]const clap.clap_event_header) void {
        if (event.*.space_id == clap.CLAP_CORE_EVENT_SPACE_ID) {
            if (event.*.type == clap.CLAP_EVENT_NOTE_ON or
                event.*.type == clap.CLAP_EVENT_NOTE_OFF or
                event.*.type == clap.CLAP_EVENT_NOTE_CHOKE)
            {
                const noteEvent = std.zig.c_translation.cast([*c]clap.clap_event_note, event);

                for (plugin.voices.items, 0..) |*voice, i| {
                    if ((noteEvent.*.key == -1 or voice.key == noteEvent.*.key) and
                        (noteEvent.*.note_id == -1 or voice.noteId == noteEvent.*.note_id) and
                        (noteEvent.*.channel == -1 or voice.channel == noteEvent.*.channel))
                    {
                        // choke should end the note immediately
                        if (event.*.type == clap.CLAP_EVENT_NOTE_CHOKE) {
                            plugin.voices.items[i] = undefined;
                        } else {
                            voice.held = false;
                        }
                    }
                }

                if (event.*.type == clap.CLAP_EVENT_NOTE_ON) {
                    plugin.voices.append(Voice{
                        .held = true,
                        .noteId = noteEvent.*.note_id,
                        .channel = noteEvent.*.channel,
                        .phase = 0.0,
                        .key = noteEvent.*.key,
                        .velocity = @floatCast(noteEvent.*.velocity),
                    }) catch unreachable;
                }
            }
        }
    }

    fn render_audio(
        plugin: *Plugin,
        start: u32,
        end: u32,
        left: [*c]f32,
        right: [*c]f32,
    ) void {
        for (start..end) |i| {
            var sum: f32 = 0;

            for (plugin.voices.items) |*voice| {
                if (!voice.held) continue;
                const val = std.math.sin(voice.phase * std.math.tau);
                sum += val * voice.velocity;
                voice.phase += 440 * std.math.exp2(@as(f32, @floatFromInt(voice.key - 57)) / 12) / @as(f32, @floatCast(plugin.sampleRate));
                voice.phase -= std.math.floor(voice.phase);
            }

            left[i] = sum;
            right[i] = sum;
        }
    }
};

const extensionNotePorts = struct {
    const extension = clap.clap_plugin_note_ports{
        .count = count,
        .get = get,
    };

    fn count(_: [*c]const clap.clap_plugin, isInput: bool) callconv(.C) u32 {
        return if (isInput) 1 else 0;
    }

    fn get(
        _: [*c]const clap.clap_plugin,
        index: u32,
        isInput: bool,
        info: [*c]clap.clap_note_port_info,
    ) callconv(.C) bool {
        if (!isInput or index != 0) return false;
        info.*.id = 0;
        info.*.preferred_dialect = clap.CLAP_NOTE_DIALECT_CLAP;
        info.*.supported_dialects = clap.CLAP_NOTE_DIALECT_CLAP;
        _ = std.fmt.bufPrint(&info.*.name, "Note Port", .{}) catch unreachable;
        return true;
    }
};

const extensionAudioPorts = struct {
    const extension = clap.clap_plugin_audio_ports{
        .count = count,
        .get = get,
    };

    fn count(_: [*c]const clap.clap_plugin, isInput: bool) callconv(.C) u32 {
        return if (isInput) 0 else 1;
    }

    fn get(
        _: [*c]const clap.clap_plugin,
        index: u32,
        isInput: bool,
        info: [*c]clap.clap_audio_port_info,
    ) callconv(.C) bool {
        if (isInput or index != 0) return false;
        info.* = .{
            .id = 0,
            .name = undefined,
            .channel_count = 2,
            .flags = clap.CLAP_AUDIO_PORT_IS_MAIN,
            .port_type = &clap.CLAP_PORT_STEREO,
            .in_place_pair = clap.CLAP_INVALID_ID,
        };
        _ = std.fmt.bufPrint(&info.*.name, "Audio Port", .{}) catch unreachable;
        return true;
    }
};

const pluginDescriptor = clap.clap_plugin_descriptor{
    .clap_version = clap.CLAP_VERSION,
    .name = "First CLAP",
    .id = "cksum.FirstCLAP",
    .vendor = "cksum",
    .url = "https://cksum.co.uk",
    .manual_url = "https://cksum.co.uk",
    .support_url = "https://cksum.co.uk",
    .version = "0.1.0",
    .description = "First CLAP plugin",
    .features = &[_][*c]const u8{
        clap.CLAP_PLUGIN_FEATURE_INSTRUMENT,
        clap.CLAP_PLUGIN_FEATURE_SYNTHESIZER,
        clap.CLAP_PLUGIN_FEATURE_STEREO,
        null,
    },
};

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

    return Plugin.create(host);
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
