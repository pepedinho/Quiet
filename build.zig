const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    // INFO: define available target for quietOS kernel (for now only x86).
    const target = b.standardTargetOptions(.{
        .whitelist = &.{
            .{ .cpu_arch = .x86, .os_tag = .freestanding },
        },
        .default_target = .{
            .cpu_arch = .x86,
            .os_tag = .freestanding,
        },
    });

    const cpu_arch = target.result.cpu.arch;

    // Arch module
    const arch = b.createModule(.{
        .root_source_file = b.path("arch/arch.zig"),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = false,
    });

    //Driver module
    const drivers = b.createModule(.{
        .root_source_file = b.path("drivers/drivers.zig"),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = false,
        .imports = &.{
            .{ .name = "arch", .module = arch },
        },
    });

    // Kernel module
    const kernel_module = b.createModule(.{
        .root_source_file = b.path("kernel/kernel.zig"),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = false,
        .imports = &.{
            .{ .name = "arch", .module = arch },
            .{ .name = "drivers", .module = drivers },
        },
    });

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", @import("build.zig.zon").version);
    kernel_module.addOptions("b_opt", build_options);

    // Kernel raw binary
    const kernel = b.addExecutable(.{
        .name = "quiet.k",
        .root_module = kernel_module,
    });

    b.installArtifact(kernel);

    const linker_script = switch (cpu_arch) {
        .x86 => b.path("arch/x86/linker.ld"),
        else => @panic("unimplemented arch"),
    };

    kernel.setLinkerScript(linker_script);

    b.installArtifact(kernel);

    const iso_step = b.step("iso-grub", "Build bootable GRUB IMAGE");

    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", "iso-grub/boot/grub" });

    const cp_kernel_cmd = b.addSystemCommand(&.{"cp"});
    cp_kernel_cmd.addArtifactArg(kernel);
    cp_kernel_cmd.addArg("iso-grub/boot/quiet.k");
    cp_kernel_cmd.step.dependOn(&mkdir_cmd.step);

    const cp_grub_cmd = b.addSystemCommand(&.{ "cp", "meta/grub.cfg", "iso-grub/boot/grub/grub.cfg" });
    cp_grub_cmd.step.dependOn(&mkdir_cmd.step);

    const mkrescue = b.addSystemCommand(&.{
        "grub-mkrescue",
        "-o",
        "quiet-grub.iso",
        "iso-grub",
        "--compress=xz",
        "--core-compress=xz",
        "--fonts=",
        "--themes=",
        "--locales=",
        "--modules=",
    });

    mkrescue.step.dependOn(&cp_kernel_cmd.step);
    mkrescue.step.dependOn(&cp_grub_cmd.step);

    iso_step.dependOn(&mkrescue.step);

    const run_step = b.step("run-grub", "Run kernel in QEMU using GRUB ISO");

    const qemu_version = b.fmt("qemu-system-{s}", .{switch (cpu_arch) {
        .aarch64 => "aarch64",
        .arm => "arm",
        .avr => "avr",
        .loongarch64 => "loongarch64",
        .m68k => "m68k",
        .mips => "mips",
        .mips64 => "mips64",
        .mips64el => "mips64el",
        .mipsel => "mipsel",
        .or1k => "or1k",
        .powerpc => "ppc",
        .powerpc64 => "ppc64",
        .riscv32 => "riscv32",
        .riscv64 => "riscv64",
        .s390x => "s390x",
        .sparc => "sparc",
        .sparc64 => "sparc64",
        .x86 => "i386",
        .x86_64 => "x86_64",
        .xtensa => "xtensa",
        else => @panic("unsupported CPU architecture"),
    }});

    const enable_kvm = b.option(bool, "kvm", "Use KVM hardware acceleration with QEMU") orelse true;

    const qemu = b.addSystemCommand(&.{
        qemu_version,
        "-cdrom",
        "quiet-grub.iso",
        "-serial",
        "stdio",
    });
    if (enable_kvm) qemu.addArg("-enable-kvm");
    qemu.step.dependOn(&mkrescue.step);

    run_step.dependOn(&qemu.step);

    const limine_iso_step = b.step("iso-limine", "Build bootable Limine ISO image");

    const limine_dir = "/usr/share/limine";
    const limine_iso_dir = "iso-limine";

    const mkdir_limine = b.addSystemCommand(&.{ "mkdir", "-p", limine_iso_dir ++ "/boot/limine" });

    const cp_kernel_limine = b.addSystemCommand(&.{"cp"});
    cp_kernel_limine.addArtifactArg(kernel);
    cp_kernel_limine.addArg(limine_iso_dir ++ "/boot/quiet.k");
    cp_kernel_limine.step.dependOn(&mkdir_limine.step);

    const cp_limine_conf = b.addSystemCommand(&.{
        "cp", "meta/limine.conf", limine_iso_dir ++ "/boot/limine/limine.conf",
    });

    const cp_limine_splash = b.addSystemCommand(&.{
        "cp", "meta/limine-splash.png", limine_iso_dir ++ "/limine-splash.png",
    });
    cp_limine_splash.step.dependOn(&mkdir_limine.step);

    cp_limine_conf.step.dependOn(&mkdir_limine.step);

    const cp_limine_sys = b.addSystemCommand(&.{
        "cp",                                             limine_dir ++ "/limine-bios.sys",
        limine_iso_dir ++ "/boot/limine/limine-bios.sys",
    });
    cp_limine_sys.step.dependOn(&mkdir_limine.step);

    const cp_limine_bios_cd = b.addSystemCommand(&.{
        "cp",                                                limine_dir ++ "/limine-bios-cd.bin",
        limine_iso_dir ++ "/boot/limine/limine-bios-cd.bin",
    });
    cp_limine_bios_cd.step.dependOn(&mkdir_limine.step);

    const cp_limine_uefi_cd = b.addSystemCommand(&.{
        "cp",                                                limine_dir ++ "/limine-uefi-cd.bin",
        limine_iso_dir ++ "/boot/limine/limine-uefi-cd.bin",
    });
    cp_limine_uefi_cd.step.dependOn(&mkdir_limine.step);

    const xorriso_limine = b.addSystemCommand(&.{
        "xorriso",          "-as",                            "mkisofs",
        "-b",               "boot/limine/limine-bios-cd.bin", "-no-emul-boot",
        "-boot-load-size",  "4",                              "-boot-info-table",
        "--efi-boot",       "boot/limine/limine-uefi-cd.bin", "-efi-boot-part",
        "--efi-boot-image", "--protective-msdos-label",       limine_iso_dir,
        "-o",               "quiet-limine.iso",
    });
    xorriso_limine.step.dependOn(&cp_kernel_limine.step);
    xorriso_limine.step.dependOn(&cp_limine_conf.step);
    xorriso_limine.step.dependOn(&cp_limine_splash.step);
    xorriso_limine.step.dependOn(&cp_limine_sys.step);
    xorriso_limine.step.dependOn(&cp_limine_bios_cd.step);
    xorriso_limine.step.dependOn(&cp_limine_uefi_cd.step);

    const limine_install = b.addSystemCommand(&.{ "limine", "bios-install", "quiet-limine.iso" });
    limine_install.step.dependOn(&xorriso_limine.step);

    limine_iso_step.dependOn(&limine_install.step);

    const run_limine_step = b.step("run-limine", "Run kernel in QEMU using Limine ISO");

    const qemu_limine = b.addSystemCommand(&.{
        qemu_version,
        "-cdrom",
        "quiet-limine.iso",
        "-serial",
        "stdio",
    });
    if (enable_kvm) qemu_limine.addArg("-enable-kvm");
    qemu_limine.step.dependOn(&limine_install.step);

    run_limine_step.dependOn(&qemu_limine.step);
}
