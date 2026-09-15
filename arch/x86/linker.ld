ENTRY(_start)

SECTIONS
{
    . = 0x00100000;

    .multiboot2 :
    {
        KEEP(*(.multiboot2))
    }

    .text :
    {
        *(.text*)
    }

    .rodata :
    {
        *(.rodata*)
    }

    .data :
    {
        *(.data*)
    }

    .bss :
    {
        *(COMMON)
        *(.bss*)
    }
}
