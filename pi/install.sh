#!/usr/bin/env bash
set -euo pipefail

# Version extension code, not Pi credentials, sessions, or personal settings.
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/extensions"
agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
mkdir -p "$agent_dir"
agent_dir="$(cd "$agent_dir" && pwd -P)"
target="$agent_dir/extensions"
if [[ -L "$target" && "$(readlink "$target")" == "$source_dir" ]]; then
  printf 'Already installed: %s -> %s\n' "$target" "$source_dir"
  exit 0
fi
if [[ -L "$target" && "${1:-}" != "--relink" ]]; then
  printf 'Already linked elsewhere: %s\nUse --relink to explicitly move it to this checkout.\n' "$target" >&2
  exit 1
fi
if [[ -e "$target" && ! -d "$target" ]]; then
  printf 'Expected a directory: %s\n' "$target" >&2
  exit 1
fi

# Preflight before moving anything. On relink, review is our versioned extension.
if [[ -d "$target" ]]; then
  for entry in "$target"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="$(basename "$entry")"
    [[ -L "$target" && "$name" == "review" ]] && continue
    if [[ -e "$source_dir/$name" || -L "$source_dir/$name" ]]; then
      if [[ "$entry" -ef "$source_dir/$name" ]]; then continue; fi
      printf 'Extension name collision; nothing moved: %s\n' "$name" >&2
      exit 1
    fi
  done
fi

legacy=""
backup=""
if [[ -L "$target" ]]; then
  legacy="$(cd "$target" && pwd -P)"
elif [[ -d "$target" ]]; then
  backup="$(mktemp -d "$agent_dir/extensions-backup.XXXXXX")"
  rmdir "$backup"
  mv "$target" "$backup"
  legacy="$backup"
  printf 'Preserved existing extensions at: %s\n' "$backup"
fi
# Restore the original directory if migration fails before the final symlink.
trap 'if [[ -n "$backup" && ! -e "$target" && ! -L "$target" ]]; then mv "$backup" "$target"; fi' EXIT
if [[ -n "$legacy" ]]; then
  for entry in "$legacy"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="$(basename "$entry")"
    [[ -z "$backup" && "$name" == "review" ]] && continue
    [[ -e "$source_dir/$name" || -L "$source_dir/$name" ]] && continue
    # Reuse an absolute link's destination so removal of an old worktree is safe.
    link="$entry"
    if [[ -L "$entry" ]]; then
      destination="$(readlink "$entry")"
      [[ "$destination" == /* ]] && link="$destination"
    fi
    ln -s "$link" "$source_dir/$name"
  done
fi
if [[ -L "$target" ]]; then unlink "$target"; fi
ln -s "$source_dir" "$target"
trap - EXIT
printf 'Installed: %s -> %s\nRun /reload in Pi, or start a new session.\n' "$target" "$source_dir"
