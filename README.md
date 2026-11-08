# deck-skill

Portable [Agent Skills](https://agentskills.io) package for managing
[Nextcloud Deck](https://apps.nextcloud.com/apps/deck) kanban boards from any
skills-compatible agent CLI (Qoder, Claude Code, OpenCode, Qwen Code, ...).

One skill, `deck`, wraps the Deck REST API (`/index.php/apps/deck/api/v1.0`):

```bash
deck.sh boards
deck.sh cards "Work" Doing
deck.sh add "Work" "To do" "Fix CI runner"
deck.sh move "Work" 42 "Doing"
deck.sh done "Work" 42
deck.sh comment 42 "blocked on upstream"
```

## Setup

```bash
bash install.sh          # copies skill to ~/.agents/skills, links ~/.claude/skills
$EDITOR ~/.config/deck-skill/config.sh   # DECK_URL / DECK_USER / DECK_TOKEN
```

Create an app password in Nextcloud: **Settings → Security → Devices/sessions →
Create new token**. The token lives only in the git-ignored local config with
mode 600 — never in the repo, a skill file, or a prompt.

## Requirements

Bash 4+, `curl`, `jq`, Nextcloud with Deck (API v1.0; tested against Deck 6+).
