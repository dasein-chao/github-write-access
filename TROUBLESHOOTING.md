# Troubleshooting

Find your error text below. Every entry here was reproduced for real, not guessed.

Run `bash setup.sh --status` first — it answers most of these in one shot.

---

## `403 Resource not accessible by integration`

A GitHub App installation token. The app was installed with read-only repository access.

- Reconnecting it does nothing. The scope lives where the app was issued.
- `permissions.push: true` from the repo API does **not** contradict this. That field describes your role on the repo, not the token's power.
- Fix: stop using that connector for writes, and give the machine a credential of its own — `bash setup.sh`.

## `403 Resource not accessible by personal access token`

A fine-grained token without `Contents: Read and write`, or the repo is not in the token's repository list.

Fix: edit the token. Add the repo, set Contents to Read and write. No need to regenerate it.

## `remote: Permission to owner/repo.git denied to user`

The credential is valid; the account simply has no write access to that repo. Not a token problem.

For organization repos, the token may also need SSO authorization from the org's settings page.

## `Authentication failed` or `Invalid username or token. Password authentication is not supported`

The stored credential itself is broken — revoked, expired, or never valid to begin with.

```
bash setup.sh --clean
bash setup.sh
```

## No error at all — the command just hangs

No credential, and the credential helper opened a GUI prompt that nobody can click. This is the most misdiagnosed failure in the whole list; it looks like a slow network.

Already handled inside these scripts via:

```
GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never
```

If you are writing your own commands, set those too. Silence is not success.

## `Cannot prompt because terminal prompts have been disabled`

You are in a non-interactive shell (CI, a container, or an agent's shell). Interactive login cannot work there — it will not error, it will just stall.

Use the token path instead: `bash setup.sh --token-file ~/.github-token`.

## `'01' is not recognized as an internal or external command` (Windows)

Your `.cmd` file has LF line endings. cmd.exe splits lines and mangles commands: `chcp 65001` becomes `chcp` + `01`, and `!VAR!` never expands.

Save it with CRLF. Any decent editor can do this; so does `sed 's/$/\r/'`.

## `//usr/bin/bash.exe` — doubled slash (Windows)

You derived a bash path by walking up from the git executable. In some distributions both `/mingw64` and `/usr` sit at the filesystem root, so `../..` resolves to `/`.

Convert the path you actually want instead of computing it:

```
cygpath -w /usr/bin/bash.exe
```

## Empty directory after cloning

The repo has no commits. There is no branch, so nothing can be tested or pushed.

Pick a repo with at least one commit.

## `Updates were rejected because the remote contains work that you do not have locally`

Not a permission problem. Pull first:

```
git pull --rebase
```

`push.sh` does this automatically when the remote has moved.

## Storing a token "succeeded" but every push fails

Your credential tool happily stored an invalid token. Git Credential Manager's `--pat` flag does exactly this: any string is accepted, exit code `0`, no validation.

Always validate before storing:

```
curl -s -H "Authorization: Bearer $TOKEN" https://api.github.com/user
```

`setup.sh --token-file` does this for you, and refuses to store a token GitHub rejects.
