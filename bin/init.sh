#!/bin/bash
#
set -e
echo 'export PATH="$PATH:$HOME/.config/bin"' >>~/.bash_profile
source ~/.bash_profile
chmod +x $HOME/.config/bin/dnvim
