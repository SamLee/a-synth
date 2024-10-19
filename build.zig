const std = @import("std");

pub fn build(b: *std.Build) void {
    const clap = b.dependency("clap", .{});

    const plugin = b.addSharedLibrary(.{
        .name = "sine.clap",
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    plugin.addIncludePath(clap.path("include"));
    b.installArtifact(plugin);

    const validate_cmd = b.addSystemCommand(&.{
        "./clap-validator",
        "validate",
        "zig-out/lib/libsine.clap.so",
    });
    validate_cmd.step.dependOn(b.getInstallStep());

    const validate = b.step("validate", "Run the snap validator");
    validate.dependOn(&validate_cmd.step);
}
