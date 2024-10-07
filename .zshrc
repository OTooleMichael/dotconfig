
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="$HOME/.config/bin:/opt/homebrew/opt/libpq/bin:$PATH"
export VISUAL=nvim
export EDITOR="$VISUAL"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/michaelotoole/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/michaelotoole/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/michaelotoole/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/michaelotoole/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

alias vim="nvim" #vim-alias
alias zj="zellij"
alias zr="zellij run --"
alias zj-clean="zellij ls | awk '/EXITED/ {print $1}' | cstrip | xargs zellij d"

if which fzf > /dev/null 2>&1; then
  source <(fzf --zsh);
  export FZF_COMPLETION_TRIGGER='**'
  alias fz="fzf --preview 'bat --color=always {}'"
  alias fzvim="fz | xargs nvim"
fi

if which zoxide > /dev/null 2>&1; then
    eval "$(zoxide init zsh --cmd cd)"
fi

alias source-rc="source ~/.zshrc"

DOCKER_PATH=$(which docker)
which docker-compose &> /dev/null
_IS_COMPOSE=$?
docker compose --version &> /dev/null
_IS_COMPOSE_SUB=$?

docker_() {
  if [[ "$1" == "compose" ]]; then
    shift
    docker-compose "$@"
  else
    $DOCKER_PATH "$@"
  fi
}

if [[ $_IS_COMPOSE -eq 0 && $_IS_COMPOSE_SUB -ne 0 ]]; then
  alias docker='docker_'
fi



docker-find() {
    if [[ "$1" == "-" ]]; then
      # passing "-" will list all containers and let you choose one
      _LIST=$(docker ps | grep -v '^CONTAINER');
      _PICKED=$(echo $_LIST | fzf);
      echo $_PICKED | awk '{print $1}'
      return
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


on-port-fn() {
  lsof -i ":$1" | tail -n +2
  _RES=$(lsof -i ":$1" | tail -n +2);
  if [[ "$2" == "all" ]]; then
    echo $_RES
    return
  fi;
  _ID=$(echo $_RES | awk '{print $2}')
  if [[ "$2" == "kill" ]]; then
    kill -9 "$_ID"
    return
  fi;
  echo $_ID
}

alias onport='on-port-fn'
alias dnvim="nvim --headless -n -c 'lua require(\"dnvim\").cli()' -- " #dnvim-alias
