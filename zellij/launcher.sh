#!/bin/zsh
cmd=$(fzf --prompt="› " --height=100% < ~/.config/zellij/commands.txt)
if [ -n "$cmd" ]; then
    echo "$ $cmd"
    echo ""
    zsh -i -c "$cmd" </dev/null
    echo ""
    read -r -s -n1 </dev/tty
fi
