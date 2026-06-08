export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="$HOME/.config/bin:/opt/homebrew/opt/libpq/bin:$PATH"
export VISUAL=nvim
export EDITOR="$VISUAL"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '~/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '~/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '~/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '~/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

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

# Kills orphaned rust-analyzer after nvim exits (crash or clean)
function nvim() {
  command nvim "$@"
  for pid in $(pgrep -x rust-analyzer 2>/dev/null); do
    ppid=$(ps -o ppid= -p $pid 2>/dev/null | tr -d ' ')
    parent_cmd=$(ps -o comm= -p $ppid 2>/dev/null)
    [[ "$parent_cmd" != "nvim" ]] && kill "$pid" 2>/dev/null
  done
}
alias zj="zellij"
alias zr="zellij run --"
alias zj-clean="zellij ls | awk '/EXITED/ {print $1}' | cstrip | xargs zellij d"


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

git-sync_() {
  target_branch=$(git branch | awk '/master|main/ {print $NF}');
  if [ -z "$target_branch" ]; then
    echo "No master or main branch found."
    return 1;
  fi;
  git checkout $target_branch;
  git stash;
  git pull;
  git stash pop;
}

alias git-sync="git-sync_"


docker-enter() {
    local container_pattern="$1"
    local command="${2:-bash}"

    if [[ -z "$container_pattern" ]]; then
        # No pattern provided - use smart default, fallback to fzf
        local container_id=$(docker-find f)
        if [[ -z "$container_id" ]]; then
            echo "No container found"
            return 1
        fi
        docker exec -it "$container_id" "$command"
        return $?
    fi

    # Pattern provided - find matching container
    local container_id=$(docker-find f "$container_pattern" | head -1)
    if [[ -z "$container_id" ]]; then
        echo "Container matching '$container_pattern' not found"
        return 1
    fi
    docker exec -it "$container_id" "$command"
}

docker-exec() {
    local container_pattern="$1"
    shift

    if [[ -z "$container_pattern" ]]; then
        echo "Usage: dexec <container_pattern> <command...>"
        return 1
    fi

    local container_id=$(docker-find f "$container_pattern" | head -1)
    if [[ -z "$container_id" ]]; then
        echo "Container matching '$container_pattern' not found"
        return 1
    fi

    docker exec -it "$container_id" "$@"
}

alias denter='docker-enter'
alias dexec='docker-exec'
alias dfind='docker-find f'

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



### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
export PATH="/Users/michaelotoole/.rd/bin:$PATH"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

# Go binary path (added by dx installer)
export PATH="$PATH:/Users/michaelotoole/go/bin"

# bun completions
[ -s "/Users/michaelotoole/.bun/_bun" ] && source "/Users/michaelotoole/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# dx shell completion
eval "$(dx completion zsh)"

# BEGIN dx claude-code-otel
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=https://claude-code-otel.internal.corp.traderepublic.com
export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative
export OTEL_RESOURCE_ATTRIBUTES="user.email=michael.o.toole@traderepublic.com"
# END dx claude-code-otel

# >>> dx ai-kit (managed — do not edit) >>>
[ -r /Users/michaelotoole/.traderepublic/ai-kit/ai-kit-env.sh ] && source /Users/michaelotoole/.traderepublic/ai-kit/ai-kit-env.sh
# <<< dx ai-kit <<<
alias prrr="PYTHONUNBUFFERED=1 ~/projects/prrr/.venv/bin/prrr"
alias slack-pull="~/.config/slack-pull/.venv/bin/slack-pull"

if which fzf > /dev/null 2>&1; then
  source <(fzf --zsh);
  export FZF_COMPLETION_TRIGGER='**'
  alias fz="fzf --preview 'bat --color=always {}'"
  alias fzvim="fz | xargs nvim"
fi
if which zoxide > /dev/null 2>&1; then
    eval "$(zoxide init zsh --cmd cd)"
fi
alias dnvim="nvim --headless -n -c 'lua require(\"dnvim\").cli()' -- " #dnvim-alias
