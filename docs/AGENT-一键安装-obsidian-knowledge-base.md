# Agent 一键安装任务书：Obsidian Knowledge Base

> 本文档的阅读对象是 AI Agent，不是最终用户。  
> Agent 获得本文档后，应自行完成环境检查、依赖安装、Skill 部署、配置生成和功能验收。

## 用户只需这样说

将本文档交给 Agent，然后发送：

```text
请按照《AGENT-一键安装-obsidian-knowledge-base.md》完成安装。
Obsidian Vault 路径：C:\path\to\your\vault
Skill 源码位置：C:\path\to\obsidian-knowledge-base
```

如果 Skill 已位于当前仓库，也可以省略源码位置，让 Agent 自动查找。

---

## Agent 执行指令

你正在安装 `obsidian-knowledge-base` Agent Skill。请持续执行到安装成功或确认遇到无法自行解决的阻塞，不要只输出操作建议。

### 1. 最终目标

将用户指定的 Obsidian Vault 配置为 Agent 的默认私人知识库，并确保以下能力可运行：

1. QMD 本地 BM25 全文搜索；
2. 单篇笔记读取；
3. Obsidian 实时双链图谱；
4. Obsidian 不可用时的文件解析降级；
5. 反向链接、N 跳邻居、最短路径和健康检查；
6. Agent 新任务中可以自动触发该 Skill。
7. 默认启用 `auto` 模式，无需用户每次重复“去 Obsidian 查询”。

### 2. 输入变量

从用户消息、当前工作区和系统环境中解析以下变量：

| 变量 | 是否必需 | 说明 |
|---|---:|---|
| `VAULT_PATH` | 是 | Obsidian Vault 的绝对路径 |
| `SKILL_SOURCE` | 自动 | `obsidian-knowledge-base` 源码目录；本地找不到时从官方仓库获取 |
| `SKILL_TARGET` | 自动 | 当前 Agent 的用户级 Skills 目录 |
| `QMD_COLLECTION` | 自动 | 默认 `obsidian`，冲突时生成唯一名称 |
| `OBSIDIAN_VAULT_NAME` | 自动 | 优先通过 CLI 获取，否则使用 Vault 文件夹名 |

如果 `VAULT_PATH` 未提供：

1. 在用户明确放入任务范围的目录中查找包含 `.obsidian` 的文件夹；
2. 仅找到一个时自动使用；
3. 找到多个或一个都未找到时，向用户询问准确路径。

如果 `SKILL_SOURCE` 未提供，按以下顺序查找：

1. 当前目录；
2. 当前仓库的 `obsidian-knowledge-base`；
3. 当前仓库的 `skills\obsidian-knowledge-base`；
4. 当前仓库的 `.agents\skills\obsidian-knowledge-base`；
5. 用户提供的发布包解压目录。

如果以上位置均不存在完整源码，使用 Git 从唯一可信的官方仓库克隆到新建的临时目录：

```powershell
$sourceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("obsidian-knowledge-base-" + [guid]::NewGuid().ToString("N"))
git clone --depth 1 https://github.com/qunqingcode/obsidian-knowledge-base.git $sourceRoot
$SKILL_SOURCE = $sourceRoot
```

如果 Git 不可用或官方仓库无法访问，停止安装并准确报告阻塞；不得改用第三方镜像。

如果 `SKILL_TARGET` 未提供：

1. 优先使用当前 Agent 官方约定的用户级 Skills 目录；
2. Codex 使用 `$env:USERPROFILE\.codex\skills\obsidian-knowledge-base`；
3. Claude Code 使用 `$env:USERPROFILE\.claude\skills\obsidian-knowledge-base`；
4. Cursor 使用 `$env:USERPROFILE\.cursor\skills\obsidian-knowledge-base`；
5. 当前 Agent 有其他原生 Skills 目录时，使用其官方目录；
6. 无法可靠识别当前 Agent 时，向用户确认目标目录，不要同时安装到多个未知目录。

源码目录必须包含：

```text
SKILL.md
scripts\vault.ps1
scripts\graph.ps1
scripts\graph-engine.js
scripts\get-behavior.ps1
docs\graph-queries.md
docs\THIRD_PARTY_NOTICES.md
```

获取源码后仍不完整时停止安装并准确报告缺失文件，不得凭空生成或下载来源不明的替代代码。

### 3. 已授权操作

用户要求执行一键安装，即授权 Agent 在当前计算机上：

- 读取系统版本、PATH 和已安装软件；
- 安装或升级 QMD；
- 在缺少 Node.js 时，通过可信官方来源安装 Node.js 22 LTS 或更高版本；
- 创建或更新 QMD Collection；
- 将 Skill 文件复制到当前用户的 Codex Skills 目录；
- 创建或更新该 Skill 的 `config.json`；
- 执行只读验证命令。

本授权不包括：

- 修改、重命名或删除 Vault 中的笔记；
- 向笔记批量写入双链；
- 上传 Vault、索引或配置到网络；
- 读取或展示无关账号、密码、Token、私钥；
- 删除其他 Skill 或其他 QMD Collection；
- 覆盖无法恢复的用户配置。

### 4. 安全约束

1. 所有路径先解析为绝对路径并确认目标准确。
2. 不递归删除任何目录。
3. 如果目标 Skill 已存在，先读取并保留现有 `config.json`。
4. 不用示例配置覆盖用户已有的有效配置。
5. 复制源码时排除源码中的真实 `config.json`，配置由本流程单独生成。
6. 不扫描或输出 Vault 中的账号密码内容。
7. 验收只使用普通、非敏感关键词；无法选择关键词时使用 `list` 和图谱统计。
8. 命令失败时记录命令、退出码和关键错误，不隐藏失败。
9. 不将用户的绝对路径提交到 Git 仓库。
10. 修改系统级安装前确认该动作属于本任务所需的正常安装步骤。

### 5. 执行阶段

#### 阶段 A：检查 Vault

验证：

```powershell
Test-Path -LiteralPath $VAULT_PATH -PathType Container
Test-Path -LiteralPath (Join-Path $VAULT_PATH ".obsidian") -PathType Container
Get-ChildItem -LiteralPath $VAULT_PATH -Recurse -Filter *.md -File |
    Select-Object -First 5 FullName
```

判定：

- 路径不存在：停止并要求用户修正；
- 没有 `.obsidian`：提示它可能只是 Markdown 目录，允许使用，但实时 Obsidian 图谱可能不可用；
- 没有任何 `.md`：停止并说明没有可索引内容；
- 不读取或展示笔记正文。

#### 阶段 B：检查 PowerShell 和 Node.js

执行：

```powershell
$PSVersionTable.PSVersion
Get-Command node -ErrorAction SilentlyContinue
node --version
npm --version
```

要求 Node.js `>=22.0.0`。

若未安装或版本过低：

1. 优先使用系统已有包管理器从 Node.js 官方发行渠道安装当前 LTS；
2. Windows 可使用：

```powershell
winget install OpenJS.NodeJS.LTS
```

3. 安装后刷新 PATH 或重新启动命令会话；
4. 再次验证 `node --version` 和 `npm --version`；
5. 若系统没有可信包管理器，不从未知镜像下载安装包，向用户报告阻塞。

#### 阶段 C：安装 QMD

检查：

```powershell
Get-Command qmd -ErrorAction SilentlyContinue
qmd --version
```

未安装或不可运行时执行：

```powershell
npm install -g @tobilu/qmd
```

然后获取真实路径：

```powershell
$nodePath = (Get-Command node).Source
$npmGlobalRoot = (npm root -g).Trim()
$qmdEntry = Join-Path $npmGlobalRoot "@tobilu\qmd\dist\cli\qmd.js"

Test-Path -LiteralPath $nodePath -PathType Leaf
Test-Path -LiteralPath $qmdEntry -PathType Leaf
```

两项必须都为 `True`。

#### 阶段 D：部署 Skill

目标目录使用前面解析出的 `SKILL_TARGET`。Codex 的示例为：

```powershell
$skillTarget = Join-Path $env:USERPROFILE ".codex\skills\obsidian-knowledge-base"
```

部署要求：

1. 确认 `SKILL_SOURCE` 与 `SKILL_TARGET` 不是同一路径；
2. 若目标不存在则创建；
3. 若目标已存在，先保存现有 `config.json` 内容；
4. 将源码中的以下内容复制到目标：
   - `SKILL.md`
   - `agents`
   - `scripts`
   - `docs`
   - `references`
5. 不从源码复制真实 `config.json`；
6. 不删除目标目录中的未知用户文件；
7. 部署后检查所有必需文件。

可使用 PowerShell 的 `Copy-Item -LiteralPath` 分项复制。不要使用会清空目标目录的镜像或同步参数。

#### 阶段 E：配置 QMD Collection

先读取：

```powershell
qmd collection list
```

处理规则：

1. 如果已有 Collection 指向同一个 `VAULT_PATH`，复用其名称；
2. 如果名称 `obsidian` 未占用，创建：

```powershell
qmd collection add "$VAULT_PATH" --name obsidian --mask "**/*.md"
```

3. 如果 `obsidian` 已被其他目录占用，使用 `obsidian-<vault文件夹名>`；
4. 不删除或改写用户其他 Collection；
5. 执行：

```powershell
qmd update
qmd collection list
```

记录最终 Collection 名称为 `QMD_COLLECTION`。

#### 阶段 F：探测 Obsidian CLI

按顺序探测：

```powershell
Get-Command obsidian -ErrorAction SilentlyContinue
Test-Path -LiteralPath "C:\Program Files\Obsidian\Obsidian.com" -PathType Leaf
Test-Path -LiteralPath "$env:LOCALAPPDATA\Obsidian\Obsidian.com" -PathType Leaf
```

找到后执行：

```powershell
obsidian version
obsidian vaults verbose format=json
```

或使用探测到的 `Obsidian.com` 绝对路径。

处理规则：

- CLI 可用且能识别目标 Vault：记录 CLI 路径和真实 Vault 名称；
- CLI 已安装但未启用：不阻塞安装，使用 `files` 降级并提醒用户启用；
- Obsidian 未运行：允许配置为 `auto`，验收时接受回退到 `files`；
- 无法匹配 Vault 名称：使用 Vault 文件夹名，并通过文件后端完成验收。

#### 阶段 G：生成配置

在 `SKILL_TARGET\config.json` 生成有效 JSON：

```json
{
  "vault_path": "<VAULT_PATH>",
  "qmd_executable": "<NODE_ABSOLUTE_PATH>",
  "qmd_entry": "<QMD_ENTRY_ABSOLUTE_PATH>",
  "qmd_collection": "<QMD_COLLECTION>",
  "behavior": {
    "mode": "auto",
    "log_retention_days": 30
  },
  "graph": {
    "backend": "auto",
    "obsidian_cli": "<OBSIDIAN_CLI_ABSOLUTE_PATH>",
    "obsidian_vault": "<OBSIDIAN_VAULT_NAME>",
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

要求：

- 使用 JSON 序列化工具生成，不手工拼接未经转义的路径；
- Windows 路径在 JSON 中正确转义；
- 写入后立即用 `ConvertFrom-Json` 重新解析；
- 验证所有文件路径存在；
- 如果 Obsidian CLI 未找到，`obsidian_cli` 可以填写预期默认路径，但验收必须接受 `files` 后端；
- 默认设置 `behavior.mode` 为 `auto`；除非用户明确要求，否则不要启用会记录路由事件的 `audit`；
- 配置不得包含密码、Token 或其他凭据。

#### 阶段 H：验收

从 `SKILL_TARGET` 执行以下测试。

1. 配置解析：

```powershell
Get-Content -LiteralPath ".\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
```

2. 行为模式：

```powershell
.\scripts\get-behavior.ps1
```

结果必须为 `mode=auto`、`automatic_routing=true`、`audit_logging=false`。

3. 列出笔记：

```powershell
.\scripts\vault.ps1 -Mode list
```

4. 图谱统计：

```powershell
.\scripts\vault.ps1 -Mode stats -Backend files
```

5. 自动后端：

```powershell
.\scripts\vault.ps1 -Mode stats -Backend auto
```

6. 健康检查：

```powershell
.\scripts\vault.ps1 -Mode health -Backend auto
```

7. 搜索测试：

- 从非敏感文件名中选取一个普通词作为查询词；
- 不使用“密码”“账号”“Token”“密钥”等词；
- 执行：

```powershell
.\scripts\vault.ps1 -Mode search -Query "<普通关键词>" -MaxResults 5
```

8. 图关系测试：

- 从 `stats` 或列表结果中选择一篇实际笔记；
- 执行：

```powershell
.\scripts\vault.ps1 -Mode neighbors -Note "<Vault相对路径.md>" -Depth 1 -Backend auto
```

### 6. 成功判定

同时满足以下条件才可报告安装成功：

- Node.js 版本不低于 22；
- QMD 可执行；
- QMD Collection 指向目标 Vault；
- Skill 必需文件完整；
- `config.json` 能成功解析；
- `get-behavior.ps1` 返回有效的 `auto` 模式；
- `list` 成功；
- `stats -Backend files` 成功；
- `stats -Backend auto` 成功，允许实际回退到 `files`；
- `health` 成功；
- 至少一次普通全文搜索成功执行；
- 未修改 Vault 内任何笔记。

`auto` 后端回退到 `files` 不属于安装失败，但必须在结果中说明实时 Obsidian CLI 尚未生效。

### 7. 失败处理

遇到错误时按顺序处理：

1. 读取完整错误；
2. 检查路径、版本和配置；
3. 修复后重试失败步骤；
4. 不重复执行已经成功且可能产生副作用的安装动作；
5. 不通过删除用户数据来解决问题；
6. 无法继续时报告：
   - 已完成阶段；
   - 失败阶段；
   - 原始关键错误；
   - 已尝试的修复；
   - 需要用户完成的最小操作。

只有以下情况需要中途询问用户：

- 无法确定唯一 Vault；
- 找不到 Skill 源码；
- 必须获取管理员权限且当前 Agent 无法申请；
- 需要用户在 Obsidian 界面手动启用 CLI；
- 发现现有配置与目标 Vault 冲突，且无法安全合并。

### 8. 最终报告格式

安装成功后，向用户返回：

```text
安装结果：成功

Vault：<绝对路径>
Skill：<绝对路径>
Node.js：<版本>
QMD：<版本>
Collection：<名称>
行为模式：auto
图谱后端：<obsidian 或 files>
笔记数量：<数量>
图节点/边：<统计>

已通过：
- 全文搜索
- 文件读取
- 图谱统计
- 邻居查询
- 健康检查

说明：
<是否启用实时 Obsidian CLI；如使用 files，说明如何启用>

下一步：
请新建一个 Agent 任务，然后直接提问：
“查一下我的 Obsidian 里关于 <主题> 的记录，并列出相关笔记。”
```

不要在最终报告中输出笔记正文、账号密码、Token 或其他敏感内容。

---

## 给 Agent 的最短执行提示

如果 Agent 已能读取本文档，只需发送：

```text
严格执行本文档中的“Agent 执行指令”，持续完成安装和全部验收。
Vault 路径：C:\path\to\your\vault
Skill 源码位置：C:\path\to\obsidian-knowledge-base
不得修改 Vault 中的任何笔记。
```
