#!/usr/bin/env bash
set -euo pipefail

# Removes globally installed skills and GEMINI.md role files from
# ~/.gemini/config (Antigravity CLI, Antigravity IDE, Antigravity 2.0)
# and ~/.gemini (Gemini CLI).

DESTS=(
  "${HOME}/.gemini/config/skills"
  "${HOME}/.gemini/skills"
)

for DEST in "${DESTS[@]}"; do
  if [ -L "${DEST}" ]; then
    rm -f "${DEST}"
    echo "removed symlink ${DEST}"
  elif [ -d "${DEST}" ]; then
    for entry in "${DEST}"/* "${DEST}"/.[!.]* "${DEST}"/..?*; do
      if [ -e "${entry}" ] || [ -L "${entry}" ]; then
        rm -rf "${entry}"
        echo "removed ${entry}"
      fi
    done
  fi
done

RULES=(
  "${HOME}/.gemini/GEMINI.md"
  "${HOME}/.gemini/config/GEMINI.md"
)

for RULE in "${RULES[@]}"; do
  if [ -e "${RULE}" ] || [ -L "${RULE}" ]; then
    rm -f "${RULE}"
    echo "removed ${RULE}"
  fi
done
