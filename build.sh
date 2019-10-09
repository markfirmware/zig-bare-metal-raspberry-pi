#!/bin/bash
set -x

rm -f main
echo
cat main.zig
echo
echo zig version $(zig version)
zig build-exe -target armv7-freestanding-eabihf --linker-script linker.ld main.zig
llvm-objdump --version | head -2
llvm-objdump -x --source main > main.disasm
grep -C4 unknown main.disasm
hexdump -C main | egrep ' 02 0b (dd|4b) ed '
