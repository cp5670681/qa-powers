#!/usr/bin/env bash
# 开发用：把本仓库 skill 软链到本机各宿主的 skill 目录。
# 不是对外安装器。用户请用 Claude plugin 或 npx skills add。
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Claude / Codex 共用 ~/.agents；Pi 全局目录 ~/.pi/agent/skills
DESTS=("$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.pi/agent/skills")

names=()
srcs=()
while IFS= read -r -d '' skill_md; do
  src="$(dirname "$skill_md")"
  names+=("$(basename "$src")")
  srcs+=("$src")
done < <(find "$REPO/skills" -name SKILL.md -print0)

for DEST in "${DESTS[@]}"; do
  if [ -L "$DEST" ]; then
    resolved="$(readlink -f "$DEST")"
    case "$resolved" in
      "$REPO"|"$REPO"/*)
        echo "error: $DEST is a symlink into this repo ($resolved)." >&2
        echo "Remove it (rm \"$DEST\") and re-run." >&2
        exit 1
        ;;
    esac
  fi
  mkdir -p "$DEST"
  for i in "${!names[@]}"; do
    name="${names[$i]}"
    src="${srcs[$i]}"
    target="$DEST/$name"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      echo "error: $target exists and is not a symlink (refusing to overwrite; rm it or use a different dest)." >&2
      exit 1
    fi
    ln -sfn "$src" "$target"
    echo "linked $name -> $src ($DEST)"
  done
done
