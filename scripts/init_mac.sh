#!/bin/bash
set -eo pipefail
brew update
brew install fzf ripgrep bat fd
brew cleanup
