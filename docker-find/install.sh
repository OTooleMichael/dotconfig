#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.cargo/bin"
TARGET_BIN="$SCRIPT_DIR/target/release/docker-find"
INSTALLED_BIN="$INSTALL_DIR/docker-find"

# Create install directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Check if we need to build/install
if [ ! -f "$TARGET_BIN" ] || [ "$SCRIPT_DIR/src/main.rs" -nt "$TARGET_BIN" ] || [ ! -L "$INSTALLED_BIN" ]; then
    echo "Building docker-find..."
    cd "$SCRIPT_DIR"
    cargo build --release
    
    echo "Installing docker-find to $INSTALLED_BIN"
    rm -f "$INSTALLED_BIN"
    ln -s "$TARGET_BIN" "$INSTALLED_BIN"
    echo "docker-find installed successfully (symlinked)"
else
    echo "docker-find already installed and up-to-date"
fi