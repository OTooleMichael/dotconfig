#!/bin/bash
set -eo pipefail

echo "Installing homebrew packages..."
brew update
brew install fzf ripgrep bat zoxide neovim zoxide zellij
brew cleanup
brew install --cask font-jetbrains-mono-nerd-font

# Install kitty if not present
if ! command -v kitty &>/dev/null; then
  echo "Installing kitty..."
  curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
fi

# Install Rust if not present
if ! command -v rustc &>/dev/null; then
  echo "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source ~/.cargo/env
fi

# Ensure cargo is in PATH
export PATH="$HOME/.cargo/bin:$PATH"

# Install docker-find
"$HOME/.config/docker-find/install.sh"

ln -s -f ~/.config/.zshrc ~/.zshrc
set e
eval "$(zoxide init zsh)"
set -e
echo "Complete"
