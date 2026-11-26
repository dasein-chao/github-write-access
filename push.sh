#!/usr/bin/env bash
# push.sh — commit and push in one step
#
#   bash push.sh                      current directory, generated message
#   bash push.sh -m "note to self"    your message
#   bash push.sh -m "..." ~/some-repo another repo
#
# Does: identity fallback -> add -A -> commit -> rebase if remote moved -> push.
# Never force-pushes, never deletes branches, never rewrites history.

set -uo pipefail

export GIT_TERMINAL_PROMPT=0
export GCM_INTERACTIVE=never

MSG=""
DIR="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--message) MSG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) DIR="$1"; shift ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'FAIL - %s\n' "$*"; exit 1; }

cd "$DIR" 2>/dev/null || die "no such directory: $DIR"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo: $DIR"

BRANCH="$(git branch --show-current)"
[ -z "$BRANCH" ] && die "detached HEAD - check out a branch first"

if [ -z "$(git status --porcelain)" ]; then
  say "Nothing to commit."
  if git rev-parse "@{u}" >/dev/null 2>&1; then
    AHEAD="$(git rev-list --count '@{u}..HEAD')"
    [ "$AHEAD" -gt 0 ] || exit 0
    say "Local is $AHEAD commit(s) ahead. Pushing."
  else
    exit 0
  fi
else
  [ -z "$MSG" ] && MSG="update: $(date '+%Y-%m-%d %H:%M')"
  say "Committing: $MSG"
  git add -A || die "git add failed"

  if ! git config user.email >/dev/null 2>&1; then
    OWNER="$(git remote get-url origin 2>/dev/null | sed -n 's#.*github\.com[:/]\([^/]*\)/.*#\1#p')"
    [ -z "$OWNER" ] && OWNER="$(whoami)"
    git config user.name "$OWNER"
    git config user.email "${OWNER}@users.noreply.github.com"
    say "Set identity for this repo only: $OWNER"
  fi
  git commit --quiet -m "$MSG" || die "commit failed"
fi

if git rev-parse "@{u}" >/dev/null 2>&1; then
  git fetch --quiet origin || true
  BEHIND="$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)"
  if [ "${BEHIND:-0}" -gt 0 ]; then
    say "Remote is $BEHIND commit(s) ahead. Rebasing."
    git pull --rebase --quiet || die "rebase hit a conflict - resolve it, then run again"
  fi
fi

say "Pushing origin/$BRANCH"
if git push --quiet origin "$BRANCH" 2>/tmp/wbpush.err; then
  URL="$(git remote get-url origin | sed -n 's#.*github\.com[:/]\(.*\)\.git#https://github.com/\1#p')"
  say "Pushed: $URL/commits/$BRANCH"
else
  sed -n '1,6p' /tmp/wbpush.err
  say ""
  say "Push rejected. If it looks like permissions, run: bash setup.sh --status"
  say "Details: TROUBLESHOOTING.md"
  exit 1
fi
