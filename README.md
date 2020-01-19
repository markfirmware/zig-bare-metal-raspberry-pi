    
    export fn main() void {
        const err = std.fmt.bufPrint(&buf, "", .{});
    }
    
    var buf: [100]u8 = undefined;
    const std = @import("std");
    
    zig version 0.5.0+72ec44567
    LLVM (http://llvm.org/):
      LLVM version 7.0.1
       110a4:	00 0b d2 ed  <unknown>
       110a8:	02 0b 4b ed  <unknown>
       111d4:	00 0b d1 ed  <unknown>
       111d8:	08 0b cd ed  <unknown>
       11230:	00 0b d0 ed  <unknown>
       11234:	02 0b 4b ed  <unknown>
       11270:	00 0b d0 ed  <unknown>
       11274:	06 0b 4b ed  <unknown>
       1127c:	00 0b d1 ed  <unknown>
       11280:	08 0b 4b ed  <unknown>
    000010a0  48 d0 4d e2 00 0b d2 ed  02 0b 4b ed 08 30 4b e2  |H.M.......K..0K.|
    000011d0  b8 32 cd e1 00 0b d1 ed  08 0b cd ed 0b d0 a0 e1  |.2..............|
    00001230  00 0b d0 ed 02 0b 4b ed  24 10 1b e5 04 10 91 e5  |......K.$.......|
    00001270  00 0b d0 ed 06 0b 4b ed  28 10 9d e5 00 0b d1 ed  |......K.(.......|
    00001280  08 0b 4b ed 47 00 00 eb  24 00 1b e5 28 10 9d e5  |..K.G...$...(...|
