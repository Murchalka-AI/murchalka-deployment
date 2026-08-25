#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 || ! -s "$1" || "$1" != *.murchalka ]]; then
  echo "Usage: install-bundle.sh <signed-module.murchalka>" >&2
  exit 2
fi

inbox="$(cd "$(dirname "$0")/../runtime/modules/inbox" && pwd)"
source_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
target="$inbox/$(basename "$source_path")"
partial="$target.partial"
test ! -e "$target"
install -m 0600 "$source_path" "$partial"
mv "$partial" "$target"
echo "Staged $(basename "$target") for Runtime verification."

