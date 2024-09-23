const std = @import("std");
const raylib = @import("raylib-zig/lib.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "linden",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const system_lib = b.option(bool, "system-raylib", "link to preinstalled raylib libraries") orelse false;
    raylib.link(b, exe, system_lib);
    raylib.addAsPackage(b, "raylib", exe);
    raylib.math.addAsPackage(b, "raylib-math", exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_check = b.addExecutable(.{
        .name = "bounce",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    raylib.link(b, exe_check, system_lib);
    raylib.addAsPackage(b, "raylib", exe_check);
    raylib.math.addAsPackage(b, "raylib-math", exe_check);

    const check = b.step("check", "Check if project compiles");
    check.dependOn(&exe_check.step);
}
