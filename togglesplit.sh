#!/bin/sh

set -eu

# Hyprland togglesplit: flip the split holding the invoking pane.

herdr="${HERDR_BIN_PATH:-herdr}"

command -v "$herdr" >/dev/null 2>&1 || {
  echo "herdr-togglesplit: herdr not found" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "herdr-togglesplit: jq not found" >&2
  exit 1
}

if [ -z "${HERDR_PANE_ID:-}" ]; then
  echo "herdr-togglesplit: no HERDR_PANE_ID, invoke this action from a pane" >&2
  exit 1
fi

if ! layout=$("$herdr" pane layout --pane "$HERDR_PANE_ID"); then
  exit 1
fi

script_dir=$(dirname "$0")
if [ ! -f "$script_dir/togglesplit.jq" ]; then
  echo "herdr-togglesplit: togglesplit.jq not found next to $0" >&2
  exit 1
fi
if ! plan=$(printf '%s' "$layout" | jq -c --arg id "$HERDR_PANE_ID" -f "$script_dir/togglesplit.jq"); then
  echo "herdr-togglesplit: could not plan the toggle" >&2
  exit 1
fi

toast=$(printf '%s' "$plan" | jq -r '.toast // empty')
if [ -n "$toast" ]; then
  "$herdr" notification show "toggle split" \
    --body "$toast" \
    --sound none >/dev/null || true
  exit 0
fi

workspace=$(printf '%s' "$plan" | jq -r '.workspace // empty')
tab=$(printf '%s' "$plan" | jq -r '.tab // empty')
if [ -z "$workspace" ] || [ -z "$tab" ]; then
  echo "herdr-togglesplit: planner returned no tab" >&2
  exit 1
fi

focus_dir=$(printf '%s' "$plan" | jq -r '.focus.dir // empty')
focus_pid=$(printf '%s' "$plan" | jq -r '.focus.pid // empty')
moves=$(printf '%s' "$plan" | jq -r '.moves[]? | [.split, .mover, .target, (.ratio | tostring), (if .focus then "yes" else "no" end)] | @tsv')
movers=$(printf '%s' "$plan" | jq -r '.moves[]?.mover')
replayed=""
detached=""

# Scratch tabs vanish once empty. Anything detached but not replayed by
# exit is still sitting in one, so name it instead of losing it.
# shellcheck disable=SC2086,SC2154 # trap body runs at exit, not at arm time; herdr ids never contain whitespace
trap 'left=""
  for m in $detached; do
    case " $replayed " in *" $m "*) ;; *) left="$left $m";; esac
  done
  [ -z "$left" ] || "$herdr" notification show "toggle split" \
    --body "panes left in scratch tabs:$left" --sound none >/dev/null || true' \
  EXIT HUP INT TERM

if [ -n "$movers" ]; then
  # shellcheck disable=SC2086 # herdr ids never contain whitespace
  for mover in $movers; do
    "$herdr" pane move "$mover" --new-tab --workspace "$workspace" --no-focus >/dev/null
    detached="$detached $mover"
  done
fi

if [ -n "$moves" ]; then
  # Heredoc, not a pipe: a pipe would run this loop in a subshell and
  # hide $replayed from the trap above.
  TAB=$(printf '\t')
  while IFS="$TAB" read -r split mover target ratio focus; do
    if [ "$focus" = "yes" ]; then
      focus_flag="--focus"
    else
      focus_flag="--no-focus"
    fi
    "$herdr" pane move "$mover" \
      --tab "$tab" \
      --split "$split" \
      --target-pane "$target" \
      --ratio "$ratio" \
      "$focus_flag" >/dev/null
    replayed="$replayed $mover"
  done <<EOF
$moves
EOF
fi

trap - EXIT HUP INT TERM

# The replay can park focus on the wrong pane, so when the invoking pane
# traveled, hop to the neighbor it ends next to and back.
if [ -n "$focus_dir" ] && [ -n "$focus_pid" ]; then
  case "$focus_dir" in
    right) back=left;; left) back=right;; down) back=up;; up) back=down;; *) back="";;
  esac
  if [ -n "$back" ]; then
    if "$herdr" pane focus --direction "$focus_dir" --pane "$HERDR_PANE_ID" >/dev/null; then
      "$herdr" pane focus --direction "$back" --pane "$focus_pid" >/dev/null || true
    fi
  fi
fi
