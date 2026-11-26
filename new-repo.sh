#!/usr/bin/env bash
# new-repo.sh — 建仓库只剩一个鼠标动作：点 Create
#
#   bash new-repo.sh <目录>                起名、算描述、弹浏览器、等创建、自动推送
#   bash new-repo.sh <目录> --url-only     只打印要打开的链接（agent 拿去弹）
#   bash new-repo.sh <目录> --watch        只做等待 + 推送（配合 --url-only）
#   可选: --name 名字  --desc "描述"  --private  --wait 秒  --no-push
#
# 设计前提：agent 负责命名、描述、绑定、推送；用户只点一次 Create。
# 不向用户索取令牌。SSH 负责推送，建仓库这一步永远是网页动作。
set -uo pipefail

DIR=""; NAME=""; DESC=""; PRIV=0; WAIT=300; MODE="full"; NOPUSH=0; OVERWRITE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name)      NAME="${2:-}"; shift 2 ;;
    --desc)      DESC="${2:-}"; shift 2 ;;
    --private)   PRIV=1; shift ;;
    --wait)      WAIT="${2:-300}"; shift 2 ;;
    --url-only)  MODE="url"; shift ;;
    --watch)     MODE="watch"; shift ;;
    --no-push)   NOPUSH=1; shift ;;
    --overwrite) OVERWRITE=1; shift ;;
    -h|--help)   sed -n '2,10p' "$0"; exit 0 ;;
    -*)          printf '未知选项: %s\n' "$1" >&2; exit 2 ;;
    *)           DIR="$1"; shift ;;
  esac
done

DIR="${DIR:-$PWD}"
[ -d "$DIR" ] || { printf '目录不存在: %s\n' "$DIR" >&2; exit 1; }
DIR="$(cd "$DIR" && pwd)"

say() { printf '%s\n' "$*"; }

# ---------- 身份 ----------
ssh_login() {
  local out
  out="$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
            -T git@github.com 2>&1)"
  printf '%s\n' "$out" | sed -n 's/^Hi \([^!]*\)!.*/\1/p'
}

OWNER="${GITHUB_OWNER:-$(ssh_login)}"
[ -n "$OWNER" ] || { say "SSH 没通，拿不到你的 GitHub 用户名。先跑 ssh-setup.sh。"; exit 1; }

# ---------- 起名 ----------
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^[._-]\{1,\}//; s/[._-]\{1,\}$//' \
    | cut -c1-80
}

guess_name() {
  local n=""
  if [ -f "$DIR/package.json" ]; then
    n="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DIR/package.json" | head -1)"
  fi
  if [ -z "$n" ] && [ -f "$DIR/pyproject.toml" ]; then
    n="$(sed -n 's/^name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$DIR/pyproject.toml" | head -1)"
  fi
  if [ -z "$n" ] && [ -f "$DIR/README.md" ]; then
    n="$(sed -n 's/^#[[:space:]]\{1,\}//p' "$DIR/README.md" | head -1)"
  fi
  [ -n "$n" ] || n="$(basename "$DIR")"
  n="$(slugify "$n")"
  # 纯日期或纯数字的目录名当不了仓库名
  case "$n" in
    ""|*[!0-9-]*) : ;;
    *) n="project-$n" ;;
  esac
  printf '%s' "$n"
}

guess_desc() {
  local d=""
  if [ -f "$DIR/package.json" ]; then
    d="$(sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$DIR/package.json" | head -1)"
  fi
  if [ -z "$d" ] && [ -f "$DIR/README.md" ]; then
    # 跳过标题行，取第一段有内容的文字
    d="$(sed -n '2,40p' "$DIR/README.md" \
         | sed '/^[[:space:]]*$/d; /^#/d; /^```/d; /^>.*/d; /^[-*][[:space:]]/d' \
         | head -1)"
  fi
  [ -n "$d" ] || d="${NAME:-$(guess_name)}"
  # 描述框不渲染 markdown，也吃不下换行和超长
  printf '%s' "$d" | sed 's/`//g; s/\*\*//g; s/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c1-300
}

[ -n "$NAME" ] || NAME="$(guess_name)"
[ -n "$DESC" ] || DESC="$(guess_desc)"

# ---------- 弹浏览器 ----------
open_url() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) cmd //c start "" "$1" >/dev/null 2>&1 ;;
    Darwin)               open "$1" >/dev/null 2>&1 ;;
    *)                    xdg-open "$1" >/dev/null 2>&1 ;;
  esac
}

enc() { printf '%s' "$1" | sed 's/%/%25/g; s/ /%20/g; s/#/%23/g; s/&/%26/g; s/?/%3F/g; s/+/%2B/g'; }

DESC_ENC="$(enc "$DESC")"
URL="https://github.com/new?name=$(enc "$NAME")&description=${DESC_ENC}&owner=${OWNER}"

if [ "$MODE" = "url" ]; then
  printf '%s\n' "$URL"
  exit 0
fi

# ---------- 本地仓库就绪 ----------
repo_exists() {
  GIT_TERMINAL_PROMPT=0 git ls-remote "git@github.com:$OWNER/$NAME.git" >/dev/null 2>&1
}

remote_has_commits() {
  GIT_TERMINAL_PROMPT=0 git ls-remote --heads "git@github.com:$OWNER/$NAME.git" 2>/dev/null | grep -q .
}

# 拒绝覆盖已有 origin。这不是洁癖：目录里可能挂着别的项目，删掉就找不回来。
check_origin_safe() {
  local cur
  cur="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
  [ -z "$cur" ] && return 0
  case "$cur" in
    *"$OWNER/$NAME.git"|*"$OWNER/$NAME"|"git@github.com:$OWNER/$NAME.git") return 0 ;;
  esac
  if [ "$OVERWRITE" -ne 1 ]; then
    say "这个目录的 origin 指向别的地方，不会动它:"
    say "  $cur"
    say "要么换个空目录重新来，要么确认后加 --overwrite"
    return 1
  fi
  say "警告：按 --overwrite 替换 origin ($cur)"
  return 0
}

push_now() {
  if [ ! -d "$DIR/.git" ]; then
    say "初始化本地仓库"
    git -C "$DIR" init -q
  fi
  check_origin_safe || return 1

  git -C "$DIR" rev-parse --verify HEAD >/dev/null 2>&1 || {
    say "本地还没有提交，先提交一次"
    git -C "$DIR" add -A
    git -C "$DIR" -c user.name="$OWNER" -c user.email="$OWNER@users.noreply.github.com" \
        commit -q -m "initial commit"
  }

  git -C "$DIR" remote remove origin 2>/dev/null
  git -C "$DIR" remote add origin "git@github.com:$OWNER/$NAME.git"

  local BR
  BR="$(git -C "$DIR" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  [ "$BR" = "main" ] || git -C "$DIR" branch -M main 2>/dev/null

  say "推到 origin/main ..."
  if GIT_TERMINAL_PROMPT=0 git -C "$DIR" push -q -u origin main 2>&1 | sed 's/^/  /'; then
    :
  fi
  if ! GIT_TERMINAL_PROMPT=0 git -C "$DIR" ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    say "推送失败。诊断:"
    GIT_TERMINAL_PROMPT=0 git -C "$DIR" push -u origin main 2>&1 | sed 's/^/  /' | head -8
    return 1
  fi
  say ""
  say "完成: https://github.com/$OWNER/$NAME"
  say "文件数: $(git -C "$DIR" ls-files | wc -l | tr -d ' ')  分支: main"
  return 0
}

# ---------- 只等 ----------
if [ "$MODE" = "watch" ]; then
  check_origin_safe || exit 4
  if repo_exists && remote_has_commits && [ "$OVERWRITE" -ne 1 ]; then
    say "github.com/$OWNER/$NAME 已经有内容了，不会往上推。"
    say "确认要覆盖再说，或者用 --name 换个名字。"
    exit 3
  fi
  if repo_exists && ! remote_has_commits; then
    say "仓库已建好（空），直接推送"
    [ "$NOPUSH" -eq 1 ] && exit 0
    push_now; exit $?
  fi
  say "等待 https://github.com/$OWNER/$NAME 出现（最多 ${WAIT}s）"
  END=$(( $(date +%s) + WAIT ))
  while [ "$(date +%s)" -lt "$END" ]; do
    if repo_exists; then
      say "  → 仓库出现了"
      [ "$NOPUSH" -eq 1 ] && exit 0
      sleep 2
      push_now; exit $?
    fi
    printf '.'
    sleep 3
  done
  say ""
  say "等超时了。仓库还没建，或者名字被改过。"
  exit 1
fi

# ---------- 完整流程 ----------
check_origin_safe || exit 4

if repo_exists; then
  say "github.com/$OWNER/$NAME 这个名字已经被占用了。"
  if remote_has_commits; then
    say "里面有内容，不会动它。换一个名字：--name 别的名字"
    exit 3
  fi
  say "它是个空仓库，可以直接推：bash $0 \"$DIR\" --watch --name $NAME"
  exit 3
fi

say "仓库名  : $NAME"
say "描述    : $DESC"
say "目录    : $DIR"
say "可见性  : $([ "$PRIV" -eq 1 ] && echo Private || echo Public)"
say ""
say "浏览器已打开，点绿色 Create repository 就行。其余我来。"
open_url "$URL"
say "没弹出来就点: $URL"
say ""

END=$(( $(date +%s) + WAIT ))
CREATED=0
while [ "$(date +%s)" -lt "$END" ]; do
  if repo_exists; then CREATED=1; break; fi
  printf '.'
  sleep 3
done
say ""

if [ "$CREATED" -ne 1 ]; then
  say "等了 ${WAIT}s 还没看到仓库。链接在这儿，随时可以点: $URL"
  say "点完再跑: bash $0 \"$DIR\" --watch"
  exit 1
fi

say "仓库已创建，开始推送"
sleep 2
[ "$NOPUSH" -eq 1 ] && { say "跳过推送（--no-push）"; exit 0; }
push_now || exit 1

say ""
say "可选：把 topics 粘上（About 旁齿轮），一行一个"
say "  $(printf '%s' "$NAME" | tr '-' ' ') cli tool"
