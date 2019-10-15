const std = @import("std");
const Builder = std.build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const want_armv6 = b.option(bool, "armv6", "Build armv6") orelse false;
    const want_armv7 = b.option(bool, "armv7", "Build armv7 (default)") orelse false;
    const want_qemu = b.option(bool, "qemu", "Build qemu variant of armv7") orelse false;
    const want_nodisplay = b.option(bool, "nodisplay", "No display for qemu") orelse false;

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
        if (want_qemu) {
            kernel_name = exec_name ++ "-armv7-qemu.img";
        } else {
            kernel_name = exec_name ++ "-armv7.img";
        }
    }
    const os = builtin.Os.freestanding;
    const environ = builtin.Abi.eabihf;
    exe.setTarget(arch, os, environ);
    exe.addBuildOption(u32, "subarch", subarch);
    exe.addBuildOption(bool, "is_qemu", want_qemu);
    exe.setLinkerScriptPath(if (want_qemu) "src/linker-qemu.ld" else "src/linker.ld");

    const run_objcopy = b.addSystemCommand([_][]const u8{
        "llvm-objcopy-6.0", exe.getOutputPath(),
        "-O", "binary",
        kernel_name,
    });
    run_objcopy.step.dependOn(&exe.step);

    b.default_step.dependOn(&run_objcopy.step);

    var run_qemu_args = std.ArrayList([]const u8).init(b.allocator);
    try run_qemu_args.appendSlice([_][]const u8{
        "qemu-system-arm",
        "-kernel", exe.getOutputPath(),
        "-m", "256",
        "-M", "raspi2",
        "-serial", "stdio",
        "-display", if (want_nodisplay) "none" else "gtk",
    });
    const run_qemu = b.addSystemCommand(run_qemu_args.toSliceConst());
    run_qemu.step.dependOn(&exe.step);

    const qemu = b.step("qemu", "Run the program in qemu");
    qemu.dependOn(&run_qemu.step);
}
