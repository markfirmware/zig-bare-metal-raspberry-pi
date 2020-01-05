testing __udivmodsi4

    export fn main() void {
        var x: u32 = 1;
        var y: u32 = 2;
        var z: u32 = x % y;
    }

    zig version 0.5.0+508a8980b

    LLVM (http://llvm.org/):
      LLVM version 7.0.1
       11264:	04 20 82 e2 	add	r2, r2, #4
       11268:	e2 ff ff eb 	bl	#-120 <__udivmodsi4>
       1126c:	08 00 8d e5 	str	r0, [sp, #8]
    ; return result;
       11270:	02 0b dd ed  <unknown>
       11274:	02 0b 4b ed  <unknown>
       11278:	08 00 1b e5 	ldr	r0, [r11, #-8]
       1127c:	04 10 1b e5 	ldr	r1, [r11, #-4]
       11280:	0b d0 a0 e1 	mov	sp, r11
       11284:	00 88 bd e8 	pop	{r11, pc}

    00001270  02 0b dd ed 02 0b 4b ed  08 00 1b e5 04 10 1b e5  |......K.........|
