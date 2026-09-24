const gdt = @import("gdt.zig");

pub const IDT_ENTRIES = 256;

const GateType = enum(u4) {
    task_gate = 0x5,
    interrupt_16 = 0x6,
    trap_16 = 0x7,
    interrupt_32 = 0xE,
    trap_32 = 0xF,
};

// see: https://wiki.osdev.org/Interrupt_Descriptor_Table#IDT_items
pub const Interrupt = enum(u8) {
    divide_error = 0,
    debug = 1,
    nmi = 2,
    breakpoint = 3,
    overflow = 4,
    bound_range_exceeded = 5,
    invalid_opcode = 6,
    device_not_available = 7,
    double_fault = 8,
    coprocessor_segment_overrun = 9,
    invalid_tss = 10,
    segment_not_present = 11,
    stack_segment_fault = 12,
    general_protection = 13,
    page_fault = 14,
    //reserved
    floating_point_error = 16,
    alignment_check = 17,
    machine_check = 18,
    floating_point_exception = 19,
    virtualization_exception = 20,
    control_protection = 21,
    // reserved
    // N/A
    _,
};

const IdtDescriptor = packed struct {
    size: u16,
    offset: u32,
};

const GateDescriptor = packed struct(u64) {
    offset_low: u16,
    selector: u16,
    reserved_0: u8 = 0,
    gate_type: GateType,
    reserved_1: u1 = 0,
    ring: u2,
    present: u1,
    offset_high: u16,

    const nil: @This() = @bitCast(@as(u64, 0));

    fn make(offset: u32, selector: u16, ring: u2, gate_type: GateType) @This() {
        return .{
            .offset_low = @truncate(offset),
            .selector = selector,
            .present = 1,
            .ring = ring,
            .gate_type = gate_type,
            .offset_high = @truncate(offset >> 16),
        };
    }
};

pub const InterruptFrame = packed struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    int_no: u32,
    err: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
    esp_ring: u32 = 0,
    ss_ring: u32 = 0,
};

pub const InterruptHandler = *const fn (*InterruptFrame) void;

var handlers: [IDT_ENTRIES]?InterruptHandler = @splat(null);
var idt_gates: [IDT_ENTRIES]GateDescriptor = @splat(GateDescriptor.nil);

pub fn hasErrorCode(int: Interrupt) bool {
    return switch (int) {
        .double_fault, .invalid_tss, .stack_segment_fault, .page_fault, .segment_not_present, .general_protection, .alignment_check, .control_protection => true,
        else => false,
    };
}

fn generateStub(comptime int: Interrupt) *const fn () callconv(.naked) void {
    return &struct {
        fn stub() callconv(.naked) void {
            if (!comptime hasErrorCode(int)) {
                asm volatile ("push $0");
            }
            asm volatile ("push %[int]"
                :
                : [int] "i" (@as(u32, @intFromEnum(int))),
            );
            asm volatile ("jmp isrStub");
        }
    }.stub;
}

const isr_stub = blk: {
    var stubs: [IDT_ENTRIES]*const fn () callconv(.naked) void = undefined;
    for (0..IDT_ENTRIES) |i| {
        stubs[i] = generateStub(@enumFromInt(i));
    }
    break :blk stubs;
};

export fn isrStub() callconv(.naked) void {
    asm volatile ("pusha");

    asm volatile (
        \\mov %%esp, %%eax
        \\push %%eax
        \\call interruptDispatch
        \\add $4, %%esp
    );

    asm volatile (
        \\popa
        \\add $8, %%esp
        \\iret
    );
}

export fn interruptDispatch(frame: *InterruptFrame) void {
    if (frame.int_no < IDT_ENTRIES) {
        if (handlers[frame.int_no]) |handler| {
            handler(frame);
        }
    }
}

pub fn registerHandler(int: Interrupt, handler: InterruptHandler) void {
    handlers[@intFromEnum(int)] = handler;
}

pub fn init() void {
    for (0..IDT_ENTRIES) |i| {
        const addr = @intFromPtr(isr_stub[i]);
        idt_gates[i] = GateDescriptor.make(addr, gdt.KERNEL_CODE_SEGMENT, 0, .interrupt_32);
    }

    const descriptor = IdtDescriptor{
        .size = @sizeOf(@TypeOf(idt_gates)) - 1,
        .offset = @intFromPtr(&idt_gates),
    };

    asm volatile ("lidt (%[ptr])"
        :
        : [ptr] "r" (&descriptor),
    );
}

pub fn enableInterrupts() void {
    asm volatile ("sti");
}

pub fn disableInterrupts() void {
    asm volatile ("cli");
}
