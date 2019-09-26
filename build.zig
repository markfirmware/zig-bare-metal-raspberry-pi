const std = @import("std");
const Builder = std.build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const want_armv6 = b.option(bool, "armv6", "Build armv6 instead of armv7 (armv7 is default)") orelse false;
    const want_armv7 = b.option(bool, "armv7", "Build armv7 instead of armv6 (armv7 is default)") orelse false;
    const want_qemu = b.option(bool, "qemu", "Select qemu load address and peripherals") orelse false;

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
    exe.setTarget(arch, builtin.Os.freestanding, environ);
    exe.addBuildOption(u32, "subarch", subarch);
    exe.addBuildOption(bool, "is_qemu", want_qemu);

    const linker_script = if (want_qemu) "src/linker-qemu.ld" else "src/linker.ld";
    exe.setLinkerScriptPath(linker_script);

    const run_objcopy = b.addSystemCommand([_][]const u8{
        "llvm-objcopy", exe.getOutputPath(),
        "-O", "binary",
        kernel_name,
    });
    run_objcopy.step.dependOn(&exe.step);

    b.default_step.dependOn(&run_objcopy.step);
}
