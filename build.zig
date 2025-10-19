const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    _ = b.addModule("datez", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const date_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/Date.zig"),
            .target = target,
        })
    });

    const run_date_tests = b.addRunArtifact(date_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_date_tests.step);
}
