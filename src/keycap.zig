const std = @import("std");
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("stdio.h");
});

/// Key capture utility. Run: io-keycap
/// Press keys to see their raw byte sequences. Press 'q' to quit.
/// POSIX-only (macOS/Linux). Not built on Windows — see build.zig.
pub fn main() !void {
    const fd = std.posix.STDIN_FILENO;
    var old: c.termios = undefined;
    _ = c.tcgetattr(fd, &old);
    var raw = old;
    raw.c_lflag &= ~@as(c_uint, c.ECHO | c.ICANON);
    raw.c_iflag &= ~@as(c_uint, c.IXON | c.ICRNL);
    raw.c_cc[c.VMIN] = 1;
    raw.c_cc[c.VTIME] = 0;
    _ = c.tcsetattr(fd, c.TCSANOW, &raw);
    defer _ = c.tcsetattr(fd, c.TCSANOW, &old);

    _ = c.printf("io keycap. Press keys (q to quit).\r\n");

    var buf: [16]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &buf) catch break;
        if (n == 0) break;
        _ = c.printf("%d bytes:", @as(c_int, @intCast(n)));
        for (buf[0..n]) |b| {
            _ = c.printf(" 0x%02x", @as(c_uint, b));
        }
        _ = c.printf("\r\n");
        if (buf[0] == 'q' and n == 1) break;
    }
}
