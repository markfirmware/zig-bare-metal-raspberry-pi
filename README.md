instruction is at https://github.com/markfirmware/zig-bare-metal-raspberry-pi/blob/aligment-exception/asm.armv8#L1746

serial output follows

    sctlr_el3 c50838
    sctlr_el3 c50878
    sctlr_el3 c50878


    alignment fault data abort exception level 3 (no change) 32 bit instruction at 0x19d8 reading from 0x7ffffb8
    CurrentEL c exception level 3
    esr_el3 96000021 class 0x25
    spsr_el3 600003cd
    elr_el3 19d8
    far_el3 7ffffb8
    sctlr_el3 c50838
    core 0 is now idle in arm exception handler (other cores were already idle from start up)
