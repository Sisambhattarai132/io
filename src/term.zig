/// Cross-platform terminal abstraction.
///
/// On POSIX (macOS, Linux, BSD) we use termios + poll + read + ioctl(TIOCGWINSZ).
/// On Windows we use the Win32 Console API: GetConsoleMode/SetConsoleMode,
/// GetConsoleScreenBufferInfo, ReadFile on the console handle, and
/// WaitForSingleObject for poll-equivalent timeout behavior.
///
/// All the rest of io (chat.zig, setup.zig) calls only these functions,
/// never the raw POSIX or Win32 APIs directly.

const std = @import("std");
const builtin = @import("builtin");

pub const TermGuard = struct {
    inner: Inner,

    /// Enter raw terminal mode on stdin. Returns a guard that restores the
    /// original settings on `disable()`.
    pub fn enable() !TermGuard {
        return .{ .inner = try Inner.enable() };
    }

    pub fn disable(self: *TermGuard) void {
        self.inner.disable();
    }
};

// ── Platform-specific inner implementation ──────────────────────────────────

const posix = std.posix;

const Inner = if (builtin.os.tag == .windows)
    WindowsTermGuard
else
    PosixTermGuard;

// ── POSIX implementation ────────────────────────────────────────────────────

/// VMIN/VTIME indices differ per platform (Linux: 6/5, macOS/BSD: 16/17).
const VMIN: usize = switch (builtin.os.tag) {
    .linux => 6,
    else => 16,
};
const VTIME: usize = switch (builtin.os.tag) {
    .linux => 5,
    else => 17,
};

const PosixTermGuard = struct {
    original: posix.termios,

    fn enable() !PosixTermGuard {
        const fd = posix.STDIN_FILENO;
        const orig = try posix.tcgetattr(fd);

        var raw = orig;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;

        raw.cflag.CSIZE = .CS8;

        if (VMIN < raw.cc.len and VTIME < raw.cc.len) {
            raw.cc[VMIN] = 1;
            raw.cc[VTIME] = 0;
        }

        try posix.tcsetattr(fd, .FLUSH, raw);
        return .{ .original = orig };
    }

    fn disable(self: *PosixTermGuard) void {
        posix.tcsetattr(posix.STDIN_FILENO, .NOW, self.original) catch {};
    }
};

// ── Windows implementation ─────────────────────────────────────────────────

const w = std.os.windows;

// Console mode flags
const ENABLE_PROCESSED_INPUT: w.DWORD = 0x0001;
const ENABLE_LINE_INPUT: w.DWORD = 0x0002;
const ENABLE_ECHO_INPUT: w.DWORD = 0x0004;
const ENABLE_VIRTUAL_TERMINAL_INPUT: w.DWORD = 0x0200;
const ENABLE_VIRTUAL_TERMINAL_PROCESSING: w.DWORD = 0x0004;

// GetStdHandle codes
const STD_INPUT_HANDLE: w.DWORD = @bitCast(@as(i32, -10));
const STD_OUTPUT_HANDLE: w.DWORD = @bitCast(@as(i32, -11));

// WaitForSingleObject return values
const WAIT_OBJECT_0: w.DWORD = 0x00000000;
const WAIT_TIMEOUT: w.DWORD = 0x00000102;
const INFINITE: w.DWORD = 0xFFFFFFFF;

extern "kernel32" fn GetStdHandle(nStdHandle: w.DWORD) callconv(.winapi) ?w.HANDLE;
extern "kernel32" fn GetConsoleMode(hConsoleHandle: w.HANDLE, lpMode: *w.DWORD) callconv(.winapi) w.BOOL;
extern "kernel32" fn SetConsoleMode(hConsoleHandle: w.HANDLE, dwMode: w.DWORD) callconv(.winapi) w.BOOL;
extern "kernel32" fn WaitForSingleObject(hHandle: w.HANDLE, dwMilliseconds: w.DWORD) callconv(.winapi) w.DWORD;
extern "kernel32" fn ReadFile(
    hFile: w.HANDLE,
    lpBuffer: *anyopaque,
    nNumberOfBytesToRead: w.DWORD,
    lpNumberOfBytesRead: *w.DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) w.BOOL;

const COORD = extern struct {
    X: i16,
    Y: i16,
};

const SMALL_RECT = extern struct {
    Left: i16,
    Top: i16,
    Right: i16,
    Bottom: i16,
};

const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: w.WORD,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};

extern "kernel32" fn GetConsoleScreenBufferInfo(
    hConsoleOutput: w.HANDLE,
    lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO,
) callconv(.winapi) w.BOOL;

const WindowsTermGuard = struct {
    orig_in_mode: w.DWORD,
    orig_out_mode: w.DWORD,
    stdin_handle: w.HANDLE,
    stdout_handle: w.HANDLE,

    fn enable() !WindowsTermGuard {
        const stdin_h = GetStdHandle(STD_INPUT_HANDLE) orelse return error.NoStdin;
        const stdout_h = GetStdHandle(STD_OUTPUT_HANDLE) orelse return error.NoStdout;

        var in_mode: w.DWORD = 0;
        if (!GetConsoleMode(stdin_h, &in_mode).toBool()) return error.GetConsoleModeFailed;
        var out_mode: w.DWORD = 0;
        if (!GetConsoleMode(stdout_h, &out_mode).toBool()) return error.GetConsoleModeFailed;

        // Virtual terminal input passes escape sequences through as-is
        // (like POSIX raw mode), so our existing ESC-sequence parsing works.
        const new_in_mode: w.DWORD = ENABLE_VIRTUAL_TERMINAL_INPUT;
        // Enable ANSI escape sequence output processing.
        const new_out_mode: w.DWORD = out_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING;

        if (!SetConsoleMode(stdin_h, new_in_mode).toBool()) return error.SetConsoleModeFailed;
        if (!SetConsoleMode(stdout_h, new_out_mode).toBool()) return error.SetConsoleModeFailed;

        return .{
            .orig_in_mode = in_mode,
            .orig_out_mode = out_mode,
            .stdin_handle = stdin_h,
            .stdout_handle = stdout_h,
        };
    }

    fn disable(self: *WindowsTermGuard) void {
        _ = SetConsoleMode(self.stdin_handle, self.orig_in_mode);
        _ = SetConsoleMode(self.stdout_handle, self.orig_out_mode);
    }
};

// ── Cross-platform terminal size ────────────────────────────────────────────

/// Returns terminal width in columns, or 80 if undeterminable.
pub fn width() usize {
    if (builtin.os.tag == .windows) return windowsWidth();
    return posixWidth();
}

/// Returns terminal height in rows, or 24 if undeterminable.
pub fn height() usize {
    if (builtin.os.tag == .windows) return windowsHeight();
    return posixHeight();
}

extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;

fn posixWidth() usize {
    var ws: posix.winsize = undefined;
    const TIOCGWINSZ: c_ulong = switch (builtin.os.tag) {
        .linux => 0x5413,
        else => 0x40087468, // macOS/BSD
    };
    if (ioctl(posix.STDIN_FILENO, TIOCGWINSZ, &ws) != 0 or ws.col == 0) return 80;
    return ws.col;
}

fn posixHeight() usize {
    var ws: posix.winsize = undefined;
    const TIOCGWINSZ: c_ulong = switch (builtin.os.tag) {
        .linux => 0x5413,
        else => 0x40087468, // macOS/BSD
    };
    if (ioctl(posix.STDIN_FILENO, TIOCGWINSZ, &ws) != 0 or ws.row == 0) return 24;
    return ws.row;
}

fn windowsWidth() usize {
    const stdout_h = GetStdHandle(STD_OUTPUT_HANDLE) orelse return 80;
    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (!GetConsoleScreenBufferInfo(stdout_h, &info).toBool()) return 80;
    const w_val: usize = @intCast(info.srWindow.Right - info.srWindow.Left + 1);
    if (w_val == 0) return 80;
    return w_val;
}

fn windowsHeight() usize {
    const stdout_h = GetStdHandle(STD_OUTPUT_HANDLE) orelse return 24;
    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (!GetConsoleScreenBufferInfo(stdout_h, &info).toBool()) return 24;
    const h_val: usize = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1);
    if (h_val == 0) return 24;
    return h_val;
}

// ── Cross-platform stdin reading with timeout ───────────────────────────────

/// Polls stdin for up to `timeout_ms`. Returns number of bytes read into
/// `buf`, or 0 on timeout / error.
pub fn readStdinTimeout(buf: []u8, timeout_ms: u32) usize {
    if (builtin.os.tag == .windows) return windowsReadTimeout(buf, timeout_ms);
    return posixReadTimeout(buf, timeout_ms);
}

fn posixReadTimeout(buf: []u8, timeout_ms: u32) usize {
    const pollfd = posix.pollfd;
    const POLLIN = posix.POLL.IN;
    var pfds = [_]pollfd{.{ .fd = posix.STDIN_FILENO, .events = POLLIN, .revents = 0 }};
    const ret = posix.poll(&pfds, @intCast(timeout_ms)) catch return 0;
    if (ret == 0) return 0;
    if ((pfds[0].revents & POLLIN) == 0) return 0;
    const n = posix.read(posix.STDIN_FILENO, buf) catch return 0;
    if (n == 0) return 0;
    return n;
}

fn windowsReadTimeout(buf: []u8, timeout_ms: u32) usize {
    const stdin_h = GetStdHandle(STD_INPUT_HANDLE) orelse return 0;
    const wait = WaitForSingleObject(stdin_h, timeout_ms);
    if (wait != WAIT_OBJECT_0) return 0;
    var bytes_read: w.DWORD = 0;
    if (!ReadFile(stdin_h, buf.ptr, @intCast(buf.len), &bytes_read, null).toBool()) return 0;
    return @intCast(bytes_read);
}

/// Reads up to `buf.len` bytes from stdin (blocking, no timeout).
/// Returns the number of bytes actually read, or 0 on error / EOF.
pub fn readStdin(buf: []u8) usize {
    if (builtin.os.tag == .windows) {
        const stdin_h = GetStdHandle(STD_INPUT_HANDLE) orelse return 0;
        var bytes_read: w.DWORD = 0;
        if (!ReadFile(stdin_h, buf.ptr, @intCast(buf.len), &bytes_read, null).toBool()) return 0;
        return @intCast(bytes_read);
    }
    const n = posix.read(posix.STDIN_FILENO, buf) catch return 0;
    if (n == 0) return 0;
    return n;
}

/// Reads a single byte from stdin (blocking). Returns the byte, or null on
/// error / EOF.
pub fn readByte() ?u8 {
    var b: [1]u8 = undefined;
    if (readStdin(&b) == 0) return null;
    return b[0];
}

/// Polls stdin for up to `timeout_ms`. Returns true if data is available.
pub fn stdinReady(timeout_ms: u32) bool {
    if (builtin.os.tag == .windows) {
        const stdin_h = GetStdHandle(STD_INPUT_HANDLE) orelse return false;
        return WaitForSingleObject(stdin_h, timeout_ms) == WAIT_OBJECT_0;
    }
    const pollfd = posix.pollfd;
    const POLLIN = posix.POLL.IN;
    var pfds = [_]pollfd{.{ .fd = posix.STDIN_FILENO, .events = POLLIN, .revents = 0 }};
    const ret = posix.poll(&pfds, @intCast(timeout_ms)) catch return false;
    return ret != 0 and (pfds[0].revents & POLLIN) != 0;
}
