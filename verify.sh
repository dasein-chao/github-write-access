#!/usr/bin/env bash
# verify.sh — prove write access with a real push, then clean up
#
#   bash verify.sh                        test against a repo you own
#   bash verify.sh --repo owner/repo      pick the repo to test on
#   bash verify.sh --repo owner/repo --keep   leave the branch behind
#
# Exit 0 means write access works. Exit 1 means it does not, with the reason.

set -uo pipefail

export GIT_TERMINAL_PROMPT=0
export GCM_INTERACTIVE=never

REPO="${WB_VERIFY_REPO:-}"
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1"; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
pass() { printf '\nPASS - %s\n' "$*"; }
fail() { printf '\nFAIL - %s\n' "$*"; exit 1; }

# Prints the GitHub login if this machine already has a working SSH key.
ssh_user() {
  local out
  out="$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
            -T git@github.com 2>&1)"
  printf '%s\n' "$out" | sed -n 's/^Hi \([^!]*\)!.*/\1/p'
}

if [ -z "$REPO" ]; then
  say "No repo given. Pass one you own, with at least one commit:"
  say "  bash verify.sh --repo your-name/your-repo"
  exit 2
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"
BRANCH="write-check-$(date +%s)"
WORK="$(mktemp -d 2>/dev/null || echo "/tmp/wbverify.$$")"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

say "repo   : $REPO"
say "branch : $BRANCH"

say ""
say "[0/5] checking credential"
TRANSPORT="https"
SSH_USER="$(ssh_user 2>/dev/null || true)"
if [ -n "$SSH_USER" ]; then
  TRANSPORT="ssh"
  say "      SSH key accepted by github.com as $SSH_USER"
else
  CRED="$(printf 'protocol=https\nhost=github.com\n\n' | timeout 15 git credential fill 2>/dev/null)"
  if ! printf '%s' "$CRED" | grep -q '^password='; then
    say "      No credential for github.com - neither an SSH key nor a stored token."
    say ""
    say "      Fix that first:"
    say "        bash ssh-setup.sh                  (recommended: no token to leak, never expires)"
    say "        bash setup.sh --browser            (or log in with a token)"
    fail "nothing to test"
  fi
  say "      stored token (username=$(printf '%s\n' "$CRED" | sed -n 's/^username=//p'))"
fi

if [ "$TRANSPORT" = "ssh" ]; then
  REMOTE="git@github.com:$REPO.git"
else
  REMOTE="https://github.com/$REPO.git"
fi
say "      transport : $TRANSPORT"

say "[1/5] cloning"
if ! git clone --quiet --depth 1 "$REMOTE" "$WORK/repo" 2>"$WORK/clone.err"; then
  sed -n '1,4p' "$WORK/clone.err"
  say ""
  say "      Empty repos cannot be tested - there is no branch to build on."
  say "      Private repo without access looks the same. Try another repo."
  fail "cannot clone $REPO"
fi
cd "$WORK/repo" || fail "cannot enter work dir"

say "[2/5] creating branch"
git checkout --quiet -b "$BRANCH" || fail "cannot create branch"

GIT_NAME="$(git config user.name || true)"
GIT_MAIL="$(git config user.email || true)"
[ -z "$GIT_NAME" ] && GIT_NAME="$OWNER"
[ -z "$GIT_MAIL" ] && GIT_MAIL="${OWNER}@users.noreply.github.com"
say "      commit as: $GIT_NAME <$GIT_MAIL>"

say "[3/5] committing"
printf 'write access check\nrepo=%s\ntime=%s\n' "$REPO" "$(date -u +%FT%TZ)" > .write-check.txt
git add .write-check.txt
if ! git -c user.name="$GIT_NAME" -c user.email="$GIT_MAIL" \
      commit --quiet -m "test: verify write access (temporary, removed right after)" 2>"$WORK/commit.err"; then
  sed -n '1,4p' "$WORK/commit.err"
  fail "local commit failed"
fi

say "[4/5] pushing (this is the actual test)"
if ! git push --quiet origin "$BRANCH" 2>"$WORK/push.err"; then
  say ""
  say "      GitHub refused the push:"
  sed -n '1,6p' "$WORK/push.err" | sed 's/^/      /'
  say ""
  case "$(cat "$WORK/push.err")" in
    *"Resource not accessible by integration"*)
      say "      A GitHub App token, read-only. Not fixable by reconnecting it."
      say "      Use a credential of your own: bash setup.sh" ;;
    *"Resource not accessible by personal access token"*)
      say "      The token lacks Contents: Read and write, or this repo is not in its list." ;;
    *"Authentication failed"*|*"Invalid username or token"*|*"could not read Username"*)
      say "      The stored credential is broken. Run: bash setup.sh --clean" ;;
    *"Permission denied (publickey)"*)
      say "      This machine's SSH key is not registered on GitHub, or not allowed here."
      say "      Add it: bash ssh-setup.sh" ;;
    *"denied to"*)
      say "      Credential is fine, but this account has no write access to $REPO." ;;
    *)
      say "      See TROUBLESHOOTING.md." ;;
  esac
  fail "no write access"
fi

say "[5/5] checking the remote, then cleaning up"
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  say "      branch confirmed on the remote"
else
  say "      push reported success but the branch is not there - check the web UI"
fi

if [ "$KEEP" -eq 1 ]; then
  say "      kept: https://github.com/$REPO/tree/$BRANCH"
else
  if git push --quiet origin --delete "$BRANCH" 2>"$WORK/del.err" \
     && ! git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    say "      test branch deleted"
  else
    say "      could not delete it: https://github.com/$REPO/branches"
  fi
fi

pass "$REPO is writable"
