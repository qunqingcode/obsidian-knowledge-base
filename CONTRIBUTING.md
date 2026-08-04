# Contributing

感谢你帮助改进 Obsidian Knowledge Base。项目优先接受可复现的问题、真实使用场景、兼容性反馈和带测试的改进。

## 提交问题

提交 Issue 前请先搜索已有讨论，并选择对应模板。Bug 报告应包含：

- 项目版本或 commit SHA；
- Agent、Windows、PowerShell、Node.js 和 Obsidian 版本；
- 当前搜索与图谱后端；
- 最小复现步骤、预期行为和实际行为；
- 已脱敏的诊断输出。

请勿公开粘贴以下内容：

- Vault 笔记正文；
- 真实 `config.json`；
- 本地绝对路径、账号、Token、IP 或服务器地址；
- QMD 索引、缓存或审计日志原文。

## 开发流程

1. Fork 仓库并从 `main` 创建分支；
2. 保持修改范围清晰，避免混入无关格式化；
3. 为行为变更补充确定性测试；
4. 本地运行完整测试；
5. 提交 Pull Request，并说明验证环境和兼容性影响。

```powershell
git clone https://github.com/YOUR_NAME/obsidian-knowledge-base.git
cd obsidian-knowledge-base
.\tests\run-tests.ps1
```

## 设计原则

贡献应保持这些项目边界：

- Markdown 和本地 Vault 是唯一事实来源；
- 默认本地优先、只读，不要求云端 Embedding；
- 搜索命中和图谱连接只是候选，语义结论必须读取原文；
- 回答引用实际使用的笔记及修改日期；
- 敏感内容仅在用户明确请求时最小化读取和输出；
- Obsidian 不运行或可选依赖不可用时应有清晰的本地降级路径。

## Pull Request 检查

- `./tests/run-tests.ps1` 全部通过；
- 新功能或修复有测试覆盖；
- README、安装文档和命令示例保持一致；
- 不包含用户数据、真实配置或机器专属文件；
- 第三方代码和设计来源已保留许可证及声明。

大范围架构调整请先创建 Feature Request，说明实际问题和预期行为，避免实现方向重复。
