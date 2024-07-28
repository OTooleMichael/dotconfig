
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="$HOME/.config/bin:/opt/homebrew/opt/libpq/bin:$PATH"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/michaelotoole/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/michaelotoole/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/michaelotoole/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/michaelotoole/Downloads/google-cloud-sdk/completion.zsh.inc'; fi
alias vim="nvim" #vim-alias
alias zj="zellij"
alias zr="zellij run --"
alias zj-clean="zellij ls | awk '/EXITED/ {print $1}' | cstrip | xargs zellij d"
source <(fzf --zsh);
export FZF_COMPLETION_TRIGGER='**'
alias fz="fzf --preview 'bat --color=always {}'"
alias fzvim="fz | xargs nvim"

docker-find() {
    if [[ "$1" == "-" ]]; then
      # passing "-" will list all containers and let you choose one
      return docker ps | fzf | awk '{print $1}'
    fi
    docker ps -q -f "name=$1"
}

docker-enter() {
    _COMMAND=${2:-bash}
    docker exec -it $(docker-find $1) $_COMMAND
}

alias denter='docker-enter'
alias dfind='docker-find'

copy-docker() {
  docker_location="/tmp/dnvim_copy_watcher.txt"
  docker exec -i $1 cat $docker_location | pbcopy
}
alias dcopy='copy-docker'

autoload -U colors && colors
PROMPT="%~%: "
alias cstrip='sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g"'

alias dnvim="nvim --headless -n -c 'lua require(\"dnvim\").cli()' -- " #dnvim-alias
