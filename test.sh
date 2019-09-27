#!/bin/bash
set -x

zig build
llvm-objdump -x --source zig-cache/zig-bare-metal-raspberry-pi > asm.armv7-qemu
grep unknown asm.armv7-qemu
hexdump *.img | egrep '0b02 ed'
