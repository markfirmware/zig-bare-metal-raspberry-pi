Privacy
-------

Bluetooth signals are collected and displayed on the screen

Function
--------

zig logo is displayed

The frame buffer cursor moves around the screen in response to the tv remote controller buttons. This requires the Consumer Electronics Control (CEC) feature on the tv.

Presently only working on rpi3b+ due to some code generation issues

Not yet working on armv6 raspberry pi models

Not yet tested on rpi4b

Testing
-------

    zig build qemu -Dqemu

(yes, the -Dqemu is needed at this time)

or

    zig build qemu -Dqemu -Dnodisplay

to omit the frame buffer display
