#!/usr/bin/env bash
# kill-boxes.sh — delete the fuzz boxes (stops Hetzner billing immediately).
# Corpus + crashes live in R2, so deleting loses only the box-local build cache.
#   kill-boxes.sh [arm|x86|both]   (default both)
set -euo pipefail
export HCLOUD_TOKEN="$(grep -E '^api_token=' "$HOME/.config/hetzner/credentials" | head -1 | cut -d= -f2- | tr -d ' \r')"
WHICH="${1:-both}"
del(){ # <name>
  if hcloud server describe "$1" >/dev/null 2>&1; then
    hcloud server delete "$1" >/dev/null && echo "deleted $1"
  else
    echo "$1 not present"
  fi
}
case "$WHICH" in
  both) del zen-fuzz-arm; del zen-fuzz-x86;;
  arm)  del zen-fuzz-arm;;
  x86)  del zen-fuzz-x86;;
  *) echo "usage: kill-boxes.sh [arm|x86|both]" >&2; exit 1;;
esac
