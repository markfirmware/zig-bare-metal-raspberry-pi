zig logo is displayed

The frame buffer cursor moves around the screen in response to the tv remote controller buttons. This requires the Consumer Electronics Control (CEC) feature on the tv.

Successfully tested on rpi3b, rpi3b+

Not yet working on armv6 raspberry pi models

Not yet tested on rpi4b

Building
--------

Requires the following patch to lib/zig/std/fmt.zig:

replace

    const digit = a % base;

with
    const digit = a - base * (a / base);

Testing
-------

    zig build qemu -Dqemu

(yes, the -Dqemu is needed at this time)

or

    zig build qemu -Dqemu -Dnodisplay

to omit the frame buffer display
