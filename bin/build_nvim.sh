#!/bin/bash
VERSION="0.9.4"
LIN_PACKAGE_MANAGER=$(which apk)
INTERPRETER=$(ls /lib | grep "ld-musl-aarch64.so.1")
set -e
USER=$(whoami)
ARH=$(uname -m)
if [[ $INTERPRETER != "" ]]; then
	ARCH="alpine-$ARCH"
fi

curl -L -o neovim_src.zip "https://github.com/neovim/neovim/archive/refs/tags/v$VERSION.zip"
