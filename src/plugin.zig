const std = @import("std");
const clap = @cImport(@cInclude("clap/clap.h"));
const Envelope = @import("envelope.zig").Envelope;

const Voice = struct {
    held: bool,
    ended: bool = false,
    noteId: i32,
    channel: i16,
    key: i16,
    phase: f32,
    velocity: f32,
    envelope: Envelope,
};

pub const Plugin = struct {
    plugin: clap.clap_plugin,
    host: [*c]const clap.clap_host,
    sampleRate: f64 = 44100,
    voices: std.ArrayList(Voice),
    tailTime: f64 = 2.0 / 1000.0,
    allocator: std.mem.Allocator,
    params: Params = Params{},

    pub fn create(
        host: [*c]const clap.clap_host,
        allocator: std.mem.Allocator,
        descriptor: *const clap.clap_plugin_descriptor,
    ) [*c]clap.clap_plugin {
        var p = allocator.create(Plugin) catch unreachable;

        p.* = .{
            .plugin = clap.clap_plugin{
                .desc = descriptor,
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
            .allocator = allocator,
        };

        return &p.plugin;
    }

    fn init(_: [*c]const clap.clap_plugin) callconv(.C) bool {
        return true;
    }

    fn destroy(clap_plugin: [*c]const clap.clap_plugin) callconv(.C) void {
        const plugin: *Plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        plugin.allocator.destroy(plugin);
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

        if (std.mem.orderZ(u8, id, &clap.CLAP_EXT_PARAMS) == .eq) {
            return &extensionParams.extension;
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

        var i: usize = plugin.voices.items.len;
        while (i > 0) : (i -= 1) {
            const voice = plugin.voices.items[i - 1];
            if (voice.ended) {
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
                _ = plugin.voices.swapRemove(i - 1);
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

                for (plugin.voices.items) |*voice| {
                    if ((noteEvent.*.key == -1 or voice.key == noteEvent.*.key) and
                        (noteEvent.*.note_id == -1 or voice.noteId == noteEvent.*.note_id) and
                        (noteEvent.*.channel == -1 or voice.channel == noteEvent.*.channel))
                    {
                        if (event.*.type == clap.CLAP_EVENT_NOTE_CHOKE) {
                            voice.ended = true;
                        } else {
                            voice.held = false;
                            while (voice.envelope.state != Envelope.State.release) {
                                voice.envelope.advance();
                            }
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
                        .envelope = Envelope.default(plugin.sampleRate),
                    }) catch unreachable;
                }
            }

            if (event.*.type == clap.CLAP_EVENT_PARAM_VALUE) {
                const paramEvent = std.zig.c_translation.cast([*c]clap.clap_event_param_value, event);
                const param: Params.Params = @enumFromInt(paramEvent.*.param_id);

                switch (param) {
                    Params.Params.wave => {
                        const enumId: usize = @intFromFloat(paramEvent.*.value);
                        plugin.params.wave = @enumFromInt(enumId);
                    },
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
                if (voice.ended) continue;
                if (voice.envelope.state == Envelope.State.end) {
                    voice.ended = true;
                    continue;
                }

                const val: f32 = switch (plugin.params.wave) {
                    .sine => std.math.sin(voice.phase * std.math.tau),
                    .square => if (std.math.sin(voice.phase * std.math.tau) > 0.0) 1 else -1,
                    .saw => 2 * (voice.phase - std.math.floor(0.5 + voice.phase)),
                };

                sum += voice.envelope.apply(val * voice.velocity);
                voice.phase += 440 * std.math.exp2(@as(f32, @floatFromInt(voice.key - 57)) / 12) / @as(f32, @floatCast(plugin.sampleRate));
                voice.phase -= std.math.floor(voice.phase);
                if (voice.envelope.state != Envelope.State.sustain) voice.envelope.advance();
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

const extensionParams = struct {
    const extension = clap.clap_plugin_params{
        .count = count,
        .flush = flush,
        .get_info = get_info,
        .get_value = get_value,
        .value_to_text = value_to_text,
        .text_to_value = text_to_value,
    };

    fn count(_: [*c]const clap.clap_plugin) callconv(.C) u32 {
        return 1;
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
        if (param_index == @intFromEnum(Params.Params.wave)) {
            param_info.* = clap.clap_param_info{
                .id = param_index,
                .flags = clap.CLAP_PARAM_IS_ENUM | clap.CLAP_PARAM_IS_STEPPED,
                .min_value = 0,
                .max_value = @typeInfo(Params.Wave).Enum.fields.len - 1,
            };
            _ = std.fmt.bufPrint(&param_info.*.name, "Shape", .{}) catch unreachable;

            return true;
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
        const string = switch (param) {
            Params.Params.wave => block: {
                const enumId: usize = @intFromFloat(value);
                const wave: Params.Wave = @enumFromInt(enumId);
                break :block @tagName(wave);
            },
        };

        _ = std.fmt.bufPrint(buf, "{s}", .{string}) catch unreachable;

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
        };

        out.* = value;

        return true;
    }
};

const Params = struct {
    wave: Wave = Wave.sine,

    const Params = enum { wave };
    const Wave = enum { sine, square, saw };
};
