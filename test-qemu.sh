#!/bin/bash
set -x

zig build -Dqemu
llvm-objdump -x --source zig-cache/zig-bare-metal-raspberry-pi > asm.armv7-qemu
qemu-system-arm -M raspi2 -display none -serial stdio -kernel zig-bare-metal-raspberry-pi-armv7-qemu.img 

