#!/usr/bin/env bash
# deck.sh — Nextcloud Deck (kanban) client for agent use — Deck REST API v1.1
#
# Boards:
#   boards
#   board          <board>
#   create-board   <title> [color]
#   update-board   <board> [title|-] [color|-] [archive:0|1|-]
# Stacks:
#   stacks         <board> [archived]
#   stack          <board> <stack>
#   create-stack   <board> <title> [order]
#   update-stack   <board> <stack> [title|-] [order|-]
# Cards:
#   cards          <board> [stack]
#   show           <board> <card-id>
#   add            <board> <stack> <title> [description|-] [duedate|-]
#   update         <board> <card-id> [title|-] [description|-] [duedate|-|none]
#   move           <board> <card-id> <stack> [order]
#   done           <card-id> | undone <card-id>
#   assign-label   <board> <card-id> <label>
#   unassign-label <board> <card-id> <label>
#   assign-user    <board> <card-id> <user-id>
#   unassign-user  <board> <card-id> <user-id>
# Labels:
#   labels         <board>
#   label          <board> <label>
#   create-label   <board> <title> <color>
#   update-label   <board> <label> [title|-] [color|-]
# Attachments (v1.1: type "file", stored in the user's Nextcloud files):
#   attachments    <board> <card-id>
#   attach         <board> <card-id> <file>
#   download       <board> <card-id> <attachment-id> [out-file]
# Comments (OCS API):
#   comments       <card-id> [limit] [offset]
#   comment        <card-id> <text> [parent-comment-id]
#   edit-comment   <card-id> <comment-id> <text>
# Config & sessions (OCS API):
#   config
#   config-set     <key> <value>
#   session-open   <board>
#   session-sync   <board> <token>
#   session-close  <board> <token>
# Site profiles:
#   sites
#
# "-" keeps the current value. No delete commands on purpose.
#
# Config: the first file found among $DECK_CONFIG, ./config.sh, and
# ~/.config/deck-skill/config.sh. Each site needs DECK_URL (e.g.
# https://cloud.example.com), DECK_USER, DECK_TOKEN (app password), and an
# optional DECK_PROXY. Values exported in the real environment override the
# config file. DECK_SITE selects a named profile defined as
# DECK_SITE_<PROFILE>_URL/USER/TOKEN (optional _PROXY); "default" is the plain
# DECK_URL/DECK_USER/DECK_TOKEN. See "deck.sh sites" for what is configured.
set -euo pipefail

# Capture the real environment before sourcing, so exported values always win
# over the config file (same resolution order as mw-skills' lib.sh).
_DECK_ENV_URL="${DECK_URL:-}"
_DECK_ENV_USER="${DECK_USER:-}"
_DECK_ENV_TOKEN="${DECK_TOKEN:-}"
_DECK_ENV_SITE="${DECK_SITE:-}"
_DECK_ENV_PROXY="${DECK_PROXY:-}"
_DECK_CONFIG="${DECK_CONFIG:-}"
if [[ -z "$_DECK_CONFIG" ]]; then
  for _candidate in "${PWD}/config.sh" "${HOME}/.config/deck-skill/config.sh"; do
    if [[ -f "$_candidate" ]]; then
      _DECK_CONFIG="$_candidate"
      break
    fi
  done
fi
if [[ -n "$_DECK_CONFIG" && -f "$_DECK_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$_DECK_CONFIG"
fi

DECK_SITE="${_DECK_ENV_SITE:-${DECK_SITE:-default}}"
if [[ ! "$DECK_SITE" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "deck: invalid DECK_SITE: $DECK_SITE (letters, digits, underscores)" >&2
  exit 1
fi
_DECK_SITE_KEY="${DECK_SITE^^}"

# Snapshot the plain (default-site) settings before a profile can replace them,
# so `deck.sh sites` can report both.
_DECK_DEFAULT_URL="${_DECK_ENV_URL:-${DECK_URL:-}}"
_DECK_DEFAULT_USER="${_DECK_ENV_USER:-${DECK_USER:-}}"
_DECK_DEFAULT_TOKEN="${_DECK_ENV_TOKEN:-${DECK_TOKEN:-}}"

if [[ "$_DECK_SITE_KEY" != "DEFAULT" ]]; then
  _DECK_PROFILE_URL="$(eval "printf '%s' \"\${DECK_SITE_${_DECK_SITE_KEY}_URL:-}\"")"
  _DECK_PROFILE_USER="$(eval "printf '%s' \"\${DECK_SITE_${_DECK_SITE_KEY}_USER:-}\"")"
  _DECK_PROFILE_TOKEN="$(eval "printf '%s' \"\${DECK_SITE_${_DECK_SITE_KEY}_TOKEN:-}\"")"
  _DECK_PROFILE_PROXY="$(eval "printf '%s' \"\${DECK_SITE_${_DECK_SITE_KEY}_PROXY:-}\"")"
  if [[ -z "$_DECK_PROFILE_URL" && -z "$_DECK_ENV_URL" ]]; then
    echo "deck: unknown site profile: $DECK_SITE" >&2
    echo "deck: define DECK_SITE_${_DECK_SITE_KEY}_URL/USER/TOKEN, or run 'deck.sh sites'" >&2
    exit 1
  fi
  if [[ -n "$_DECK_PROFILE_URL" ]]; then
    DECK_URL="$_DECK_PROFILE_URL"
    DECK_USER="$_DECK_PROFILE_USER"
    DECK_TOKEN="$_DECK_PROFILE_TOKEN"
    if [[ -n "$_DECK_PROFILE_PROXY" ]]; then
      DECK_PROXY="$_DECK_PROFILE_PROXY"
    fi
  fi
fi

DECK_URL="${_DECK_ENV_URL:-${DECK_URL:-}}"
DECK_USER="${_DECK_ENV_USER:-${DECK_USER:-}}"
DECK_TOKEN="${_DECK_ENV_TOKEN:-${DECK_TOKEN:-}}"
DECK_PROXY="${_DECK_ENV_PROXY:-${DECK_PROXY:-}}"

# `sites` only reports what is configured, so it must work with a partial config.
if [[ "${1:-boards}" != "sites" ]]; then
  _missing=()
  [[ -n "$DECK_URL" ]]   || _missing+=(DECK_URL)
  [[ -n "$DECK_USER" ]]  || _missing+=(DECK_USER)
  [[ -n "$DECK_TOKEN" ]] || _missing+=(DECK_TOKEN)
  if [[ "${#_missing[@]}" -gt 0 ]]; then
    echo "deck: site '$DECK_SITE' is missing ${_missing[*]}" >&2
    echo "deck: searched \$DECK_CONFIG, ./config.sh, ~/.config/deck-skill/config.sh (found: ${_DECK_CONFIG:-none})" >&2
    echo "deck: copy config.sh.example to fill these in, or run 'deck.sh sites'" >&2
    exit 1
  fi
fi

BASE="${DECK_URL%/}/index.php/apps/deck/api/v1.1"
OCS="${DECK_URL%/}/ocs/v2.php/apps/deck/api/v1.1"
WEB="${DECK_URL%/}/index.php/apps/deck"
AUTH=(curl -sS --fail-with-body -u "$DECK_USER:$DECK_TOKEN"
      -H 'OCS-APIRequest: true' -H 'Accept: application/json')
[[ -n "${DECK_PROXY:-}" ]] && AUTH+=(--proxy "$DECK_PROXY")
CURL=("${AUTH[@]}" -H 'Content-Type: application/json')

api() { # api <METHOD> <path> [json-data]
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    "${CURL[@]}" -X "$method" "$BASE/$path" --data "$data"
  else
    "${CURL[@]}" -X "$method" "$BASE/$path"
  fi
}

ocs() { # ocs <METHOD> <path> [json-data]
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    "${CURL[@]}" -X "$method" "$OCS/$path" --data "$data"
  else
    "${CURL[@]}" -X "$method" "$OCS/$path"
  fi
}

# unwrap {data: ...} envelopes where present
env() { jq '(.data? // .)'; }

# List the default site plus every DECK_SITE_<NAME>_* profile found in the
# config. Reports whether a token is set; never prints one.
list-sites() {
  local names=("default") key nm url user tok set_or_missing selected
  while read -r key; do
    nm="${key#DECK_SITE_}"
    nm="${nm%_URL}"
    names+=("${nm,,}")
  done < <(compgen -v 'DECK_SITE_' | grep -E '_URL$' | sort -u)

  echo "deck: config ${_DECK_CONFIG:-none found}; selected site: $DECK_SITE" >&2
  printf '%-10s  %-42s  %-14s  %-8s  %s\n' SITE URL USER TOKEN SELECTED
  for nm in "${names[@]}"; do
    if [[ "$nm" == "default" ]]; then
      url="$_DECK_DEFAULT_URL"
      user="$_DECK_DEFAULT_USER"
      tok="$_DECK_DEFAULT_TOKEN"
    else
      key="${nm^^}"
      url="$(eval "printf '%s' \"\${DECK_SITE_${key}_URL:-}\"")"
      user="$(eval "printf '%s' \"\${DECK_SITE_${key}_USER:-}\"")"
      tok="$(eval "printf '%s' \"\${DECK_SITE_${key}_TOKEN:-}\"")"
    fi
    selected=""
    if [[ "$nm" == "$DECK_SITE" ]]; then
      selected="yes"
    fi
    if [[ -n "$tok" ]]; then
      set_or_missing="set"
    else
      set_or_missing="missing"
    fi
    printf '%-10s  %-42s  %-14s  %-8s  %s\n' "$nm" "${url:--}" "${user:--}" \
      "$set_or_missing" "$selected"
  done
}

stacks_json() { api GET "boards/$1/stacks"; }

resolve_board() { # name-or-id -> numeric id
  if [[ "$1" =~ ^[0-9]+$ ]]; then echo "$1"; return; fi
  local id
  id=$(api GET boards | env | jq -r --arg n "$(echo "$1" | tr 'A-Z' 'a-z')" \
        '.[] | select((.title | ascii_downcase) == $n) | .id' | sed -n 1p)
  [[ -n "$id" ]] || { echo "deck: no board named '$1'" >&2; exit 1; }
  echo "$id"
}

resolve_stack() { # board-id stack-name -> numeric stack id
  local id
  id=$(stacks_json "$1" | env | jq -r --arg n "$(echo "$2" | tr 'A-Z' 'a-z')" \
        '.[] | select((.title | ascii_downcase) == $n) | .id' | sed -n 1p)
  [[ -n "$id" ]] || { echo "deck: no stack '$2' in board $1" >&2; exit 1; }
  echo "$id"
}

resolve_label() { # board-id label-name-or-id -> numeric label id
  if [[ "$2" =~ ^[0-9]+$ ]]; then echo "$2"; return; fi
  local id
  id=$(api GET "boards/$1" | env | jq -r --arg n "$(echo "$2" | tr 'A-Z' 'a-z')" \
        '.labels[]? | select((.title | ascii_downcase) == $n) | .id' | sed -n 1p)
  [[ -n "$id" ]] || { echo "deck: no label '$2' in board $1" >&2; exit 1; }
  echo "$id"
}

card_stack_of() { # board-id card-id -> numeric stack id
  local id
  id=$(stacks_json "$1" | env | jq -r --argjson c "$2" \
        '.[] | select(.cards[]?.id == $c) | .id' | sed -n 1p)
  [[ -n "$id" ]] || { echo "deck: no card $2 in board $1" >&2; exit 1; }
  echo "$id"
}

cmd="${1:-boards}"; shift || true
case "$cmd" in
  boards)
    api GET boards | env | jq -r '.[] | "\(.id)\t\(.title)"'
    ;;
  board)
    b=$(resolve_board "$1")
    api GET "boards/$b" | env | jq '{id, title, color, archived, owner: .owner.uid, labels, acl, permissions}'
    ;;
  create-board)
    t="$1"; color="${2:-ff0000}"
    api POST boards "$(jq -n --arg t "$t" --arg c "$color" '{title: $t, color: $c}')" \
      | env | jq '{id, title, color}'
    ;;
  update-board)
    b=$(resolve_board "$1"); t="${2:-}"; color="${3:-}"; arch="${4:-}"
    cur=$(api GET "boards/$b" | env)
    payload=$(jq -n --argjson cur "$cur" --arg t "$t" --arg c "$color" --arg a "$arch" '{
      title: (if $t == "" or $t == "-" then $cur.title else $t end),
      color: (if $c == "" or $c == "-" then $cur.color else $c end),
      archived: (if $a == "" or $a == "-" then $cur.archived else ($a == "1" or $a == "true") end)}')
    api PUT "boards/$b" "$payload" | env | jq '{id, title, color, archived}'
    ;;

  stacks)
    b=$(resolve_board "$1"); variant="${2:-}"
    if [[ "$variant" == "archived" ]]; then
      api GET "boards/$b/stacks/archived" | env \
        | jq -r '.[] | "\(.id)\t\(.title)\t(\(.cards | length) cards)"'
    else
      stacks_json "$b" | env | jq -r '.[] | "\(.id)\t\(.title)\t(\(.cards | length) cards)"'
    fi
    ;;
  stack)
    b=$(resolve_board "$1"); s=$(resolve_stack "$b" "$2")
    api GET "boards/$b/stacks/$s" | env \
      | jq '{id, title, order, cards: [.cards[]? | {id, title, done, duedate}]}'
    ;;
  create-stack)
    b=$(resolve_board "$1"); t="$2"; order="${3:-999}"
    api POST "boards/$b/stacks" "$(jq -n --arg t "$t" --argjson o "$order" '{title: $t, order: $o}')" \
      | env | jq '{id, title, order}'
    ;;
  update-stack)
    b=$(resolve_board "$1"); s=$(resolve_stack "$b" "$2"); t="${3:-}"; order="${4:-}"
    cur=$(api GET "boards/$b/stacks/$s" | env)
    payload=$(jq -n --argjson cur "$cur" --arg t "$t" --arg o "$order" '{
      title: (if $t == "" or $t == "-" then $cur.title else $t end),
      order: (if $o == "" or $o == "-" then $cur.order else ($o | tonumber) end)}')
    api PUT "boards/$b/stacks/$s" "$payload" | env | jq '{id, title, order}'
    ;;

  cards)
    b=$(resolve_board "$1"); filter="${2:-}"
    stacks_json "$b" | env | jq -r --arg f "$(echo "$filter" | tr 'A-Z' 'a-z')" '
      .[]
      | select($f == "" or (.title | ascii_downcase) == $f)
      | .title as $s
      | .cards[]?
      | "\(.id)\t[\($s)]\t\((.done // "") | if . != "" and . != null then "DONE" else "open" end)\t\((.duedate // "-") | .[0:10])\t\(.title)"
    '
    ;;
  show)
    b=$(resolve_board "$1"); c="$2"; s=$(card_stack_of "$b" "$c")
    api GET "boards/$b/stacks/$s/cards/$c" | env
    ;;
  add)
    b=$(resolve_board "$1"); s=$(resolve_stack "$b" "$2"); t="$3"
    d="${4:-}"; dd="${5:-}"
    payload=$(jq -n --arg t "$t" --arg d "$d" --arg dd "$dd" '{
      title: $t, type: "plain", order: 999,
      description: (if $d == "" or $d == "-" then null else $d end),
      duedate: (if $dd == "" or $dd == "-" then null else $dd end)}')
    api POST "boards/$b/stacks/$s/cards" "$payload" | env | jq '{id, title, duedate}'
    ;;
  update)
    b=$(resolve_board "$1"); c="$2"; s=$(card_stack_of "$b" "$c")
    t="${3:-}"; d="${4:-}"; dd="${5:-}"
    cur=$(api GET "boards/$b/stacks/$s/cards/$c" | env)
    # REST-scoped card PUT is rejected (400) by Deck 1.19+; the UI updates via
    # the unscoped OCS route with the full card object plus boardId.
    payload=$(jq -n --argjson cur "$cur" --argjson b "$b" --arg t "$t" --arg d "$d" --arg dd "$dd" '
      $cur + {boardId: $b}
      | .description = (.description // "")
      | .title = (if $t == "" or $t == "-" then .title else $t end)
      | .description = (if $d == "" or $d == "-" then .description else $d end)
      | .duedate = (if $dd == "" or $dd == "-" then .duedate
                    elif $dd == "none" then null else $dd end)')
    ocs PUT "cards/$c" "$payload" | jq -c '.ocs.data | {id, title, description, duedate}'
    ;;
  move)
    b=$(resolve_board "$1"); c="$2"
    src=$(card_stack_of "$b" "$c"); dst=$(resolve_stack "$b" "$3"); order="${4:-999}"
    if [[ "$src" == "$dst" ]]; then
      echo "card $c already in stack $dst"
    else
      api PUT "boards/$b/stacks/$src/cards/$c/reorder" \
        "$(jq -n --argjson s "$dst" --argjson o "$order" '{stackId: $s, order: $o}')" | env >/dev/null
      echo "moved card $c -> stack $dst"
    fi
    ;;
  done|undone)
    c="$1"
    # done/undone is only exposed on the web route; REST card PUT rejects it
    "${CURL[@]}" -X PUT "$WEB/cards/$c/$cmd" >/dev/null
    echo "card $c $cmd"
    ;;
  assign-label|unassign-label)
    b=$(resolve_board "$1"); c="$2"; s=$(card_stack_of "$b" "$c")
    l=$(resolve_label "$b" "$3")
    ep=assignLabel; [[ "$cmd" == "unassign-label" ]] && ep=removeLabel
    api PUT "boards/$b/stacks/$s/cards/$c/$ep" \
      "$(jq -n --argjson l "$l" '{labelId: $l}')" >/dev/null
    # response reflects pre-change state; re-read the card for the truth
    api GET "boards/$b/stacks/$s/cards/$c" | env \
      | jq -c '{id, title, labels: [.labels[]? | .title]}'
    ;;
  assign-user|unassign-user)
    b=$(resolve_board "$1"); c="$2"; s=$(card_stack_of "$b" "$c"); u="$3"
    ep=assignUser; [[ "$cmd" == "unassign-user" ]] && ep=unassignUser
    api PUT "boards/$b/stacks/$s/cards/$c/$ep" \
      "$(jq -n --arg u "$u" '{userId: $u}')" >/dev/null
    api GET "boards/$b/stacks/$s/cards/$c" | env \
      | jq -c '{id, title, assignedUsers: [.assignedUsers[]? | .participant.uid]}'
    ;;

  labels)
    b=$(resolve_board "$1")
    api GET "boards/$b" | env | jq -r '.labels[]? | "\(.id)\t\(.title)\t\(.color)"'
    ;;
  label)
    b=$(resolve_board "$1"); l=$(resolve_label "$b" "$2")
    api GET "boards/$b/labels/$l" | env
    ;;
  create-label)
    b=$(resolve_board "$1"); t="$2"; color="${3:-31CC7C}"
    api POST "boards/$b/labels" "$(jq -n --arg t "$t" --arg c "$color" '{title: $t, color: $c}')" \
      | env | jq '{id, title, color}'
    ;;
  update-label)
    b=$(resolve_board "$1"); l=$(resolve_label "$b" "$2"); t="${3:-}"; color="${4:-}"
    cur=$(api GET "boards/$b/labels/$l" | env)
    payload=$(jq -n --argjson cur "$cur" --arg t "$t" --arg c "$color" '{
      title: (if $t == "" or $t == "-" then $cur.title else $t end),
      color: (if $c == "" or $c == "-" then $cur.color else $c end)}')
    api PUT "boards/$b/labels/$l" "$payload" | env | jq '{id, title, color}'
    ;;

  attachments)
    b=$(resolve_board "$1"); c="$2"; s=$(card_stack_of "$b" "$c")
    api GET "boards/$b/stacks/$s/cards/$c/attachments" | env \
      | jq -r 'if type == "array" then .[] | "\(.id)\t\(.type)\t\(.extendedData.info.basename // .data)\t\(.extendedData.filesize // "?")" else . end'
    ;;
  attach)
    b=$(resolve_board "$1"); c="$2"; s=$(card_stack_of "$b" "$c"); f="$3"
    [[ -f "$f" ]] || { echo "deck: file not found: $f" >&2; exit 1; }
    # v1.1 uploads use multipart form data with type "file" (stored in Nextcloud files)
    "${AUTH[@]}" -X POST "$BASE/boards/$b/stacks/$s/cards/$c/attachments" \
      -F "type=file" -F "file=@${f}" \
      | jq -c '{id, type, data, path: .extendedData.path}'
    ;;
  download)
    b=$(resolve_board "$1"); c="$2"; s=$(card_stack_of "$b" "$c"); a="$3"; out="${4:-}"
    att=$(api GET "boards/$b/stacks/$s/cards/$c/attachments" | env \
          | jq --argjson a "$a" '.[] | select(.id == $a)')
    [[ -n "$att" ]] || { echo "deck: no attachment $a on card $c" >&2; exit 1; }
    atype=$(jq -r '.type' <<<"$att")
    apath=$(jq -r '.extendedData.path // empty' <<<"$att")
    if [[ "$atype" == "file" && -n "$apath" ]]; then
      # v1.1 file attachments live in the user's Nextcloud files
      url="${DECK_URL%/}/remote.php/dav/files/$DECK_USER$apath"
    else
      echo "deck: attachment $a is type '$atype'; only 'file' attachments are downloadable" >&2; exit 1
    fi
    if [[ -n "$out" ]]; then
      "${AUTH[@]}" -o "$out" "$url"; echo "saved attachment $a -> $out"
    else
      "${AUTH[@]}" "$url"
    fi
    ;;

  comments)
    c="$1"; limit="${2:-20}"; offset="${3:-0}"
    ocs GET "cards/$c/comments?limit=$limit&offset=$offset" \
      | jq -r '.ocs.data[]? | "\(.id)\t\(.creationDateTime)\t\(.actorId): \(.message)"'
    ;;
  comment)
    c="$1"; m="$2"; parent="${3:-}"
    payload=$(jq -n --arg m "$m" --arg p "$parent" '{message: $m}
      + (if $p == "" or $p == "-" then {parentId: null} else {parentId: ($p | tonumber)} end)')
    ocs POST "cards/$c/comments" "$payload" \
      | jq -c '.ocs.data | {id, message, mentions}'
    ;;
  edit-comment)
    c="$1"; cm="$2"; m="$3"
    ocs PUT "cards/$c/comments/$cm" "$(jq -n --arg m "$m" '{message: $m}')" \
      | jq -c '.ocs.data | {id, message}'
    ;;

  sites)
    list-sites
    ;;

  config)
    ocs GET config | jq '.ocs.data'
    ;;
  config-set)
    k="$1"; v="$2"
    ocs POST "config/$k" "$(jq -n --argjson v "$v" '{value: $v}')" | jq '.ocs.data'
    ;;

  session-open)
    b=$(resolve_board "$1")
    ocs PUT session/create "$(jq -n --argjson b "$b" '{boardId: $b}')" | jq -r '.ocs.data.token'
    ;;
  session-sync|session-close)
    b=$(resolve_board "$1"); tok="$2"
    ep=sync; [[ "$cmd" == "session-close" ]] && ep=close
    ocs POST "session/$ep" "$(jq -n --argjson b "$b" --arg t "$tok" '{boardId: $b, token: $t}')" >/dev/null
    echo "session $ep ok"
    ;;

  *)
    cat >&2 <<'EOF'
usage: deck.sh <command> [args...]   (run with no args and see script header for the full list)
  boards | board <b> | create-board <title> [color] | update-board <b> [title] [color] [0|1]
  stacks <b> [archived] | stack <b> <s> | create-stack <b> <s> [order] | update-stack <b> <s> [title] [order]
  cards <b> [stack] | show <b> <c> | add <b> <s> <title> [desc] [duedate] | update <b> <c> [title] [desc] [duedate|none]
  move <b> <c> <s> [order] | done <c> | undone <c>
  assign-label <b> <c> <l> | unassign-label <b> <c> <l> | assign-user <b> <c> <u> | unassign-user <b> <c> <u>
  labels <b> | label <b> <l> | create-label <b> <title> <color> | update-label <b> <l> [title] [color]
  attachments <b> <c> | attach <b> <c> <file> | download <b> <c> <a> [out]
  comments <c> [limit] [offset] | comment <c> <text> [parent] | edit-comment <c> <cm> <text>
  config | config-set <key> <value>
  session-open <b> | session-sync <b> <token> | session-close <b> <token>
  sites                       # list configured site profiles (no tokens shown)
Target a configured server other than the default with DECK_SITE=<profile>;
one-off targets use DECK_URL/DECK_USER/DECK_TOKEN from the environment.
EOF
    exit 2
    ;;
esac
