# Obsidian Knowledge Base 安装文档

本文档用于在 Windows 上安装 `obsidian-knowledge-base` Agent Skill，将本地 Obsidian Vault 接入 AI Agent，提供全文搜索、双链图谱遍历、多跳关系查询和来源引用能力。

## 1. 安装后的能力

安装完成后，Agent 可以：

- 自动把指定 Obsidian Vault 作为私人知识库；
- 使用 QMD 对 Markdown 内容进行本地 BM25 搜索；
- 查询正向链接、反向链接和 N 跳邻居；
- 查找两篇笔记之间的最短连接路径；
- 分析 Hub、桥接节点、孤岛和未解析链接；
- Obsidian 未运行时自动降级到本地文件解析；
- 回答时引用实际笔记路径；
- 默认只读，不会自行修改 Vault。

## 2. 环境要求

| 项目 | 要求 |
|---|---|
| 操作系统 | Windows 10/11 |
| PowerShell | 5.1 或更高版本 |
| Node.js | 18 或更高版本，推荐当前 LTS |
| Obsidian | 建议 1.12.7 或更高版本 |
| Agent | 支持 Agent Skills，例如 Codex |
| 知识库 | 本地 Obsidian Vault |

Obsidian CLI 用于获取实时链接图谱。若不安装或不启动 Obsidian，Skill 仍可使用文件解析后端。

## 3. 推荐：一条命令安装

在项目根目录运行：

```powershell
.\install.ps1 -VaultPath "D:\你的 Obsidian Vault"
```

默认自动选择已有 Agent Skills 目录、安装 QMD、生成配置并执行 `doctor`。
使用其他 Agent 时可传 `-Agent codex|claude|cursor|agents`，未知 Agent
使用 `-Agent custom -TargetPath <目录>`。离线或不需要 QMD 时使用
`-SkipQmd`，系统会自动使用内置文件搜索。

以下章节仅用于手动安装和排障。

## 4. 安装 Node.js

已安装 Node.js 的用户可以跳过本节。

从 [Node.js 官网](https://nodejs.org/)安装 Node.js 18 或更高版本，然后重新打开 PowerShell。

验证：

```powershell
node --version
npm --version
```

`node --version` 应显示 `v22.x.x` 或更高版本。

## 5. 安装 QMD

在 PowerShell 中执行：

```powershell
npm install -g @tobilu/qmd
```

验证：

```powershell
qmd --version
```

如果系统提示找不到 `qmd`，关闭并重新打开 PowerShell，然后检查：

```powershell
npm prefix -g
npm root -g
```

参考：[QMD 官方仓库](https://github.com/tobi/qmd)。

## 6. 安装 Skill

### 6.1 手动安装

将完整的 `obsidian-knowledge-base` 目录复制到：

```text
C:\Users\<用户名>\.codex\skills\obsidian-knowledge-base
```

目录结构必须保持如下：

```text
obsidian-knowledge-base/
├── SKILL.md
├── config.json
├── agents/
│   └── openai.yaml
├── scripts/
│   ├── vault.ps1
│   ├── graph.ps1
│   └── graph-engine.js
└── docs/
    ├── graph-queries.md
    └── THIRD_PARTY_NOTICES.md
```

### 6.2 从 Skills 生态安装

项目发布到 GitHub 或 skills.sh 后，可使用：

```powershell
npx skills add OWNER/REPO@obsidian-knowledge-base -g -y
```

将 `OWNER/REPO` 替换为实际的 GitHub 仓库名称。

参考：[Skills CLI 文档](https://www.skills.sh/docs/cli)。

## 7. 创建 QMD 索引

将下面的 Vault 路径替换为自己的实际路径：

```powershell
qmd collection add "C:\path\to\your\vault" --name obsidian --mask "**/*.md"
qmd update
qmd collection list
```

说明：

- `obsidian` 是 Collection 名称；
- 如果该名称已存在，可以换成其他名称；
- 更换名称后，必须同步修改 `config.json` 中的 `qmd_collection`；
- Skill 每次搜索前会同步 Collection；
- 当前搜索链路使用 BM25，不要求下载 Embedding 模型。

## 8. 启用 Obsidian CLI

如需读取 Obsidian 的实时链接缓存，请启用 Obsidian CLI：

1. 打开 Obsidian；
2. 进入“设置”；
3. 打开“关于”或“General”页面；
4. 找到高级设置中的命令行界面；
5. 启用 CLI 并按提示完成 PATH 注册；
6. 重新打开 PowerShell。

验证：

```powershell
obsidian version
obsidian vaults verbose format=json
```

如果 `obsidian` 命令没有加入 PATH，也可以直接测试默认安装位置：

```powershell
& "C:\Program Files\Obsidian\Obsidian.com" version
```

参考：[Obsidian CLI 官方文档](https://obsidian.md/help/cli)。

## 9. 配置 Skill

打开：

```text
C:\Users\<用户名>\.codex\skills\obsidian-knowledge-base\config.json
```

填写以下配置：

```json
{
  "config_version": 2,
  "vault_path": "C:\\path\\to\\your\\vault",
  "qmd_executable": "C:\\path\\to\\node.exe",
  "qmd_entry": "C:\\path\\to\\node_modules\\@tobilu\\qmd\\dist\\cli\\qmd.js",
  "qmd_collection": "obsidian",
  "search": {
    "backend": "auto"
  },
  "behavior": {
    "mode": "auto",
    "log_retention_days": 30
  },
  "graph": {
    "backend": "auto",
    "obsidian_cli": "C:\\Program Files\\Obsidian\\Obsidian.com",
    "obsidian_vault": "your-vault-name",
    "excluded_folders": [
      ".obsidian/",
      ".trash/",
      ".git/",
      "attachments/",
      "templates/"
    ],
    "relationship_fields": [
      "Up",
      "Source",
      "References",
      "来源",
      "参考",
      "应用于",
      "衍生自"
    ],
    "frontmatter_mapping": {
      "domain": "专业",
      "source": "来源",
      "noteType": "笔记类型"
    }
  }
}
```

`auto` 是推荐默认值：Agent 会自动判断什么时候查询私人知识，但不记录路由日志。也可改为仅明确调用时运行的 `on_demand`，或开启本地脱敏评估日志的 `audit`。

### 9.1 查找 Node.js 路径

```powershell
(Get-Command node).Source
```

将输出的绝对路径填入 `qmd_executable`。

### 9.2 查找 QMD 入口

```powershell
npm root -g
```

在输出目录后追加：

```text
\@tobilu\qmd\dist\cli\qmd.js
```

将完整路径填入 `qmd_entry`。

### 9.3 确认 Vault 名称

```powershell
obsidian vaults verbose format=json
```

将目标 Vault 的名称填入 `graph.obsidian_vault`。这通常是 Vault 根目录的文件夹名称。

### 9.4 图谱后端

`graph.backend` 支持：

| 配置值 | 行为 |
|---|---|
| `auto` | 优先使用 Obsidian 实时图谱，失败时自动使用文件解析，推荐 |
| `obsidian` | 强制使用 Obsidian CLI，Obsidian 不可用时直接报错 |
| `files` | 始终解析本地 Markdown，Obsidian 无需运行 |

## 10. 验证安装

进入 Skill 目录：

```powershell
cd "$env:USERPROFILE\.codex\skills\obsidian-knowledge-base"
```

### 10.1 验证全文搜索

```powershell
.\scripts\vault.ps1 -Mode search -Query "测试关键词" -MaxResults 10
```

日常问答优先使用带图谱关联扩展的上下文检索：

```powershell
.\scripts\vault.ps1 -Mode context -Query "测试关键词" -MaxResults 5 -MaxRelated 10
```

`hits` 是全文检索结果，`related` 是从命中文档的一跳链接中发现的关联候选。
关联候选必须读取后才能作为回答证据。

如果 Vault 中存在相关内容，应返回笔记路径、标题和匹配片段。

### 10.2 验证笔记读取

```powershell
.\scripts\vault.ps1 -Mode read -Note "文件夹\笔记名称.md"
```

`-Note` 必须是 Vault 内的相对路径。

### 10.3 验证图谱统计

```powershell
.\scripts\vault.ps1 -Mode stats
```

输出中的 `_meta.backend` 表示实际使用的后端：

- `obsidian`：使用 Obsidian 实时链接缓存；
- `files`：使用本地文件解析。

### 10.4 验证反向链接

```powershell
.\scripts\vault.ps1 -Mode backlinks -Note "笔记名称.md"
```

### 10.5 验证多跳邻居

```powershell
.\scripts\vault.ps1 -Mode neighbors -Note "笔记名称.md" -Depth 2
```

### 10.6 验证最短路径

```powershell
.\scripts\vault.ps1 -Mode path -From "起点笔记.md" -To "终点笔记.md"
```

### 10.7 验证知识库健康状态

```powershell
.\scripts\vault.ps1 -Mode health
```

## 11. 在 Agent 中使用

完成配置后，重新启动或新建一个 Codex 任务，使 Skill 被重新加载。

之后可以直接使用自然语言，例如：

- “查一下 Vault 里的示例主题。”
- “哪些文档链接到了示例文档？”
- “找出 A 笔记两跳以内的相关文件。”
- “A 和 B 两篇文档是怎么连接起来的？”
- “列出知识库里的核心笔记。”
- “检查孤岛笔记和未解析链接。”
- “生成知识图谱健康报告。”

Agent 会按问题自动选择全文搜索或图谱查询，并在形成结论前读取相关笔记。

## 12. 常见问题

### 12.1 PowerShell 禁止运行脚本

查看当前策略：

```powershell
Get-ExecutionPolicy -List
```

可以仅为当前进程临时放行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

然后重新执行验证命令。

### 12.2 提示找不到 QMD

依次检查：

```powershell
node --version
npm root -g
qmd --version
```

确认 `config.json` 中的 `qmd_executable` 和 `qmd_entry` 都是存在的绝对路径。

### 12.3 搜索没有结果

检查 Collection：

```powershell
qmd collection list
qmd update
```

确认：

- Collection 指向正确的 Vault；
- `qmd_collection` 与 Collection 名称一致；
- Vault 内存在 `.md` 文件；
- 搜索词确实出现在笔记中。

### 12.4 图谱自动降级为 files

检查：

```powershell
obsidian version
obsidian vaults verbose format=json
```

同时确认：

- Obsidian 正在运行；
- CLI 已启用；
- `graph.obsidian_cli` 指向正确的可执行文件；
- `graph.obsidian_vault` 与实际 Vault 名称一致。

如果不需要实时缓存，使用 `files` 后端属于正常行为，不影响基本双链分析。

### 12.5 找不到指定笔记

先搜索得到准确的 Vault 相对路径：

```powershell
.\scripts\vault.ps1 -Mode search -Query "标题片段"
```

再把返回的 `.md` 路径传给 `backlinks`、`neighbors` 或 `path`。

### 12.6 Obsidian 中有链接，但查询结果缺失

可能原因包括：

- 链接指向同名笔记；
- 链接尚未解析；
- 文件夹被 `excluded_folders` 排除；
- Obsidian 缓存尚未刷新；
- Vault 名称配置错误。

可以分别测试两个后端：

```powershell
.\scripts\vault.ps1 -Mode backlinks -Note "笔记名称.md" -Backend obsidian
.\scripts\vault.ps1 -Mode backlinks -Note "笔记名称.md" -Backend files
```

## 13. 安全建议

- 不要把真实 `config.json` 提交到公开仓库；
- 公开发布时提供 `config.example.json`；
- 将 `config.json`、Vault、索引和缓存加入 `.gitignore`；
- 不要在 Markdown 中长期保存明文密码、Token 或私钥；
- 不要把整个 Vault 打包进 Skill；
- Skill 默认只读，除非用户明确要求，否则不应修改笔记或新增链接；
- Obsidian `eval` 具备访问应用内部对象的能力，只应运行项目提供的固定查询逻辑。

## 14. 升级

升级 QMD：

```powershell
npm install -g @tobilu/qmd@latest
qmd update
```

升级 Skill 时：

1. 备份本机 `config.json`；
2. 用新版本替换 Skill 文件；
3. 恢复或合并配置；
4. 重新执行全文搜索、`stats` 和 `health` 验证。

不要用示例配置覆盖已经填写好的真实配置。

## 15. 卸载

删除 QMD Collection：

```powershell
qmd collection remove obsidian
```

如需同时卸载 QMD：

```powershell
npm uninstall -g @tobilu/qmd
```

最后删除：

```text
C:\Users\<用户名>\.codex\skills\obsidian-knowledge-base
```

卸载 Skill 不会删除或修改 Obsidian Vault。

## 16. 安装完成检查表

- [ ] Node.js 版本不低于 18；
- [ ] `qmd --version` 可运行；
- [ ] QMD Collection 指向正确 Vault；
- [ ] Skill 目录结构完整；
- [ ] `config.json` 中所有路径均为绝对路径；
- [ ] 全文搜索返回正确结果；
- [ ] `stats` 返回图谱统计；
- [ ] `backlinks` 或 `neighbors` 返回关联笔记；
- [ ] 新建 Agent 任务后可以自动调用知识库；
- [ ] 配置文件和 Vault 未被提交到公开仓库。
