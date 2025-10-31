const clap = @import("clap.zig").clap;
const std = @import("std");

const LogContext = struct {
    host_log: *const fn ([*c]const clap.clap_host, clap.clap_log_severity, [*c]const u8) callconv(.c) void,
    host: [*c]const clap.clap_host,
};

pub var log_context: ?LogContext = null;

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (log_context) |context| {
        var buf: [1024]u8 = undefined;
        const scope_prefix = "(" ++ @tagName(scope) ++ "): ";
        const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;
        const msg = std.fmt.bufPrintZ(&buf, prefix ++ format ++ "\n", args) catch "[error] (logging): failed to format log message";
        const severity = switch (level) {
            .debug => clap.CLAP_LOG_DEBUG,
            .info => clap.CLAP_LOG_INFO,
            .warn => clap.CLAP_LOG_WARNING,
            .err => clap.CLAP_LOG_ERROR,
        };

        context.host_log(context.host, severity, msg.ptr);
    }
}
