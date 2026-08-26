# io

A tiny, self-contained LLM coding agent. One binary, 180+ providers, zero runtime dependencies.

`io` is a single-file-distributed terminal agent that talks to any OpenAI-compatible LLM provider. It supports streaming chat, tool use (read/write/edit files, grep, glob, bash, web search/fetch), session persistence, and first-run interactive setup — all in a ~1 MB binary with no external libraries beyond libc.

## Features

- **180+ providers** — OpenAI, Anthropic, Google, Groq, Grok, Mistral, DeepSeek, OpenRouter, Together, and 170+ more via the [models.dev](https://models.dev) registry. Plus local Ollama.
- **Tool use** — read/write/edit files, list directories, grep, glob, bash execution, web search, web fetch.
- **Streaming** — SSE streaming with retry/backoff for 429/500/502/503/504.
- **Sessions** — auto-saved to `~/.ai/sessions.jsonl`. Resume by ID or `last`.
- **Interactive setup** — first-run wizard with searchable provider/model picker.
- **Cross-platform** — macOS, Linux, Windows. x86_64 + ARM64.
- **Zero dependencies** — static binaries on Linux (musl), system libcurl on macOS, built-in TLS on Windows.

## Install

### From source (Zig 0.16.0+)

```sh
git clone https://github.com/rexadbapp/io.git
cd io
zig build -Doptimize=ReleaseFast
# Binary: zig-out/bin/io
```

### Cross-compile all platforms

```sh
zig build cross
# Binaries in zig-out/dist/:
#   io-darwin-arm64
#   io-darwin-x86_64
#   io-linux-x86_64
#   io-linux-aarch64
#   io-windows-x86_64.exe
#   io-windows-aarch64.exe
```

## Usage

```sh
# Interactive chat (default)
io

# First-time setup: choose provider & model
io setup

# One-shot: ask a question
io ask "explain this codebase"

# Resume a session
io resume last
io resume 42

# List sessions
io sessions

# List providers
io providers

# List models for current provider
io models
```

### Options

```
  -p, --provider <name>    Provider (openai, anthropic, google, groq, ...)
  -m, --model <name>       Model name (defaults to provider default)
  -k, --api-key <key>      API key (overrides env var)
  -s, --system <prompt>    System prompt
  -h, --help               Show help
  -v, --version            Show version
```

### Environment

```
  AI_PROVIDER              Default provider
  AI_MODEL                 Default model
  AI_API_KEY               Default API key
  AI_DATA_DIR              Data directory (default: ~/.ai)
  AI_SYSTEM_PROMPT         System prompt
  OPENAI_API_KEY           OpenAI key
  ANTHROPIC_API_KEY        Anthropic key
  GOOGLE_API_KEY           Google key
  ... (see: io providers)
```

## Architecture

```
src/
  main.zig            Entry point, CLI parsing, subcommands
  chat.zig            Interactive chat REPL, streaming, live UI
  setup.zig           First-run interactive setup wizard
  config.zig          Config loading (env vars + file)
  provider.zig        180+ provider definitions (URLs, auth, models)
  registry.zig        models.dev live model catalog fetcher
  session.zig         JSONL session persistence
  http_client.zig     HTTP dispatcher (libcurl on macOS, std.http elsewhere)
  http_client_curl.zig  libcurl implementation (macOS)
  http_client_std.zig   std.http.Client implementation (Linux/Windows)
  term.zig            Cross-platform terminal abstraction (termios/Win32 console)
  tools.zig           Agent tool execution (read/write/edit/grep/glob/bash/web)
  response.zig        SSE stream parser & tool-call extraction
  json.zig             Minimal JSON encoder/decoder
  markdown.zig         Terminal markdown renderer
  spinner.zig         Loading spinner animation
  keycap.zig          Dev utility: raw key capture (POSIX-only)
```

### Platform notes

| Platform | HTTP/TLS | Terminal | Binary size |
|---|---|---|---|
| macOS (arm64/x86_64) | System libcurl (dyld shared cache) | termios | ~700 KB |
| Linux (x86_64/aarch64) | std.http.Client (built-in TLS) | termios | ~1.3 MB (static) |
| Windows (x86_64/aarch64) | std.http.Client (built-in TLS) | Win32 Console API | ~1.5 MB |

On macOS, linking against the system libcurl keeps the entire TLS/crypto stack out of the binary — it lives in the system library. On Linux and Windows, Zig's `std.http.Client` compiles its own TLS implementation directly into the binary, so no external libraries are needed at runtime.

## License

MIT
