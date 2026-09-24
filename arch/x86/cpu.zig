pub fn hlt() noreturn {
    while (true) asm volatile ("cli; hlt");
}
