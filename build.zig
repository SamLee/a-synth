const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const clap = b.dependency("clap", .{});

    const plugin = b.addSharedLibrary(.{
        .name = "a-synth.clap",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    plugin.addIncludePath(clap.path("include"));
    plugin.addIncludePath(b.path("src/ui"));
    if (target.query.os_tag == .windows) plugin.subsystem = .Windows;
    b.installArtifact(plugin);

    const validate_cmd = b.addSystemCommand(&.{
        "./clap-validator",
        "validate",
        "zig-out/lib/liba-synth.clap.so",
    });
    validate_cmd.step.dependOn(b.getInstallStep());

    const validate = b.step("validate", "Run the snap validator");
    validate.dependOn(&validate_cmd.step);
}
