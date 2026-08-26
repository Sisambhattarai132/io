const std = @import("std");

/// Braille spinner frames.
pub const frames = [_][]const u8{
    "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
};

/// libc write for raw stderr output from a background thread.
extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
/// libc usleep for spinner animation delay.
pub extern "c" fn usleep(microseconds: c_uint) c_int;

fn rawWrite(s: []const u8) void {
    _ = write(2, s.ptr, s.len);
}

/// A background spinner that animates on stderr while work is in progress.
/// Uses raw posix write to avoid interfering with the std.Io model.
pub const Spinner = struct {
    thread: ?std.Thread = null,
    flag: *std.atomic.Value(bool),

    /// Spawns a spinner thread. Returns null on failure (graceful degradation).
    pub fn start(alloc: std.mem.Allocator) !Spinner {
        const flag = try alloc.create(std.atomic.Value(bool));
        flag.* = .{ .raw = false };
        const t = std.Thread.spawn(.{}, spinLoop, .{flag}) catch |err| {
            alloc.destroy(flag);
            return err;
        };
        return .{ .thread = t, .flag = flag };
    }

    fn spinLoop(flag: *std.atomic.Value(bool)) void {
        var i: usize = 0;
        while (!flag.load(.acquire)) {
            const frame = frames[i % frames.len];
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "\r\x1b[36m❯ {s}\x1b[0m", .{frame}) catch break;
            rawWrite(s);
            _ = usleep(80_000); // 80ms
            i += 1;
        }
        // Clear the spinner line
        rawWrite("\r\x1b[2K");
    }

    /// Signals the spinner thread to stop and joins it.
    pub fn stop(self: *Spinner) void {
        if (self.flag.raw) return; // already stopped
        self.flag.store(true, .release);
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    /// Stops the spinner and frees the heap-allocated flag.
    pub fn deinit(self: *Spinner, alloc: std.mem.Allocator) void {
        self.stop();
        alloc.destroy(self.flag);
    }
};
