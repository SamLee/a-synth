const std = @import("std");
const clap = @import("clap.zig").clap;
const Envelope = @import("envelope.zig").Envelope;
const parameters = @import("parameters.zig");

const Voice = struct {
    held: bool,
    ended: bool = false,
    noteId: i32,
    channel: i16,
    key: i16,
    phase: f32,
    velocity: f32,
    osc: usize,
    envelope: Envelope,
};

pub const Plugin = struct {
    plugin: clap.clap_plugin,
    host: [*c]const clap.clap_host,
    sampleRate: f64 = 44100,
    voices: std.ArrayList(Voice),
    tailTime: f64 = 2.0 / 1000.0,
    allocator: std.mem.Allocator,
    params: parameters.Params = parameters.Params{},

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
            .voices = std.ArrayList(Voice).empty,
            .allocator = allocator,
        };

        return &p.plugin;
    }

    fn init(_: [*c]const clap.clap_plugin) callconv(.c) bool {
        return true;
    }

    fn destroy(clap_plugin: [*c]const clap.clap_plugin) callconv(.c) void {
        const plugin: *Plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        plugin.voices.deinit(plugin.allocator);
        plugin.allocator.destroy(plugin);
    }

    fn activate(
        clap_plugin: [*c]const clap.clap_plugin,
        sampleRate: f64,
        minFramesCount: u32,
        maxFramesCount: u32,
    ) callconv(.c) bool {
        const plugin: *Plugin = std.zig.c_translation.cast(*Plugin, clap_plugin.*.plugin_data);
        plugin.sampleRate = sampleRate;
        _ = minFramesCount;
        _ = maxFramesCount;

        return true;
    }

    fn deactivate(_: [*c]const clap.clap_plugin) callconv(.c) void {}

    fn start_processing(_: [*c]const clap.clap_plugin) callconv(.c) bool {
        return true;
    }

    fn stop_processing(_: [*c]const clap.clap_plugin) callconv(.c) void {}

    fn reset(_: [*c]const clap.clap_plugin) callconv(.c) void {}

    fn on_main_thread(_: [*c]const clap.clap_plugin) callconv(.c) void {}

    fn get_extension(
        _: [*c]const clap.clap_plugin,
        id: [*c]const u8,
    ) callconv(.c) ?*const anyopaque {
        if (std.mem.orderZ(u8, id, &clap.CLAP_EXT_NOTE_PORTS) == .eq) {
            return &extensionNotePorts.extension;
        }

        if (std.mem.orderZ(u8, id, &clap.CLAP_EXT_AUDIO_PORTS) == .eq) {
            return &extensionAudioPorts.extension;
        }

        if (std.mem.orderZ(u8, id, &clap.CLAP_EXT_PARAMS) == .eq) {
            return &parameters.extensionParams.extension;
        }

        return null;
    }

    fn process(
        clap_plugin: [*c]const clap.clap_plugin,
        clap_process: [*c]const clap.clap_process,
    ) callconv(.c) clap.clap_process_status {
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

    pub fn process_event(plugin: *Plugin, event: [*c]const clap.clap_event_header) void {
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
                                if (voice.envelope.state == Envelope.State.end) break;
                                voice.envelope.advance();
                            }
                        }
                    }
                }

                if (event.*.type == clap.CLAP_EVENT_NOTE_ON) {
                    plugin.voices.append(plugin.allocator, Voice{
                        .held = true,
                        .noteId = noteEvent.*.note_id,
                        .channel = noteEvent.*.channel,
                        .phase = 0.0,
                        .key = noteEvent.*.key,
                        .velocity = @floatCast(noteEvent.*.velocity),
                        .osc = 0,
                        .envelope = Envelope{
                            .attack = Envelope.Stage.init(plugin.sampleRate, plugin.params.attackDuration.value, plugin.params.attackTarget.value),
                            .decay = Envelope.Stage.init(plugin.sampleRate, plugin.params.decayDuration.value, plugin.params.decayTarget.value),
                            .release = Envelope.Stage.init(plugin.sampleRate, plugin.params.releaseDuration.value, plugin.params.releaseTarget.value),
                        },
                    }) catch unreachable;

                    plugin.voices.append(plugin.allocator, Voice{
                        .held = true,
                        .noteId = noteEvent.*.note_id,
                        .channel = noteEvent.*.channel,
                        .phase = 0.0,
                        .key = noteEvent.*.key,
                        .velocity = @floatCast(noteEvent.*.velocity),
                        .osc = 1,
                        .envelope = Envelope{
                            .attack = Envelope.Stage.init(plugin.sampleRate, plugin.params.attackDuration.value, plugin.params.attackTarget.value),
                            .decay = Envelope.Stage.init(plugin.sampleRate, plugin.params.decayDuration.value, plugin.params.decayTarget.value),
                            .release = Envelope.Stage.init(plugin.sampleRate, plugin.params.releaseDuration.value, plugin.params.releaseTarget.value),
                        },
                    }) catch unreachable;
                }
            }

            if (event.*.type == clap.CLAP_EVENT_PARAM_VALUE) {
                const paramEvent = std.zig.c_translation.cast([*c]clap.clap_event_param_value, event);
                parameters.handleEvent(paramEvent.*, &plugin.params);
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

                const osc = switch (voice.osc) {
                    0 => plugin.params.osc1,
                    1 => plugin.params.osc2,
                    else => {
                        std.log.err("Unrecognised osc id: {}", .{voice.osc});
                        continue;
                    },
                };

                var val: f32 = switch (osc.value) {
                    .sine => std.math.sin(voice.phase * std.math.tau),
                    .siney => block: {
                        const sine = std.math.sin(voice.phase * std.math.tau);
                        break :block if (sine < 0) sine * 0.5 else sine;
                    },
                    .square => if (std.math.sin(voice.phase * std.math.tau) > 0.0) 1 else -1,
                    .saw => 2 * (voice.phase - std.math.floor(0.5 + voice.phase)),
                    .triangle => 4 * @abs(voice.phase - std.math.floor(voice.phase + 0.75) + 0.25) - 1,
                    .noise => std.crypto.random.floatNorm(f32),
                };

                if (plugin.params.highQuality.value == .off) {
                    const noise = std.crypto.random.floatNorm(f32) / 200;
                    val += noise;
                }

                const volume: f32 = switch (voice.osc) {
                    0 => @floatCast(plugin.params.vol1.value),
                    1 => @floatCast(plugin.params.vol2.value),
                    else => unreachable,
                };

                sum += voice.envelope.apply(0.5 * val * voice.velocity * volume / 100);

                const offset: i16 = switch (voice.osc) {
                    0 => @intFromFloat(plugin.params.offset1.value),
                    1 => @intFromFloat(plugin.params.offset2.value),
                    else => unreachable,
                };

                voice.phase += 440 * std.math.exp2(@as(f32, @floatFromInt(voice.key - 57 + offset)) / 12) / @as(f32, @floatCast(plugin.sampleRate));
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

    fn count(_: [*c]const clap.clap_plugin, isInput: bool) callconv(.c) u32 {
        return if (isInput) 1 else 0;
    }

    fn get(
        _: [*c]const clap.clap_plugin,
        index: u32,
        isInput: bool,
        info: [*c]clap.clap_note_port_info,
    ) callconv(.c) bool {
        if (!isInput or index != 0) return false;
        info.*.id = 0;
        info.*.preferred_dialect = clap.CLAP_NOTE_DIALECT_CLAP;
        info.*.supported_dialects = clap.CLAP_NOTE_DIALECT_CLAP;
        _ = std.fmt.bufPrintZ(&info.*.name, "Note Port", .{}) catch unreachable;
        return true;
    }
};

const extensionAudioPorts = struct {
    const extension = clap.clap_plugin_audio_ports{
        .count = count,
        .get = get,
    };

    fn count(_: [*c]const clap.clap_plugin, isInput: bool) callconv(.c) u32 {
        return if (isInput) 0 else 1;
    }

    fn get(
        _: [*c]const clap.clap_plugin,
        index: u32,
        isInput: bool,
        info: [*c]clap.clap_audio_port_info,
    ) callconv(.c) bool {
        if (isInput or index != 0) return false;
        info.* = .{
            .id = 0,
            .name = undefined,
            .channel_count = 2,
            .flags = clap.CLAP_AUDIO_PORT_IS_MAIN,
            .port_type = &clap.CLAP_PORT_STEREO,
            .in_place_pair = clap.CLAP_INVALID_ID,
        };
        _ = std.fmt.bufPrintZ(&info.*.name, "Audio Port", .{}) catch unreachable;
        return true;
    }
};
