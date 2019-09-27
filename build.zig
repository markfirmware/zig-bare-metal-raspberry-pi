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
    arch = builtin.Arch{ .arm = builtin.Arch.Arm32.v7 };

    const os = builtin.Os.freestanding;
    const environ = builtin.Abi.eabihf;
    exe.setTarget(arch, builtin.Os.freestanding, environ);

    const linker_script = "src/linker.ld";
    exe.setLinkerScriptPath(linker_script);

    const run_objcopy = b.addSystemCommand([_][]const u8{
        "llvm-objcopy", exe.getOutputPath(),
        "-O", "binary",
        exec_name ++ "-armv7.img",
    });
    run_objcopy.step.dependOn(&exe.step);

    b.default_step.dependOn(&run_objcopy.step);
}
