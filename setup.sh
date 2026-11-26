#!/usr/bin/env bash
# setup.sh — give this machine real GitHub write access
#
#   bash setup.sh                     diagnose, then guide you through the fix
#   bash setup.sh --status            print state and exit
#   bash setup.sh --browser           browser authorization (needs a real terminal)
#   bash setup.sh --token-file PATH   verify a token, then store it
#   bash setup.sh --clean             remove stored github.com credential
#
# Tokens are never printed. Only length and first characters.

set -uo pipefail

API="https://api.github.com"
DEFAULT_TOKEN_FILE="$HOME/.github-token"

# With no credential, GCM opens a GUI prompt and waits forever instead of failing.
export GIT_TERMINAL_PROMPT=0
export GCM_INTERACTIVE=never

say() { printf '%s\n' "$*"; }
rule() { printf '%s\n' "--------------------------------------------------------"; }
hl() { printf '\n%s\n' "$*"; }

mask() { printf 'token: %s... (%d chars)\n' "${1:0:7}" "${#1}"; }

# Show native-looking paths: C:\Users\... instead of /c/Users/... on Windows.
showpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; else printf '%s' "$1"; fi; }

have_tty() { [ -t 0 ] && [ -t 1 ]; }

check_token() { # $1=token; prints login on success, details on stderr, non-zero on failure
  local tk="$1" body login
  body="$(curl -sS --max-time 20 -H "Authorization: Bearer $tk" \
        -H "Accept: application/vnd.github+json" "$API/user" 2>/dev/null)"
  login="$(printf '%s' "$body" | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [ -z "$login" ]; then
    printf 'GitHub said: %s\n' "$(printf '%s' "$body" | head -c 200 | tr -d '\n')" >&2
    return 1
  fi
  printf '%s' "$login"
}

current_cred() {
  printf 'protocol=https\nhost=github.com\n\n' | timeout 15 git credential fill 2>/dev/null
}

status() {
  hl "== environment =="
  say "git        : $(git --version 2>/dev/null || echo 'not found')"
  say "gcm        : $(git credential-manager --version 2>/dev/null | head -1 || echo 'not found')"
  say "curl       : $(curl --version 2>/dev/null | head -1 || echo 'not found')"
  say "ssh keys   : $(ls "$HOME/.ssh"/*.pub 2>/dev/null | wc -l | tr -d ' ')"

  hl "== git identity =="
  say "user.name  : $(git config --global --get user.name || echo '<unset>')"
  say "user.email : $(git config --global --get user.email || echo '<unset>')"

  hl "== credential =="
  local got user pass real
  got="$(current_cred)"
  if printf '%s' "$got" | grep -q '^password='; then
    user="$(printf '%s\n' "$got" | sed -n 's/^username=//p')"
    pass="$(printf '%s\n' "$got" | sed -n 's/^password=//p')"
    say "stored     : yes (username=$user, $(mask "$pass"))"
    if real="$(check_token "$pass" 2>/dev/null)"; then
      say "valid      : yes, resolves to $real"
    else
      say "valid      : NO. This credential is broken. Run: bash setup.sh --clean"
    fi
  else
    say "stored     : none (pushes will fail)"
  fi
  say "token file : $([ -f "$DEFAULT_TOKEN_FILE" ] && echo "found at $(showpath "$DEFAULT_TOKEN_FILE")" || echo 'not present')"
}

clean() {
  printf 'protocol=https\nhost=github.com\n\n' | git credential reject
  local left
  left="$(current_cred | grep -c '^password=' || true)"
  say "Removed the github.com credential. Remaining entries: ${left:-0}"
}

token_file() {
  local f="${1:-$DEFAULT_TOKEN_FILE}" tk user
  if [ ! -f "$f" ]; then
    say "No such file: $f"
    say "Save the token there as a single line (no quotes, no spaces) and run this again."
    return 1
  fi
  tk="$(tr -d ' \t\r\n' < "$f")"
  [ -z "$tk" ] && { say "That file is empty: $f"; return 1; }
  say "Read $(mask "$tk")"
  if ! user="$(check_token "$tk")"; then
    say ""
    say "Rejected. Nothing was stored."
    say "Usual causes: truncated copy, expired, revoked, or not a ghp_/github_pat_ token."
    return 1
  fi
  say "Valid. Token belongs to $user"
  printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' "$user" "$tk" | git credential approve
  say "Stored."
  say "Next: bash verify.sh --repo $user/<a-repo-with-at-least-one-commit>"
}

browser() {
  if ! have_tty; then
    say "This needs a real terminal (no TTY here, so the browser prompt cannot open)."
    say ""
    say "Run it yourself, in your own terminal:"
    say "  git credential-manager github login --browser"
    return 1
  fi
  git credential-manager github login --browser
}

guide() {
  status
  hl "== next step =="
  local got
  got="$(current_cred)"
  if printf '%s' "$got" | grep -q '^password='; then
    local pass
    pass="$(printf '%s\n' "$got" | sed -n 's/^password=//p')"
    if check_token "$pass" >/dev/null 2>&1; then
      say "You already have a working credential. Verify it for real:"
      say "  bash verify.sh --repo <owner>/<repo>"
      return 0
    fi
    say "The stored credential is invalid. Clearing it first:"
    clean >/dev/null
  fi
  say "Pick one:"
  say ""
  say "  Browser (default, one click):"
  say "    bash setup.sh --browser"
  say ""
  say "  Token (headless, or phone-only):"
  say "    save it to $(showpath "$DEFAULT_TOKEN_FILE")"
  say "    bash setup.sh --token-file $(showpath "$DEFAULT_TOKEN_FILE")"
  say ""
  say "  Phone-only? Create a fine-grained token with Contents: Read and write,"
  say "  then move it to the machine and use the token path above."
}

case "${1:---guide}" in
  --status)      status ;;
  --guide|"")    guide ;;
  --browser)     browser ;;
  --token-file)  token_file "${2:-}" ;;
  --clean)       clean ;;
  -h|--help)     sed -n '2,12p' "$0" ;;
  *) say "Unknown option: $1"; say "Try: bash setup.sh --status"; exit 2 ;;
esac
