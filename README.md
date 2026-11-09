# deck-skill

Portable [Agent Skills](https://agentskills.io) package for managing
[Nextcloud Deck](https://apps.nextcloud.com/apps/deck) kanban boards from any
skills-compatible agent CLI (Qoder, Claude Code, OpenCode, Qwen Code, ...).

One skill, `deck`, wraps the full Deck REST API
(`index.php/apps/deck/api/v1.1` plus the OCS routes for comments, config and
sessions):

```bash
deck.sh boards
deck.sh cards "Work" Doing
deck.sh add "Work" "To do" "Fix CI runner" - "2026-11-20T18:00:00+00:00"
deck.sh move "Work" 42 "Doing"
deck.sh done 42
deck.sh comment 42 "blocked on upstream"
deck.sh attach "Work" 42 ./spec.pdf
```

Tested against Nextcloud 35.0.2 with Deck 1.19.2 (API versions 1.0 and 1.1).
API v1.1 means card attachments of type `file` that live in the user's regular
Nextcloud files instead of Deck's private storage.

## Setup

```bash
bash install.sh          # copies skill to ~/.agents/skills, links ~/.claude/skills
$EDITOR ~/.config/deck-skill/config.sh   # DECK_URL / DECK_USER / DECK_TOKEN
```

Create an app password in Nextcloud: **Settings → Security → Devices/sessions →
Create new token**. The token lives only in the git-ignored local config with
mode 600 — never in the repo, a skill file, or a prompt.

## Requirements

Bash 4+, `curl`, `jq`, Nextcloud with Deck >= 1.3.0 (REST API v1.1; tested
against Deck 1.19.2).
