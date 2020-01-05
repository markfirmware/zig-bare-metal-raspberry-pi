const std = @import("std");
const Builder = std.build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const exec_name = "zig-bare-metal-raspberry-pi";
    const exe = b.addExecutable(exec_name, "src/main.zig");
    exe.setOutputDir("zig-cache");
    exe.setBuildMode(mode);

    var arch: builtin.Arch = undefined;
    var kernel_name: []const u8 = undefined;
    arch = builtin.Arch{ .aarch64 = builtin.Arch.Arm64.v8 };
    kernel_name = exec_name ++ "-armv8.img";
    const os = builtin.Os.freestanding;
    const environ = builtin.Abi.eabihf;
    exe.setTarget(arch, os, environ);
    exe.setLinkerScriptPath("src/linker.ld");

    const run_objcopy = b.addSystemCommand(&[_][]const u8{
        "llvm-objcopy", exe.getOutputPath(),
        "-O", "binary",
        kernel_name,
    });
    run_objcopy.step.dependOn(&exe.step);

    b.default_step.dependOn(&run_objcopy.step);
}
