#!/bin/sh
# CI's herdr (ci.yml, release.yml): a pinned release, checked by its SHA-256.
set -eu
version=0.9.5 sha256=fb77c2232a05a8035421382c894392f4174e4e38a18e48af3dd0290157c3a7e2
mkdir -p ~/.local/bin
curl -fsSL -o ~/.local/bin/herdr "https://github.com/herdrdev/herdr/releases/download/v$version/herdr-macos-aarch64"
echo "$sha256  $HOME/.local/bin/herdr" | shasum -a 256 -c
chmod +x ~/.local/bin/herdr
echo "$HOME/.local/bin" >>"$GITHUB_PATH"
# The app finds herdr through the login shell, like a user's rc file after install.
echo 'export PATH="$HOME/.local/bin:$PATH"' | tee -a ~/.zshrc >>~/.bash_profile
