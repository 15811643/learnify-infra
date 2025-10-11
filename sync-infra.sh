#!/usr/bin/env bash
set -euo pipefail
REPO=/srv/learnify-infra
cd "$REPO"
while read -r f; do
  [ -z "$f" ] && continue
  [ "${f:0:1}" = "#" ] && continue
  if [ -f "$f" ]; then
    mkdir -p ".$(dirname "$f")"
    sudo cp -a "$f" ".$f"
  fi
done < files.manifest
git add -A
git commit -m "Sync system -> repo ($(date -Iseconds))" || true
