const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .stack_check = false,
        .stack_protector = false,
        .omit_frame_pointer = true,
        .unwind_tables = .none,
        .error_tracing = false,
        .strip = optimize != .Debug,
    });

    // On macOS, link the system libcurl (always present in the dyld shared
    // cache). This keeps the entire TLS/crypto stack out of the binary.
    // On other platforms, std.http.Client provides its own TLS.
    if (target.result.os.tag == .macos) {
        // The libcurl .tbd stub lives in the macOS SDK's usr/lib.
        // Resolve the SDK path via xcrun at build time.
        const sdk_path = std.mem.trimEnd(u8, b.run(&.{
            "xcrun", "--sdk", "macosx", "--show-sdk-path",
        }), "\r\n");
        exe_mod.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/usr/lib", .{sdk_path}) });
        exe_mod.linkSystemLibrary("curl", .{});
    }

    const exe = b.addExecutable(.{
        .name = "io",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    // Standalone key capture utility: io-keycap (POSIX-only — uses termios.h)
    if (target.result.os.tag != .windows) {
        const keycap_mod = b.createModule(.{
            .root_source_file = b.path("src/keycap.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const keycap_exe = b.addExecutable(.{
            .name = "io-keycap",
            .root_module = keycap_mod,
        });
        b.installArtifact(keycap_exe);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run io");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_tests.step);

    // ── Cross-platform build: `zig build cross` ─────────────────────────────
    // Builds io for all supported targets and installs them to dist/ with
    // platform-specific names (io-darwin-arm64, io-linux-x86_64, etc.).
    // macOS uses libcurl; Linux/Windows use std.http.Client's built-in TLS.
    const cross_step = b.step("cross", "Build io for all platforms into dist/");
    const cross_targets = [_]CrossTarget{
        .{ .triple = "aarch64-macos-none", .name = "io-darwin-arm64", .ext = "" },
        .{ .triple = "x86_64-macos-none", .name = "io-darwin-x86_64", .ext = "" },
        .{ .triple = "x86_64-linux-musl", .name = "io-linux-x86_64", .ext = "" },
        .{ .triple = "aarch64-linux-musl", .name = "io-linux-aarch64", .ext = "" },
        .{ .triple = "x86_64-windows-gnu", .name = "io-windows-x86_64", .ext = ".exe" },
        .{ .triple = "aarch64-windows-gnu", .name = "io-windows-aarch64", .ext = ".exe" },
    };
    for (cross_targets) |ct| {
        const query = std.Target.Query.parse(.{ .arch_os_abi = ct.triple }) catch continue;
        const resolved = b.resolveTargetQuery(query);
        const t = resolved.result.os.tag;
        const cross_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = resolved,
            .optimize = .ReleaseFast,
            .link_libc = true,
            .stack_check = false,
            .stack_protector = false,
            .omit_frame_pointer = true,
            .unwind_tables = .none,
            .error_tracing = false,
            .strip = true,
        });
        if (t == .macos) {
            const sdk_path = std.mem.trimEnd(u8, b.run(&.{
                "xcrun", "--sdk", "macosx", "--show-sdk-path",
            }), "\r\n");
            cross_mod.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/usr/lib", .{sdk_path}) });
            cross_mod.linkSystemLibrary("curl", .{});
        }
        // Use base name without extension — Zig appends .exe on Windows.
        const cross_exe = b.addExecutable(.{
            .name = ct.name,
            .root_module = cross_mod,
        });
        cross_step.dependOn(&b.addInstallArtifact(cross_exe, .{
            .dest_dir = .{ .override = .{ .custom = "dist" } },
        }).step);
    }
}

const CrossTarget = struct {
    triple: []const u8,
    name: []const u8,
    ext: []const u8,
};
