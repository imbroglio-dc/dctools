#!/usr/bin/env bash
# git-guard.sh — PreToolUse hook on Bash. Blocks direct pushes to main/master
# so changes go through a PR (and CI). Exit 2 = block.
set -euo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')"
[ -z "$cmd" ] && exit 0

case "$cmd" in
  *"git push"*)
    if printf '%s' "$cmd" | grep -qE '\b(main|master)\b'; then
      echo "GUARD: direct push to main/master blocked; open a PR." >&2
      exit 2
    fi
    cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    if printf '%s' "$cmd" | grep -qE 'git push([[:space:]]+(-u|--set-upstream))?[[:space:]]+origin[[:space:]]*$' \
       && { [ "$cur" = "main" ] || [ "$cur" = "master" ]; }; then
      echo "GUARD: current branch is '$cur'; that push would update main/master." >&2
      exit 2
    fi
    ;;
esac
exit 0
