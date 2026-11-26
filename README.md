# GitHub Write Access

**Your AI assistant can read your repos but every write fails with `403`. This fixes it in a minute — one script, no new app, no sign-up.**

If you have ever pasted code into a chat and got this back:

```
403 Resource not accessible by integration
```

…you already know the problem. This repo is the fix, plus the eleven traps we hit while finding it.

---

## Why it happens

That error is not an expired token. It is a **GitHub App installation token with read-only scopes** — the connector your assistant uses was granted `Contents: Read` when it was installed.

Three things follow from that, and all three waste people's time:

- **Reconnecting the connector never helps.** The scope is set where the app was issued, not where you click "reconnect".
- **`permissions.push: true` is a liar.** The repo API returns it even for a read-only token. It describes *your* role on the repo, not the token's power.
- **Every generic "check your PAT scopes" answer is wrong here.** There is no PAT. That is the whole problem.

The only way forward is credentials you control, on the machine doing the work.

---

## The fix

```bash
git clone https://github.com/dasein-chao/github-write-access
cd github-write-access
bash setup.sh
```

`setup.sh` tells you what your machine actually has, then walks you through the one credential step it needs:

- **Browser authorization** — one click on GitHub's own page, nothing to copy around (default).
- **Personal access token** — if you are on a headless box, or only have a phone. Details in [Mobile and headless](#mobile-and-headless).

Windows: double-click `open-write-access.cmd` instead. It does the same thing and keeps the window open so you can read the result.

---

## Verify it, don't assume it

```bash
bash verify.sh --repo you/your-repo
```

This is the part most setups skip, and it is why they silently fail later.

`verify.sh` creates a throwaway branch, commits a file, **pushes it for real**, confirms the branch exists on the remote, then deletes it. Anything less is not proof:

- "Token saved" — not proof. We once stored a made-up token that our tool accepted without complaint.
- "Login exited 0" — not proof. Same reason.
- A branch that shows up on github.com — proof.

Output is either `PASS` or `FAIL` with the specific cause and what to do about it.

---

## Daily use

```bash
bash push.sh -m "note to self"
```

Adds everything, commits, rebases if the remote moved, pushes. It will not force-push, delete branches, or rewrite history.

No global `user.name` set? It borrows the repo owner and a `noreply` address **for that repo only**, instead of quietly changing your global git config.

---

## Traps we already hit

Each of these cost us real time. They are the reason this repo exists.

- **A credential tool that never validates your token.** Git Credential Manager's `--pat` flag stores whatever you give it and exits `0`. A fake token goes in, every push fails afterwards, and it looks exactly like a permissions problem. Always verify the token against `/user` first.
- **`push` hanging instead of failing.** With no credential, GCM opens a GUI prompt and waits forever. Two minutes of silence is not a slow network. Disable interaction: `GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never`.
- **A `.cmd` file saved with LF endings.** cmd.exe cuts commands in half: `'01' is not recognized`, `!VAR!` never expands. Windows batch files need CRLF.
- **Deriving `bash` from the `git` path.** In some bundles `/mingw64` and `/usr` both sit at the filesystem root, so `../..` resolves to `/` and you get `//usr/bin/bash.exe`. Convert the path you actually want.
- **Swallowing your own error message.** `user="$(check_token "$t")"` captures stdout — including the "token invalid" line you printed. Print diagnostics to stderr and let the caller say what happened.
- **Verifying against an empty repository.** Cloning a repo with no commits gives you an empty directory and no branch to test on.

Run `setup.sh --status` any time you are unsure where you stand.

---

## Mobile and headless

You can authorize from a phone; you cannot run the scripts from one. The split:

1. On the phone, create a fine-grained token: **Settings → Developer settings → Personal access tokens → Fine-grained tokens**. Repository access: the repos you want. Permissions: **Contents: Read and write**.
2. On the machine, save it to a file and point the script at it:

```bash
bash setup.sh --token-file ~/.github-token
```

The token is checked against GitHub before it is stored, and never printed — only its length and first characters.

Headless boxes use the same path. There is no terminal to draw a browser prompt in, so do not try to run an interactive login there; it will hang rather than fail.

---

## What's in here

```
setup.sh              diagnose, then configure credentials
verify.sh             prove write access with a real push, then clean up
push.sh               commit and push in one step
open-write-access.cmd Windows double-click launcher
TROUBLESHOOTING.md    error text → cause → fix
```

No dependencies beyond `git`, `curl`, and a shell.

---

## Scope

This is deliberately small. It does not wrap the GitHub API, it does not replace your git client, and it does not talk to your repos for you. It solves one problem — a machine that cannot push — and then gets out of the way.

If your connector *can* write, you do not need this repo.

MIT licensed.
