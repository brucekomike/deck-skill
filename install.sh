#!/usr/bin/env bash
# install.sh — install the deck skill for Agent Skills-compatible clients
#
# Installs the canonical skill to ~/.agents/skills/deck and creates a Claude
# Code compatibility link at ~/.claude/skills/deck. Seeds
# ~/.config/deck-skill/config.sh from the bundled example when absent. Define
# DECK_SITE_<NAME>_URL/USER/TOKEN profiles for multiple Nextcloud servers and
# select one with DECK_SITE; the plain DECK_URL/DECK_USER/DECK_TOKEN are the
# "default" site.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_SRC="${SCRIPT_DIR}/.agents/skills"
SKILLS_DST="${HOME}/.agents/skills"
CLAUDE_SKILLS_DST="${HOME}/.claude/skills"
CONFIG_DIR="${HOME}/.config/deck-skill"

echo "==> Installing skill to ${SKILLS_DST}"
mkdir -p "$SKILLS_DST" "$CLAUDE_SKILLS_DST" "$CONFIG_DIR"

for skill in "$SKILLS_SRC"/*; do
  name="$(basename "$skill")"
  rm -rf "${SKILLS_DST:?}/$name"
  cp -r "$skill" "$SKILLS_DST/"
  ln -sfn "$SKILLS_DST/$name" "$CLAUDE_SKILLS_DST/$name"
done

if [[ ! -f "$CONFIG_DIR/config.sh" ]]; then
  cp "${SCRIPT_DIR}/config.sh.example" "$CONFIG_DIR/config.sh"
  chmod 600 "$CONFIG_DIR/config.sh"
  echo "==> Seeded $CONFIG_DIR/config.sh — fill in DECK_URL/DECK_USER/DECK_TOKEN, or add DECK_SITE_<NAME>_* profiles"
else
  echo "==> Kept existing $CONFIG_DIR/config.sh — add DECK_SITE_<NAME>_URL/USER/TOKEN lines for more servers"
fi

echo "==> Test: bash ${SKILLS_DST}/deck/scripts/deck.sh sites   (list configured sites)"
echo "        then: bash ${SKILLS_DST}/deck/scripts/deck.sh boards"
