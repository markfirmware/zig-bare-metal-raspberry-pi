export fn kernelMain() noreturn {
    var x: u32 = 1;
    var y: u32 = 2;
    var z: u32 = x % y;
    while (true) {
    }
}

comptime {
    asm(
        \\.section .text.boot // .text.boot to keep this in the first portion of the binary
        \\.globl _start
        \\_start:
        \\ cps #0x1f // enter system mode
        \\ mov sp,#0x08000000
        \\ bl kernelMain
    );
}
