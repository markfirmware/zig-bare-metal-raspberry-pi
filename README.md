zig logo is displayed

The frame buffer cursor moves around the screen in response to the tv remote controller buttons. This requires a Cosumer Electronics Control (CEC) on the tv.

Successfully tested on rpi3b, rpi3b+

Not yet working on armv6 raspberry pi models

Building
--------

Requires the following patch to lib/zig/std/fmt.zig:

replace

    const digit = a % base;

with
    const digit = a - base * (a / base);

