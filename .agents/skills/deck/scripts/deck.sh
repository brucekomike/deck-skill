#!/usr/bin/env bash
# deck.sh — Nextcloud Deck (kanban) client for agent use
#
# Commands:
#   boards
#   stacks   <board>
#   cards    <board> [stack]
#   show     <board> <card-id>
#   add      <board> <stack> <title> [description]
#   move     <board> <card-id> <stack>
#   done     <board> <card-id> | undone <board> <card-id>
#   comment  <card-id> <text>
#
# Config: ~/.config/deck-skill/config.sh (override with DECK_CONFIG)
#   DECK_URL (e.g. https://cloud.example.com), DECK_USER, DECK_TOKEN (app
#   password), optional DECK_PROXY.
set -euo pipefail

CONFIG="${DECK_CONFIG:-$HOME/.config/deck-skill/config.sh}"
[[ -f "$CONFIG" ]] || { echo "deck: config not found at $CONFIG (copy config.sh.example)" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG"

: "${DECK_URL:?DECK_URL missing in $CONFIG}"
: "${DECK_USER:?DECK_USER missing in $CONFIG}"
: "${DECK_TOKEN:?DECK_TOKEN missing in $CONFIG}"
BASE="${DECK_URL%/}/index.php/apps/deck/api/v1.0"
CURL=(curl -sS --fail-with-body -u "$DECK_USER:$DECK_TOKEN"
      -H 'OCS-APIRequest: true' -H 'Accept: application/json'
      -H 'Content-Type: application/json')
[[ -n "${DECK_PROXY:-}" ]] && CURL+=(--proxy "$DECK_PROXY")

api() { # api <METHOD> <path> [json-data]
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    "${CURL[@]}" -X "$method" "$BASE/$path" --data "$data"
  else
    "${CURL[@]}" -X "$method" "$BASE/$path"
  fi
}

board_json() { api GET "boards/$1"; }

resolve_board() { # name-or-id -> numeric id
  if [[ "$1" =~ ^[0-9]+$ ]]; then echo "$1"; return; fi
  local id
  id=$(api GET boards | jq -r --arg n "$(echo "$1" | tr 'A-Z' 'a-z')" \
        '.data[] | select((.title | ascii_downcase) == $n) | .id' | sed -n 1p)
  [[ -n "$id" ]] || { echo "deck: no board named '$1'" >&2; exit 1; }
  echo "$id"
}

resolve_stack() { # board-id stack-name -> numeric stack id
  local id
  id=$(board_json "$1" | jq -r --arg n "$(echo "$2" | tr 'A-Z' 'a-z')" \
        '.data.stacks[] | select((.title | ascii_downcase) == $n) | .id' | sed -n 1p)
  [[ -n "$id" ]] || { echo "deck: no stack '$2' in board $1" >&2; exit 1; }
  echo "$id"
}

card_stack_of() { # board-id card-id -> numeric stack id
  local id
  id=$(board_json "$1" | jq -r --argjson c "$2" \
        '.data.stacks[] | select(.cards[]?.id == $c) | .id' | sed -n 1p)
  [[ -n "$id" ]] || { echo "deck: no card $2 in board $1" >&2; exit 1; }
  echo "$id"
}

cmd="${1:-boards}"; shift || true
case "$cmd" in
  boards)
    api GET boards | jq -r '.data[] | "\(.id)\t\(.title)"'
    ;;
  stacks)
    b=$(resolve_board "$1")
    board_json "$b" | jq -r '.data.stacks[] | "\(.id)\t\(.title)\t(\(.cards | length) cards)"'
    ;;
  cards)
    b=$(resolve_board "$1"); filter="${2:-}"
    board_json "$b" | jq -r --arg f "$(echo "$filter" | tr 'A-Z' 'a-z')" '
      .data.stacks[]
      | select($f == "" or (.title | ascii_downcase) == $f)
      | .title as $s
      | .cards[]?
      | "\(.id)\t[\($s)]\t\((.done // 0) | if . == 1 or . == true then "DONE" else "open" end)\t\((.duedate // "-") | .[0:10])\t\(.title)"
    '
    ;;
  show)
    b=$(resolve_board "$1"); c="$2"; s=$(card_stack_of "$b" "$c")
    api GET "boards/$b/stacks/$s/cards/$c" | jq '.data | {id, title, stackId, done, duedate, description, labels, attachedByCount}'
    ;;
  add)
    b=$(resolve_board "$1"); s=$(resolve_stack "$b" "$2"); t="$3"; d="${4:-}"
    payload=$(jq -n --arg t "$t" --arg d "$d" '{title: $t, description: $d}')
    api POST "boards/$b/stacks/$s/cards" "$payload" | jq '{id: .data.id, title: .data.title}'
    ;;
  move)
    b=$(resolve_board "$1"); c="$2"
    src=$(card_stack_of "$b" "$c"); dst=$(resolve_stack "$b" "$3")
    if [[ "$src" == "$dst" ]]; then
      echo "card $c already in stack $dst"
    else
      api PUT "boards/$b/stacks/$src/cards/$c/reorder" \
        "$(jq -n --argjson s "$dst" '{stackId: $s, type: "manual", order: 999}')" >/dev/null
      echo "moved card $c -> stack $dst"
    fi
    ;;
  done|undone)
    b=$(resolve_board "$1"); c="$2"; s=$(card_stack_of "$b" "$c")
    [[ "$cmd" == done ]] && v=1 || v=0
    api PUT "boards/$b/stacks/$s/cards/$c" "$(jq -n --argjson d "$v" '{done: $d}')" >/dev/null
    echo "card $c done=$v"
    ;;
  comment)
    c="$1"; m="$2"
    api POST "cards/$c/comments" "$(jq -n --arg m "$m" '{message: $m}')" >/dev/null
    echo "commented on card $c"
    ;;
  *)
    echo "usage: deck.sh boards | stacks <board> | cards <board> [stack] | show <board> <id> | add <board> <stack> <title> [desc] | move <board> <id> <stack> | done|undone <board> <id> | comment <id> <text>" >&2
    exit 2
    ;;
esac
