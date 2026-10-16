#!/usr/bin/env bash
set -euo pipefail

# Installs all shippable skills and global GEMINI.md in the repository as
# standalone copies into ~/.gemini/config (for Antigravity CLI, Antigravity IDE,
# and Antigravity 2.0) and ~/.gemini (for Gemini CLI).
# Copying instead of symlinking ensures global rules and skills keep working
# even if this repository is renamed, moved, or deleted.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DESTS=(
  "$HOME/.gemini/config/skills"
  "$HOME/.gemini/skills"
)

for DEST in "${DESTS[@]}"; do
  # If DEST itself is a symlink, remove the symlink first so mkdir creates a real directory.
  if [ -L "$DEST" ]; then
    rm -f "$DEST"
  fi

  mkdir -p "$DEST"

  # Clean up any broken symlinks left over from previous symlink installs or repo renames.
  find "$DEST" -maxdepth 1 -type l ! -exec test -e {} \; -delete

  find "$REPO/skills" -name SKILL.md \
    -not -path '*/node_modules/*' \
    -not -path '*/deprecated/*' \
    -not -path '*/in-progress/*' \
    -not -path '*/personal/*' \
    -print0 |
  while IFS= read -r -d '' skill_md; do
    src="$(dirname "$skill_md")"
    name="$(basename "$src")"
    target="$DEST/$name"

    if [ -e "$target" ] || [ -L "$target" ]; then
      rm -rf "$target"
    fi

    cp -R "$src" "$target"
    echo "copied $name -> $target"
  done
done

# Copy global Senior DevSecOps persona & safety guardrails (GEMINI.md).
# Copy to ~/.gemini/config/GEMINI.md as a standalone file (independent of repo path),
# and link ~/.gemini/GEMINI.md -> ~/.gemini/config/GEMINI.md internally within ~/.gemini
# so Antigravity deduplicates both global paths to a single rule injection.
PRIMARY_RULE="$HOME/.gemini/config/GEMINI.md"
SECONDARY_RULE="$HOME/.gemini/GEMINI.md"

mkdir -p "$(dirname "$PRIMARY_RULE")"
rm -f "$PRIMARY_RULE" "$SECONDARY_RULE"
cp "$REPO/GEMINI.md" "$PRIMARY_RULE"
ln -s "$PRIMARY_RULE" "$SECONDARY_RULE"
echo "copied GEMINI.md -> $PRIMARY_RULE (and deduplicated $SECONDARY_RULE)"
