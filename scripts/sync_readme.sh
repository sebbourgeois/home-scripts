#!/usr/bin/env bash
set -euo pipefail

repo_root_dir="$(cd "$(dirname "$0")/.." && pwd)"

# Collect script entries from subfolders with README.md
mapfile -t entries < <(
  for d in "$repo_root_dir"/*/ ; do
    name="$(basename "$d")"
    [[ "$name" =~ ^\.(git|github)$ ]] && continue
    [[ ! -f "$d/README.md" ]] && continue

    title=$(awk 'BEGIN{FS="# *"} /^# /{print $2; exit}' "$d/README.md")
    if [[ -z "${title}" ]]; then
      title="$name"
    fi

    # First non-empty, non-heading line as description
    desc=$(awk 'BEGIN{s=0} {if($0 ~ /^#/){next} if(!s && $0 ~ /^\s*$/){next} if(!s){print; s=1; exit}}' "$d/README.md")
    if [[ -z "${desc}" ]]; then
      desc="No description yet."
    fi

    printf "%s/%s — %s\n" "$name" "$title" "$desc"
  done | sort -f)

# Build README content
{
  cat <<'HEADER'
# home-scripts

Collection of small, task-focused scripts for home LAN and desktop automation. Each script lives in its own folder with its own README and (optionally) a Makefile.

## Available Scripts
HEADER

  for line in "${entries[@]}"; do
    # Escape backticks in description
    printf -- "- %s\n" "$line"
  done

  cat <<'FOOTER'

---

To add a new script, create a folder at the repo root with its own README and optionally a Makefile, then run `make sync-readme` to refresh this list.
FOOTER
} > "$repo_root_dir/README.md"

echo "Updated README.md with $((${#entries[@]})) script(s)."

