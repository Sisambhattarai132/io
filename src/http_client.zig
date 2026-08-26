/// HTTP client dispatcher.
///
/// On macOS we use libcurl (linked against /usr/lib/libcurl.4.dylib, always
/// present in the dyld shared cache). This keeps the entire TLS/crypto stack
/// out of the binary — it stays in the system library instead.
///
/// On all other platforms we fall back to Zig's std.http.Client, which has
/// its own TLS implementation compiled directly into the binary.
const builtin = @import("builtin");

const impl = if (builtin.os.tag == .macos)
    @import("http_client_curl.zig")
else
    @import("http_client_std.zig");

pub const HttpError = impl.HttpError;
pub const postChat = impl.postChat;
pub const fetchJson = impl.fetchJson;
pub const postRaw = impl.postRaw;
pub const fetchUrl = impl.fetchUrl;
pub const streamChat = impl.streamChat;
