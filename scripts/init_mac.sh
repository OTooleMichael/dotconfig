#!/bin/bash
set -eo pipefail
brew update
brew install fzf ripgrep bat zoxide neovim zoxide zellij
brew cleanup
brew install --cask font-jetbrains-mono-nerd-font
#install kitty
# curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
ln -s -f ~/.config/.zshrc ~/.zshrc
set e
eval "$(zoxide init zsh)"
set -e
echo "Complete"
