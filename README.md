# Obsidian Knowledge Base

<p align="center">
  <strong>简体中文</strong> · <a href="./README.en.md">English</a>
</p>

<p align="center">
  <img src="./docs/assets/social-preview.jpg" alt="Obsidian Knowledge Base — Local-first knowledge for AI agents" width="100%">
</p>

[![test](https://github.com/qunqingcode/obsidian-knowledge-base/actions/workflows/test.yml/badge.svg)](https://github.com/qunqingcode/obsidian-knowledge-base/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![skills.sh](https://skills.sh/b/qunqingcode/obsidian-knowledge-base)](https://skills.sh/qunqingcode/obsidian-knowledge-base/obsidian-knowledge-base)

把本地 Obsidian Vault 一键接成 Codex、Claude Code、Cursor 等 AI Agent 默认使用的私人知识库。

Agent 会遵循同一套工具无关的私人知识策略，自动判断什么时候需要查询，完成本地全文检索、原文读取、双链关联扩展和来源引用。Markdown 始终是唯一事实来源，Vault 不需要上传到云端。

**本地优先 · 默认只读 · 无需云端 Embedding · 回答可追溯**

[一键安装](#一键安装) · [让 Agent 代为安装](#让-agent-代为安装) · [效果演示](#效果演示) · [安全边界](#安全边界) · [完整文档](#文档)

## 效果演示

安装后，不必每次提醒 Agent “去 Obsidian 查”。直接用自然语言提问：

```text
我们上次为什么调整那项设置？
```

Agent 会按需完成：

```text
判断问题可能依赖私人知识
  → 在本地 Vault 检索相关 Markdown
  → 读取原文并沿双链发现直接关联笔记
  → 检查敏感信息、冲突和过期证据
  → 返回答案，并附原始笔记路径与修改日期
```

它还可以回答关系型问题，例如：

- “这篇笔记有哪些反向链接？”
- “A 和 B 之间最短通过哪些笔记连接？”
- “找出知识库里的核心节点和孤岛笔记。”
- “生成一份 Vault 知识图谱健康报告。”

## 一键安装

下载或克隆本仓库后，只需一条命令：

```powershell
.\install.ps1 -VaultPath "D:\你的 Obsidian Vault"
```

安装器会自动识别本机现有的 Codex、Claude Code、Cursor 或通用
`.agents/skills` 目录，部署 Skill、生成配置、安装可选 QMD 搜索后端，
并运行 `doctor` 验收。指定 Agent 或安装目录时使用：

```powershell
.\install.ps1 -VaultPath "D:\Vault" -Agent claude
.\install.ps1 -VaultPath "D:\Vault" -Agent custom -TargetPath "D:\agent\skills\obsidian-knowledge-base"
```

不希望安装 QMD 时加 `-SkipQmd`；全文搜索会自动使用内置文件后端，图谱也不依赖 Obsidian 正在运行。

安装后诊断：

```powershell
.\scripts\doctor.ps1
```

## 让 Agent 代为安装

将下面这段话完整发送给支持 Agent Skills 和本地命令执行的 Agent：

```text
请阅读并严格执行下面的安装任务书，把我的 Obsidian 一键接入为 Agent 默认私人知识库。
持续完成环境检查、依赖安装、Skill 部署、配置生成和功能验收；除非无法确定 Vault 路径，否则不要只给操作建议。

https://github.com/qunqingcode/obsidian-knowledge-base/blob/main/docs/AGENT-INSTALL.md
```

Agent 会自动完成：

1. 定位或询问 Obsidian Vault；
2. 检查 Node.js、QMD 和 Obsidian CLI；
3. 安装 Skill 到当前用户的 Agent Skills 目录；
4. 创建本机私有 `config.json`；
5. 建立本地 BM25 索引，失败时保留内置文件搜索；
6. 验证搜索、引用和知识图谱能力。

默认使用 `auto` 模式。安装完成后可直接问：

```text
最近写过的那份文档在哪里？
我们上次为什么调整那项设置？
哪些笔记提到了同一个主题？
找出知识库中没有链接的孤岛笔记。
```

不需要每次额外说“去 Obsidian 查”。

## skills.sh / CLI 安装

只安装 Skill 文件：

```powershell
npx skills add https://github.com/qunqingcode/obsidian-knowledge-base `
  --skill obsidian-knowledge-base `
  --agent codex `
  --global `
  --copy `
  --yes
```

将 `codex` 换成当前 Agent 的 CLI 标识即可。这个命令会把 Skill 安装到用户级目录，但不会替你确定 Vault、安装 QMD 或生成私人配置；首次使用仍建议把上面的“一键集成”任务书交给 Agent，让它完成环境配置和验收。

## 三种运行模式

在本机 `config.json` 中配置：

```json
{
  "behavior": {
    "mode": "auto",
    "log_retention_days": 30
  }
}
```

| 模式 | 行为 | 适合场景 |
|---|---|---|
| `auto` | 自动判断是否查询私人知识，不记录路由日志 | 默认推荐 |
| `on_demand` | 仅在用户明确要求查询 Vault 时运行 | 希望完全手动控制 |
| `audit` | 自动查询，并写入本地脱敏评估日志 | 调试路由和评测检索质量 |

日志只保存在本机 Skill 的 `logs/` 目录，不包含笔记正文，并会对密码、Token、账号和 IP 等内容脱敏。

## 核心能力

- 工具无关的路由、隐私、证据和引用策略，可由不同 Agent 一致执行
- QMD/BM25 本地全文搜索，不强制使用云端 Embedding API
- QMD 不可用时自动使用内置全文搜索，不中断知识库访问
- 搜索后读取原文，回答附带本地文件来源和修改日期
- `context` 检索自动用一跳双链补充关联知识，图谱结果只作为候选线索
- 出链、反向链接、N 跳邻居、最短路径和关系汇总
- 连通分量、Hub、桥、孤岛、未解析链接和图谱健康分析
- 优先读取 Obsidian 实时链接缓存，不可用时降级为 Markdown 文件解析
- 敏感结果默认隐藏，只有用户明确请求时才允许读取
- 忽略笔记中试图改变 Agent 行为或权限的指令
- 区分无结果、超时、读取失败和证据不足

## 为什么不是另一个 Obsidian MCP

MCP 和 Obsidian CLI 主要解决“Agent 能调用哪些工具”。本项目还规定：

- 什么时候应该查询私人知识；
- 哪些候选可以读取；
- 什么证据可以进入最终回答；
- 如何处理冲突、过期和敏感文档；
- 如何对路由和检索质量做本地评估。

它可以独立使用，也可以作为现有 Agent 工具层之上的检索与证据策略。

## 安全边界

- 默认只读，不自动修改、移动或删除 Vault 笔记。
- `config.json`、本地索引和日志均被 `.gitignore` 排除。
- 生产凭证不应长期保存在 Markdown；建议只在 Obsidian 中保存密码管理器引用。
- Obsidian CLI 的 `eval` 权限较高，只运行仓库内固定的图查询脚本。
- 多用户、远程或群聊环境不应读取私人敏感笔记。

## 测试

仓库包含一个不含真实信息的测试 Vault，覆盖：

- 一键安装、自动配置和 `doctor` 验收
- 无 QMD 时的内置全文搜索降级
- `context` 搜索命中后的双链关联扩展
- Markdown 双链解析和未解析链接
- 最短路径、桥和孤岛统计
- `on_demand`、`auto`、`audit` 配置
- 路由日志中的 IP 与凭证脱敏
- Skill frontmatter 基础校验

Windows 本地运行：

```powershell
.\tests\run-tests.ps1
```

每次 Push 和 Pull Request 都会通过 GitHub Actions 在 Node.js 22 + PowerShell 环境执行测试。

## 文档

- [Agent 一键安装任务书](./docs/AGENT-INSTALL.md)
- [完整安装文档](./docs/obsidian-knowledge-base-安装文档.md)
- [图查询参考](./docs/graph-queries.md)
- [检索评估规范](./references/evaluation.md)
- [贡献指南](./CONTRIBUTING.md)
- [安全策略](./SECURITY.md)
- [变更记录](./CHANGELOG.md)
- [第三方声明](./docs/THIRD_PARTY_NOTICES.md)

## 平台范围

当前版本是 Windows-first：

- Windows 10/11
- PowerShell 5.1+
- Node.js 18+（推荐当前 LTS）
- 支持 Agent Skills 的本地 Agent
- Obsidian 1.12.7+ 可启用实时图谱；未启用时自动使用文件后端

## License

[MIT](./LICENSE)。图查询能力包含对 MIT 许可项目 `azuma520/obsidian-graph-query` 思路的适配，详见[第三方声明](./docs/THIRD_PARTY_NOTICES.md)。
