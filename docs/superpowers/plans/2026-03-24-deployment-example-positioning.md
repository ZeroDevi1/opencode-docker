# Deployment Example Positioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重新整理仓库中的部署示例定位，让根目录正式部署配置成为唯一推荐入口，同时保留旧示例作为明确标注的历史参考或功能示例。

**Architecture:** 这次实现只调整文档结构和示例文件头注释，不改正式部署配置的运行逻辑。`README.md` 与 `docs/remote-deploy.md` 负责建立“正式入口 / 历史参考 / 功能示例”的清晰层次，`examples/*` 文件通过头部注释自我声明用途，避免新用户把历史示例误认为正式入口。

**Tech Stack:** Markdown、YAML、Nginx 配置文本、PowerShell/rg 文本校验、git diff

---

### Task 1: 重构 README 中的部署入口分层

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 写出 README 当前混用示例的失败断言**

Run: `rg -n "可直接参考：|examples/compose.remote.yaml|examples/nginx.opencode.conf" README.md`
Expected: 能看到正式入口与多个示例被直接并列列出，说明当前层次仍不够清晰。

- [ ] **Step 2: 修改 README 的远程部署入口说明**

把 `README.md` 中“可直接参考”与“远程部署建议”相关段落改为两层结构：

1. `正式入口`：
   - `docker-compose.yml`
   - `.env.example`
   - `docs/remote-deploy.md`
   - `nginx.conf`
2. `历史参考与功能示例`：
   - `examples/compose.remote.yaml`：legacy，旧的 Codex/OpenCode 共栈远程部署参考
   - `examples/nginx.opencode.conf`：legacy，旧的子域名反代模板
   - `examples/compose.docker-sock.yaml`：功能示例，最小 Docker Socket 运行方式
   - `examples/compose.weixin.yaml`：功能示例，微信 / `cc-connect` 接入方式

- [ ] **Step 3: 运行 README 文本校验，确认新层次已出现**

Run: `rg -n "正式入口|历史参考与功能示例|legacy|功能示例" README.md`
Expected: 四类关键词都能在 README 中找到，且与对应文件说明成对出现。

- [ ] **Step 4: 提交本任务**

```bash
git add README.md
git commit -m "docs(readme): 明确部署示例定位分层"
```

### Task 2: 为历史示例和功能示例补充文件头注释

**Files:**
- Modify: `examples/compose.remote.yaml`
- Modify: `examples/nginx.opencode.conf`
- Modify: `examples/compose.docker-sock.yaml`
- Modify: `examples/compose.weixin.yaml`

- [ ] **Step 1: 写出示例文件缺少用途注释的失败断言**

Run: `rg -n "legacy|历史参考|功能示例|正式部署入口" examples/compose.remote.yaml examples/nginx.opencode.conf examples/compose.docker-sock.yaml examples/compose.weixin.yaml`
Expected: 当前没有或明显缺少完整用途注释，因此命令输出不足以覆盖四个文件。

- [ ] **Step 2: 给 `examples/compose.remote.yaml` 增加 legacy 注释**

在文件头新增中文注释，明确说明：

- 这是历史共栈参考
- 包含 `codex + opencode + nginx + acme`
- 不是当前仓库根目录的默认正式部署方式

- [ ] **Step 3: 给 `examples/nginx.opencode.conf` 增加 legacy 注释**

在文件头新增中文注释，明确说明：

- 这是旧的子域名反代模板
- 用于历史参考
- 不等同于根目录 `nginx.conf`

- [ ] **Step 4: 给两个功能示例补充用途注释**

在 `examples/compose.docker-sock.yaml` 与 `examples/compose.weixin.yaml` 文件头分别新增中文注释，强调：

- 它们是功能型运行示例
- 不是正式远程部署入口
- 应配合 README 中的说明理解用途

- [ ] **Step 5: 运行注释覆盖校验**

Run: `rg -n "legacy|历史参考|功能示例|不是正式远程部署入口|不是当前仓库根目录的默认正式部署方式" examples/compose.remote.yaml examples/nginx.opencode.conf examples/compose.docker-sock.yaml examples/compose.weixin.yaml`
Expected: 四个文件都能命中至少一条用途说明。

- [ ] **Step 6: 提交本任务**

```bash
git add examples/compose.remote.yaml examples/nginx.opencode.conf examples/compose.docker-sock.yaml examples/compose.weixin.yaml
git commit -m "docs(examples): 标注历史与功能示例用途"
```

### Task 3: 收敛正式部署文档中的历史示例入口

**Files:**
- Modify: `docs/remote-deploy.md`

- [ ] **Step 1: 写出文档仍混入历史示例的失败断言**

Run: `rg -n "compose.remote.yaml|历史参考|相关示例|正式配置" docs/remote-deploy.md`
Expected: 当前能看到历史示例跳转，但分层尚未收敛到单独的小节。

- [ ] **Step 2: 调整 `docs/remote-deploy.md` 的示例引用结构**

将 `docs/remote-deploy.md` 中对 `examples/compose.remote.yaml` 等文件的引用移动到文末单独小节，例如“历史参考与相关示例”，并在该小节中分别说明：

- `examples/compose.remote.yaml`：Codex/OpenCode 共栈历史参考
- `examples/nginx.opencode.conf`：旧的子域名反代模板
- `examples/compose.docker-sock.yaml`：最小 Docker Socket 示例
- `examples/compose.weixin.yaml`：微信接入示例

正文继续只描述根目录正式三服务方案，不再在流程段落中并列展开历史方案。

- [ ] **Step 3: 运行文档分层校验**

Run: `rg -n "历史参考与相关示例|共栈历史参考|子域名反代模板|Docker Socket 示例|微信接入示例" docs/remote-deploy.md`
Expected: 文末存在独立示例分层，且每个引用文件都有用途说明。

- [ ] **Step 4: 提交本任务**

```bash
git add docs/remote-deploy.md
git commit -m "docs(deploy): 收敛历史示例入口说明"
```

### Task 4: 复核差异范围并确认未改变正式部署语义

**Files:**
- Modify: `README.md`
- Modify: `docs/remote-deploy.md`
- Modify: `examples/compose.remote.yaml`
- Modify: `examples/nginx.opencode.conf`
- Modify: `examples/compose.docker-sock.yaml`
- Modify: `examples/compose.weixin.yaml`
- Verify only: `.env.example`
- Verify only: `docker-compose.yml`
- Verify only: `nginx.conf`

- [ ] **Step 1: 复查正式配置文件与变量模板未被改动**

Run: `git diff -- .env.example docker-compose.yml nginx.conf`
Expected: 无输出，说明正式部署运行配置和变量模板未被本次整理触碰。

- [ ] **Step 2: 复查改动只落在文档与示例定位层**

Run: `git diff -- README.md docs/remote-deploy.md examples/compose.remote.yaml examples/nginx.opencode.conf examples/compose.docker-sock.yaml examples/compose.weixin.yaml`
Expected: Diff 只包含 README / 文档结构调整和文件头注释，不包含端口、容器名、证书路径等正式运行逻辑变更。

- [ ] **Step 3: 运行最终文本分层校验**

Run: `pwsh -NoLogo -c "rg -n '正式入口|历史参考与功能示例|legacy|功能示例' README.md; rg -n '历史参考与相关示例|共栈历史参考|子域名反代模板|Docker Socket 示例|微信接入示例' docs/remote-deploy.md; rg -n 'legacy|历史参考|功能示例|不是正式远程部署入口|不是当前仓库根目录的默认正式部署方式' examples/compose.remote.yaml examples/nginx.opencode.conf examples/compose.docker-sock.yaml examples/compose.weixin.yaml"`
Expected: README、部署文档和四个示例文件都命中对应定位说明，且命中内容与规格一致。

- [ ] **Step 4: 提交最终收尾变更**

```bash
git add README.md docs/remote-deploy.md examples/compose.remote.yaml examples/nginx.opencode.conf examples/compose.docker-sock.yaml examples/compose.weixin.yaml docs/superpowers/specs/2026-03-24-deployment-example-positioning-design.md docs/superpowers/plans/2026-03-24-deployment-example-positioning.md
git commit -m "docs(deploy): 区分正式入口与历史示例"
```
