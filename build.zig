const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const source_file = .{ .path = "src/main.zig" };

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    build_options.addOption(usize, "buffer_size", b.option(usize, "buffer-size", "Size of the buffer on the stack to use (default: 40)") orelse 40);
    build_options.addOption(bool, "n_state", b.option(bool, "n-state", "Should it be able to rotate to all 4 directions or just 2 (default: true)") orelse true);
    build_options.addOption([]const u8, "output", b.option([]const u8, "display", "Output display name in xrandr (default: eDP-1)") orelse "eDP-1");
    build_options.addOption([]const u8, "script", b.option([]const u8, "script", "Script (relative to home directory) we should run (default: .xrandr-changed)") orelse ".xrandr-changed");

    build_options.addOption(
        []const u8,
        "device_location",
        b.option([]const u8, "device-location", "The directory location to find iio devices in (default: /sys/bus/iio/devices)") orelse "/sys/bus/iio/devices",
    );

    const exe = b.addExecutable(.{
        .name = "2in1screen",
        .root_source_file = source_file,
        .target = target,
        .optimize = optimize,
    });
    exe.addOptions("build_options", build_options);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = source_file,
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addOptions("build_options", build_options);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
