#!/bin/bash

SERVICE=$1
if [[ $SERVICE == "" ]]; then
	echo "The following docker services are running ..."
	echo ""
	docker ps --format '{{.Names}}'
	echo "Choose a running service:"
	read SERVICE
fi

DOCKER_ID=$(docker ps --filter "name=$SERVICE" --format "{{.ID}}")
echo "Docker ID $DOCKER_ID"
NVIM_V=$(docker exec $DOCKER_ID which nvim || echo "")
LIN_PACKAGE_MANAGER=$(docker exec $DOCKER_ID which apk || echo "")
INTERPRETER=$(docker exec $DOCKER_ID ls /lib | grep "ld-musl-aarch64.so.1")
NPM_INSTALLED=$(docker exec $DOCKER_ID which npm || echo "")

set -e
USER=$(docker exec $DOCKER_ID whoami)
ARCH=$(docker exec $DOCKER_ID uname -m)
if [[ $INTERPRETER != "" ]]; then
	ARCH="alpine-$ARCH"
fi

echo ""
echo "Service Found:"
echo "$SERVICE -> $DOCKER_ID @ $USER "

f_install_neovim() {
	docker exec $DOCKER_ID mkdir -p "/$USER/.config"
	docker cp ~/.config/nvim/. "$DOCKER_ID:/$USER/.config/nvim"
	if [[ $RUN == "build" ]]; then
		f_build_neovim
	else
		docker cp ~/neovim/$ARCH "$DOCKER_ID:/$USER/neovim"
	fi
	docker exec $DOCKER_ID rm -f "/$USER/.config/nvim/lazy-lock.json"
	docker exec $DOCKER_ID rm -f /bin/nvim
	docker exec $DOCKER_ID ln -s "/$USER/neovim/build/bin/nvim" /bin/nvim
}

f_build_neovim() {
	docker exec $DOCKER_ID curl -L -o /tmp/neovim_stable.zip https://github.com/neovim/neovim/archive/refs/tags/stable.zip
	docker exec $DOCKER_ID apt-get install -y unzip cmake gettext
	docker exec $DOCKER_ID unzip -oq /tmp/neovim_stable.zip -d /tmp/
	docker exec $DOCKER_ID rm -rf /$USER/neovim
	docker exec $DOCKER_ID mv /tmp/neovim-stable /$USER/neovim
	docker exec -w /$USER/neovim $DOCKER_ID make CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=$HOME/neovim" && make install
	docker exec -w /$USER/neovim make install
}

if [[ $LIN_PACKAGE_MANAGER == "" ]]; then
	docker exec $DOCKER_ID apt-get update --fix-missing
	docker exec $DOCKER_ID apt-get install -y gcc git g++ wget
	if [[ $NPM_INSTALLED == "" ]]; then
		echo "Needs npm, installing ..."
		docker exec $DOCKER_ID apt-get install -y nodejs npm --no-install-recommends
	fi
else
	docker exec $DOCKER_ID apk add gcc git g++ wget nodejs npm
fi

if [[ $NVIM_V == "" ]]; then
	echo "installing"
	f_install_neovim
fi

docker exec -it $DOCKER_ID bash -c 'export VIMRUNTIME="/$(whoami)/neovim/runtime/" && bash'
