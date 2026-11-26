#!/usr/bin/env bash
# ssh-setup.sh — generate a key, print the public half, verify GitHub accepts it
# 用法:
#   bash ssh-setup.sh                       只生成并打印公钥
#   bash ssh-setup.sh --test owner/repo     额外验证某个仓库能否读写
#   bash ssh-setup.sh --add-remote owner/repo [本地目录]   绑定 origin 并推送
set -uo pipefail

KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15"

# --- 1. 生成 ---
if [ ! -f "$KEY" ]; then
  mkdir -p "$(dirname "$KEY")"
  ssh-keygen -t ed25519 -C "workbuddy-$(date +%Y%m%d)" -f "$KEY" -N "" -q || {
    echo "密钥生成失败" >&2; exit 1; }
  echo "已生成新密钥: $KEY"
else
  echo "复用已有密钥: $KEY"
fi

echo
echo "=== 把这行公钥贴到 GitHub（Settings → SSH and GPG keys → New SSH key）==="
cat "$KEY.pub"
echo
echo "指纹: $(ssh-keygen -lf "$KEY.pub" 2>/dev/null | awk '{print $2}')"
echo "公钥位置: $KEY.pub   （公钥是公开信息，发给谁都没风险）"
echo "私钥: $KEY          （绝不要外发）"
echo

# --- 2. 连通性 ---
check_auth() {
  GIT_SSH_COMMAND="ssh $SSH_OPTS" ssh -T git@github.com 2>&1
}

OUT="$(check_auth || true)"
if printf '%s' "$OUT" | grep -q "successfully authenticated"; then
  LOGIN="$(printf '%s' "$OUT" | sed -n 's/^Hi \([^!]*\)!.*/\1/p')"
  echo "✅ 认证通过，身份: ${LOGIN:-未知}"
  AUTH_OK=1
else
  echo "❌ 还没连通。GitHub 返回："
  printf '%s\n' "$OUT" | head -6
  echo
  echo "→ 公钥尚未添加到账号。添加地址: https://github.com/settings/ssh/new"
  AUTH_OK=0
fi

# --- 3. 可选：验证某仓库 ---
if [ "${1:-}" = "--test" ] || [ "${1:-}" = "--add-remote" ]; then
  REPO="${2:-}"
  [ -n "$REPO" ] || { echo "缺仓库参数 owner/repo" >&2; exit 1; }
  if [ "$AUTH_OK" != "1" ]; then
    echo "认证未通过，跳过仓库验证"; exit 2
  fi
  if GIT_SSH_COMMAND="ssh $SSH_OPTS" git ls-remote "git@github.com:$REPO.git" >/dev/null 2>&1; then
    echo "✅ 可访问 $REPO"
  else
    echo "❌ 访问不了 $REPO —— 仓库不存在，或不是你的"
    exit 3
  fi

  if [ "${1:-}" = "--add-remote" ]; then
    DIR="${3:-$PWD}"
    cd "$DIR" || exit 1
    git remote remove origin 2>/dev/null
    git remote add origin "git@github.com:$REPO.git"
    echo "已绑定 origin = git@github.com:$REPO.git （目录 $DIR）"
    echo "推送命令: git push -u origin main"
  fi
fi
