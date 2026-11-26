# GitHub 写权限

**AI 助手能读你的仓库，但一写就 `403`。一分钟修好：一个脚本，不需要建新应用，不用注册任何服务。**

如果你把代码贴进对话，拿回的是这一句：

```
403 Resource not accessible by integration
```

那这个仓库就是给你写的。里面除了修复方法，还有我们踩出来的 11 个坑。

---

## 为什么会这样

这不是 token 过期。这是**只读范围的 GitHub App 安装令牌**——你的助手用的连接器在安装时只拿到了 `Contents: Read`。

由此有三件事，件件浪费人的时间：

- **重连连接器永远没用。** 范围是发应用的地方定的，不是点「重新连接」的地方定的。
- **`permissions.push: true` 会骗人。** 只读令牌照样返回 true，它描述的是「你在这个仓库的角色」，不是令牌的权力。
- **所有「检查一下 PAT 权限」的通用答案在这里都不适用。** 因为压根没有 PAT，这就是问题本身。

唯一的出路是：在真正干活的这台机器上，放一份你自己控制的凭据。

---

## 修复

```bash
git clone https://github.com/dasein-chao/github-write-access
cd github-write-access
bash setup.sh
```

`setup.sh` 先告诉你这台机器到底有什么，再带你走完唯一那一步凭据配置：

- **浏览器授权**——在 GitHub 自己的页面上点一次，不用复制任何东西（默认方式）。
- **个人访问令牌**——无桌面的机器，或者你手上只有手机时用。见下面「手机与无桌面环境」。

Windows 直接双击 `open-write-access.cmd`。做的是同一件事，窗口会停住让你看清结果。

---

## 要验证，不要假设

```bash
bash verify.sh --repo 你的用户名/你的仓库
```

这一步大多数教程都跳过了，也正是它们后面默默失败的原因。

`verify.sh` 会建一个临时分支、提交一个文件、**真推送**、确认远端真的存在这个分支，然后删掉。比这更弱的证据都不算数：

- 「令牌已保存」——不算。我们曾经存进去一个瞎编的 token，工具照样一声不吭地接受了。
- 「登录命令退出码 0」——不算。同一个原因。
- github.com 上真的出现了那个分支——才算。

输出只有两种：`PASS`，或者 `FAIL` 加上具体原因和该怎么办。

---

## 日常使用

```bash
bash push.sh -m "记个想法"
```

暂存全部、提交、远端有新提交就先 rebase、推送。不 force、不删分支、不改写历史。

没设全局 `user.name`？它用仓库所有者和 `noreply` 邮箱，**只写进这个仓库**，不会偷偷改你的全局 git 配置。

---

## 已经踩过的坑

每一条都真花过时间。这个仓库存在的理由就是它们。

- **一个从不校验令牌的凭据工具。** Git Credential Manager 的 `--pat` 参数给什么存什么，退出码还是 `0`。假令牌进去了，之后每次推送都失败，症状和权限不足一模一样。存之前必须自己调 `/user` 验一遍。
- **push 不是失败，是挂住。** 没有凭据时它会弹一个 GUI 框并一直等。两分钟没输出不是网络慢。禁掉交互：`GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never`。
- **`.cmd` 文件用 LF 换行。** cmd.exe 会把命令从中间切断：报 `'01' 不是内部或外部命令`，`!VAR!` 永远不展开。Windows 批处理必须是 CRLF。
- **拿 git 路径去推 bash 路径。** 某些打包版把 `/mingw64` 和 `/usr` 都挂在根上，`../..` 会解析到 `/`，拼出 `//usr/bin/bash.exe`。要转换哪个路径就转哪个，别推算。
- **自己的错误提示被自己吞掉。** `user="$(check_token "$t")"` 把 stdout 一起捕获了，包括你刚打印的「令牌无效」。诊断信息走 stderr，结论让调用方说。
- **拿空仓库做验证。** 无提交的仓库克隆下来是空目录，根本没有分支可测。

任何时候不确定状态，跑 `setup.sh --status`。

---

## 手机与无桌面环境

手机可以完成授权，但跑不了脚本。分工是这样：

1. 手机上创建细粒度令牌：**Settings → Developer settings → Personal access tokens → Fine-grained tokens**。Repository access 选你要的仓库，Permissions 里 **Contents: Read and write**。
2. 在机器上把它存成文件，指给脚本：

```bash
bash setup.sh --token-file ~/.github-token
```

令牌会先经过 GitHub 校验才入库，全程不打印明文，只报长度和开头几个字符。

无桌面环境走同一条路。那里没有终端可以画浏览器提示，别尝试交互式登录——它不会报错，只会静静挂住。

---

## 里面有什么

```
setup.sh              诊断，然后配置凭据
verify.sh             用一次真实推送证明权限，然后清理干净
push.sh               一步完成提交和推送
open-write-access.cmd Windows 双击启动器
TROUBLESHOOTING.md    报错原文 → 原因 → 处置
```

除 `git`、`curl` 和一个 shell 之外没有依赖。

---

## 边界

这个项目故意做得很小。它不包装 GitHub API，不替代你的 git 客户端，也不替你跟仓库对话。它只解决一件事——一台推不上去的机器——解决完就让开。

如果你的连接器本来就能写，你不需要这个仓库。

MIT 协议。
