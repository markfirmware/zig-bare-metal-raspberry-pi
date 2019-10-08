const std = @import("std");
const Builder = std.build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const want_armv6 = b.option(bool, "armv6", "Build armv6") orelse false;
    const want_armv7 = b.option(bool, "armv7", "Build armv7 (default)") orelse false;

    const exec_name = "zig-bare-metal-raspberry-pi";
    const exe = b.addExecutable(exec_name, "src/main.zig");
    exe.setOutputDir("zig-cache");
    exe.setBuildMode(mode);

    var arch: builtin.Arch = undefined;
    var subarch: u32 = undefined;
    var kernel_name: []const u8 = undefined;
    if (want_armv6) {
        arch = builtin.Arch{ .arm = builtin.Arch.Arm32.v6 };
        subarch = 6;
        kernel_name = exec_name ++ "-armv6.img";
    } else {
        arch = builtin.Arch{ .arm = builtin.Arch.Arm32.v7 };
        subarch = 7;
        kernel_name = exec_name ++ "-armv7.img";
    }
    const os = builtin.Os.freestanding;
    const environ = builtin.Abi.eabihf;
    exe.setTarget(arch, os, environ);
    exe.addBuildOption(u32, "subarch", subarch);
    exe.setLinkerScriptPath("src/linker.ld");

    const run_objcopy = b.addSystemCommand([_][]const u8{
        "llvm-objcopy-6.0", exe.getOutputPath(),
        "-O", "binary",
        kernel_name,
    });
    run_objcopy.step.dependOn(&exe.step);

    b.default_step.dependOn(&run_objcopy.step);
}
