const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const idlist = b.dependency("idlist", .{
        .target = target,
        .optimize = optimize,
    });

    const idlist_mod = idlist.module("idlist");

    const layout_mod = b.addModule("layout", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const layout_sdl_mod = b.addModule("layout_sdl", .{
        .root_source_file = b.path("src/layout_sdl.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "layout", .module = layout_mod },
            .{ .name = "idlist", .module = idlist_mod },
        },
        .link_libc = true,
    });

    const layout_example_mod = b.createModule(.{
        .root_source_file = b.path("src/layout_example.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "layout_sdl", .module = layout_sdl_mod },
            .{ .name = "layout", .module = layout_mod },
        },
    });

    const example_exe = b.addExecutable(.{
        .name = "layout-example",
        .root_module = layout_example_mod,
        .use_llvm = true, // Unfortunatly, this seems to be the only way to get useful debug symbols.
    });
    example_exe.linkSystemLibrary("SDL3");
    example_exe.linkSystemLibrary("SDL3_ttf");

    b.installArtifact(example_exe);

    const run_cmd = b.addRunArtifact(example_exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    const unit_test_files = [_][]const u8{
        "src/Layout.zig",
    };
    for (&unit_test_files) |file| {
        const unit_test_module = b.createModule(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
        });
        const unit_test = b.addTest(.{ .root_module = unit_test_module });
        const run_test = b.addRunArtifact(unit_test);
        test_step.dependOn(&run_test.step);
    }
}
