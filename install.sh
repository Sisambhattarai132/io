#!/usr/bin/env sh
# io install script — downloads the latest release binary for your platform.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/rexadbapp/io/master/install.sh | sh
#
# Or to install a specific version:
#   curl -fsSL https://raw.githubusercontent.com/rexadbapp/io/master/install.sh | sh -s -- v0.1.0
#
# Options:
#   --prefix <dir>   Install directory (default: ~/.local/bin)
#   --version <ver>  Release version to install (default: latest)
#   -h, --help       Show this help

set -eu

REPO="rexadbapp/io"
PREFIX="${PREFIX:-$HOME/.local/bin}"
VERSION="latest"

# --- Parse args ---
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)   PREFIX="$2"; shift 2 ;;
        --version)  VERSION="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
io install script

Usage: install.sh [OPTIONS] [VERSION]

Options:
  --prefix <dir>   Install directory (default: ~/.local/bin)
  --version <ver>  Release version (default: latest)
  -h, --help       Show this help
EOF
            exit 0 ;;
        v*)         VERSION="$1"; shift ;;
        *)          echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Detect platform ---
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Darwin) PLATFORM="darwin" ;;
    Linux)  PLATFORM="linux" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

case "$ARCH" in
    x86_64|amd64) ARCHITECTURE="x86_64" ;;
    arm64)        ARCHITECTURE="arm64" ;;
    aarch64)
        # macOS release uses "arm64", Linux uses "aarch64"
        if [ "$PLATFORM" = "darwin" ]; then
            ARCHITECTURE="arm64"
        else
            ARCHITECTURE="aarch64"
        fi
        ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

# Windows binaries have .exe suffix
SUFFIX=""
if [ "$PLATFORM" = "windows" ]; then
    SUFFIX=".exe"
fi

BINARY="io-${PLATFORM}-${ARCHITECTURE}${SUFFIX}"

# --- Resolve version ---
if [ "$VERSION" = "latest" ]; then
    echo "Fetching latest version..."
    VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
    if [ -z "$VERSION" ]; then
        echo "Could not determine latest version." >&2
        exit 1
    fi
fi

echo "Installing io ${VERSION} for ${PLATFORM}/${ARCHITECTURE}..."

# --- Download ---
URL="https://github.com/${REPO}/releases/download/${VERSION}/${BINARY}"
TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

echo "Downloading ${URL}"
if ! curl -fSL --progress-bar -o "$TMPFILE" "$URL"; then
    echo "Download failed." >&2
    exit 1
fi

# --- Install ---
mkdir -p "$PREFIX"
INSTALL_PATH="${PREFIX}/io${SUFFIX}"
mv "$TMPFILE" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

echo ""
echo "Installed io to ${INSTALL_PATH}"

# --- Verify it runs ---
if command -v "$INSTALL_PATH" >/dev/null 2>&1; then
    "$INSTALL_PATH" --version || true
fi

# --- PATH check ---
case ":$PATH:" in
    *":${PREFIX}:"*) ;;
    *)
        echo ""
        echo "⚠  ${PREFIX} is not in your PATH."
        echo "   Add this to your shell profile:"
        echo "       export PATH=\"${PREFIX}:\$PATH\""
        ;;
esac

echo ""
echo "Done. Run 'io' to start chatting."
