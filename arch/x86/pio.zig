pub fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

pub fn outb(port: u16, b: u8) void {
    asm volatile ("outb %[b], %[port]"
        :
        : [b] "{al}" (b),
          [port] "N{dx}" (port),
    );
}

pub fn ioWait() void {
    outb(0x80, 0);
}
