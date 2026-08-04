# Security Policy

## Supported versions

安全修复优先应用于 `main` 和最新 GitHub Release。

## Reporting a vulnerability

请勿在公开 Issue 中提交可被直接利用的漏洞细节、真实 Vault 内容、凭证、私人路径或服务器信息。

推荐通过仓库的 **Security → Report a vulnerability** 私下报告，并提供：

- 受影响版本或 commit SHA；
- 最小复现步骤；
- 潜在影响；
- 不包含真实用户数据的概念验证；
- 建议修复方式（如有）。

如果 GitHub 私密报告入口暂不可用，请先创建一个不含漏洞细节的普通 Issue，请求维护者提供私密沟通渠道。

## Scope

重点关注：

- Vault 路径边界绕过；
- 未经明确授权读取或输出敏感笔记；
- 搜索预览、审计日志或错误输出泄露敏感值；
- 笔记内容影响 Agent 权限或安全策略；
- 安装脚本从不可信来源下载并执行代码；
- Obsidian CLI `eval` 或图谱脚本中的任意代码执行风险。

本项目的敏感信息拦截不能替代密码管理器、磁盘加密或操作系统访问控制。生产凭证不应长期保存在 Markdown 中。
