# OpenSpec Global Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让镜像在构建阶段默认全局安装 `@fission-ai/openspec@latest`，并同步 README 说明，避免文档与实际行为不一致。

**Architecture:** 沿用现有镜像构建方式，在 `Dockerfile` 中同时更新默认全局 npm 包环境变量和构建期 `npm install -g` 命令。README 仅同步默认包列表、可覆盖示例与验证命令，不改动 entrypoint 逻辑或运行时行为。

**Tech Stack:** Dockerfile、npm、README Markdown、git

---

### Task 1: 更新镜像默认全局 npm 包

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: 更新默认环境变量**

将 `VFOX_GLOBAL_NPM_PACKAGES` 从 `"ace-tool @upstash/context7-mcp"` 改为 `"ace-tool @upstash/context7-mcp @fission-ai/openspec@latest"`。

- [ ] **Step 2: 更新构建期全局安装命令**

将构建期 `npm install -g` 命令补充 `@fission-ai/openspec@latest`，保持镜像首次构建时就具备该命令。

- [ ] **Step 3: 自检 Dockerfile 变更**

确认默认环境变量与构建期安装命令保持一致，没有遗漏运行时覆盖路径。

### Task 2: 同步 README 说明

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 更新默认全局 npm 包列表**

在“默认会准备”小节中加入 `@fission-ai/openspec@latest`。

- [ ] **Step 2: 更新覆盖示例**

将 `VFOX_GLOBAL_NPM_PACKAGES` 示例补充 `@fission-ai/openspec@latest`，确保文档和默认值一致。

- [ ] **Step 3: 更新验证命令**

把本地验证命令补充为同时检查 `openspec --version`，让文档体现新增工具已随镜像提供。

### Task 3: 验证、提交与推送

**Files:**
- Modify: `Dockerfile`
- Modify: `README.md`

- [ ] **Step 1: 运行最小验证**

Run: `docker build -t opencode-docker:local .`
Expected: 构建成功，`npm install -g` 可完成 `@fission-ai/openspec@latest` 安装。

- [ ] **Step 2: 运行工具版本检查**

Run: `docker run --rm opencode-docker:local bash -lc "bun --version && opencode --version && openspec --version"`
Expected: 三个命令都输出版本信息并成功退出。

- [ ] **Step 3: 提交改动**

Run: `git add Dockerfile README.md docs/superpowers/plans/2026-03-22-openspec-global-install.md && git commit -m "build(docker): 在镜像中预装 openspec 工具"`
Expected: 生成中文提交，包含 Dockerfile、README 与计划文档。

- [ ] **Step 4: 推送分支**

Run: `git push`
Expected: 当前分支成功推送到远端。
