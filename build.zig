const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const clap = b.dependency("clap", .{});

    const plugin = b.addLibrary(.{
        .name = "a-synth.clap",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });
    plugin.addIncludePath(clap.path("include"));
    plugin.addIncludePath(b.path("src/ui"));
    if (target.query.os_tag == .windows) plugin.subsystem = .Windows;
    b.installArtifact(plugin);

    const validate_cmd = b.addSystemCommand(&.{
        "./clap-validator",
        "validate",
    });
    validate_cmd.addArtifactArg(plugin);
    validate_cmd.step.dependOn(b.getInstallStep());

    const validate = b.step("validate", "Run the snap validator");
    validate.dependOn(&validate_cmd.step);
}
