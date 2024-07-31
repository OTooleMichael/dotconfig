#!/bin/bash
set -eo pipefail
brew update
brew install fzf ripgrep bat zoxide
brew cleanup
brew install --cask font-jetbrains-mono-nerd-font
#install kitty
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
ln -s ~/.zshrc ~/.config/.zshrc
brew install zoxide
```
### Step 3: Configure Your Shell
After installing Zoxide, you need to configure your shell to use it. The configuration steps depend on the shell you are using (e.g., `bash`, `zsh`, `fish`).
#### For `bash`:
Add the following lines to your `~/.bashrc` or `~/.bash_profile`:
```sh
eval "$(zoxide init bash)"
```
#### For `zsh`:
Add the following lines to your `~/.zshrc`:
```sh
eval "$(zoxide init zsh)"
