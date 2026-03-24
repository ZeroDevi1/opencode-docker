# 部署示例定位整理设计

## 目标

- 保留仓库中现有的旧部署示例，避免删除后影响仍依赖历史方案的用户。
- 明确仓库根目录 `docker-compose.yml`、`.env.example`、`nginx.conf` 才是当前正式远程部署入口。
- 让 `README.md` 与 `docs/remote-deploy.md` 在“正式方案”和“历史参考 / 功能示例”之间建立稳定、清晰的分层，降低误读概率。

## 背景

- 当前根目录已经提供固定域名 `example.com` 的正式三服务部署方案：`opencode + nginx + acme`。
- `examples/compose.remote.yaml` 仍保留旧的 `codex + opencode + nginx + acme` 共栈结构，`examples/nginx.opencode.conf` 仍是另一套子域名反代模板。
- `examples/compose.docker-sock.yaml` 与 `examples/compose.weixin.yaml` 属于功能型运行示例，但目前在 README 中与正式部署入口并列展示，容易被误认为同等级方案。

## 设计原则

- 正式入口唯一：根目录正式部署文件必须被文档明确标注为首选入口。
- 历史信息保留：旧示例不删除，但需要显式标记为 `legacy` 或“历史参考”。
- 用途优先于文件名：README 不能只罗列路径，必须说明每个示例为什么存在。
- 不改变运行行为：本次整理仅调整说明、注释与文档分层，不重写旧示例的运行逻辑。

## 文件角色划分

### 正式部署入口

- `docker-compose.yml`：当前正式远程部署 Compose，固定为 `opencode + nginx + acme` 三服务结构。
- `.env.example`：正式部署所需变量模板，仅保留敏感值占位符。
- `nginx.conf`：正式反代配置，固定 `4395/4396 -> opencode:4096`，域名固定为 `example.com`。
- `docs/remote-deploy.md`：正式部署操作文档，只讲当前推荐方案。

### 历史参考

- `examples/compose.remote.yaml`：旧的 Codex/OpenCode 共栈远程部署参考，保留给仍需要共栈的用户。
- `examples/nginx.opencode.conf`：旧的独立子域名 Nginx 反代模板，保留为历史参考，不作为当前正式入口。

### 功能示例

- `examples/compose.docker-sock.yaml`：说明 OpenCode 直连宿主机 Docker Socket 的最小运行方式。
- `examples/compose.weixin.yaml`：说明带 `cc-connect` / 微信接入的运行方式。

## 文档分层设计

### README

- 在“远程部署建议”章节继续优先介绍根目录正式方案。
- 将示例链接拆分为两个层次：
  - 正式入口
  - 历史参考与功能示例
- 对每个示例增加一句用途说明，避免读者只看到文件名无法判断应使用哪一个。
- 对 `examples/compose.remote.yaml` 明确标注“legacy / 历史共栈参考”，避免与根目录正式方案混用。

### docs/remote-deploy.md

- 正文只描述根目录三服务正式部署流程。
- 将旧共栈方案和其他示例下沉到文末“历史参考与相关示例”小节。
- 历史示例只给出用途说明与跳转，不再在正文中并列描述两套部署流程。

## 示例文件自说明设计

- `examples/compose.remote.yaml` 文件头新增中文注释，说明它是历史共栈参考，不是当前默认正式部署方式。
- `examples/nginx.opencode.conf` 文件头新增中文注释，说明它是旧的子域名反代模板，仅供历史参考。
- `examples/compose.docker-sock.yaml` 与 `examples/compose.weixin.yaml` 文件头新增用途注释，强调它们是功能型示例，而不是正式远程部署入口。

## 约束与边界

- 不删除任何旧示例文件。
- 不把旧示例强行改造成根目录正式方案的重复版本。
- 不修改根目录 `docker-compose.yml`、`.env.example`、`nginx.conf` 的运行语义。
- 不调整镜像、容器、端口或证书处理逻辑。

## 验证方式

- 文本验证：确认 `README.md` 与 `docs/remote-deploy.md` 中“正式方案”与“历史参考 / 功能示例”分层清晰。
- 定位验证：确认每个 `examples/*.yaml` / `examples/*.conf` 文件头都含有清晰的用途注释。
- 差异验证：确认 Git diff 仅涉及文档和注释分层，不影响正式部署配置行为。

## 完成标准

- 新读者进入仓库后，能够第一时间识别“正式部署看根目录文件”。
- 仍依赖旧共栈方案的用户，仍可通过 `examples/compose.remote.yaml` 找到历史参考。
- README 与部署文档不再把历史示例与正式入口并列为同等级推荐方案。
