# ZCode 多 Agent 团队配置（锻刀大师）

本文件定义锻刀大师项目多 Agent 团队工作流在 ZCode 环境下的实现。体系于 2026-10-15 自 gonghui 项目迁移（gonghui 版又源自 feitu 项目的事故沉淀，跑通 M0→M6 全程开发）。团队规则由两处承载：

- **根 `AGENTS.md`**：Team Lead（主代理）规则。ZCode 每次会话自动加载
- **`.zcode/agents/<role>.md`**：5 个子角色提示词（自定义子代理类型定义，frontmatter：`name`/`description`/`readOnly`/`tools`/`color`/`thoughtLevel`）→ 主代理以 `subagent_type: <角色名>` 直接派工，工具权限硬性生效，模型跟随会话模型

---

## 团队结构

```
Team Lead（主代理 = ZCode 本体，规则见根 AGENTS.md）— 唯一持久角色
  ├─ @planner（策划）        — 需求→策划案
  ├─ @architect（架构师）    — 策划案→程序方案
  ├─ @programmer（程序员）   — 程序方案→代码
  ├─ @docs-updater（文档）   — 代码变更→文档同步
  └─ @git-admin（Git管理）   — 所有 Git 操作
```

## 工作流铁律

1. **严格顺序，步步审核**：planner → 用户审 → architect → 用户审 → programmer → **用户明确"同意"** → docs-updater → 主代理更新日志 → git-admin
2. **同角色多轮复用 agentId**（SendMessage），不开新代理
3. **一轮结束标志**：docs-updater 完成文档 + 主代理更新工作日志
4. **传递累计完整方案**，不只传最后一条增量
5. **三条事故红线**：用户未答复=冻结 / 转达必标来源 / 追认≠预授权

## 平台实测结论（自 gonghui 迁移，勿重复踩坑）

1. **`tools:` 白名单硬性生效**（上限限权）；`readOnly` 单独**不**生效——每个角色都必须写 tools 列表
2. **子代理内 AskUserQuestion 被权限层自动放行**（答复非用户本意）→ 一切用户确认经 Team Lead 在主会话转达；**拍板类管线禁跑 yolo 权限模式**
3. **"Agent type not found"** 系克隆中间态/会话未注册 → 回退 `general-purpose` + 注入角色文件全文（先 Read 再置于提示词开头）
4. **Glob/Grep 注入不稳定**（不按角色稳定复现）→ 白名单含 Bash 的角色可用只读 shell 命令替代，实际使用无碍
5. **子代理最终消息只回主代理、用户看不到** → 每阶段必须由主代理完整转达产物
6. **agentId 复用**：同角色多轮用 SendMessage 发同一 agentId 续聊；重开新代理 = 丢上下文

## Agent 间通信规则

所有 Agent 之间的信息传递必须通过对话完成（主代理转发），**严禁用文件作为通信媒介**：

- 策划案/架构方案作为对话文本输出，不写成长文档存盘传递
- `.zcode/agents/*.md` 是**自定义子代理类型定义**（frontmatter 硬限工具），不是通信产物
- 除 @docs-updater 外任何角色不得写文档目录；`.zcode/memory/` 只归 Team Lead

## 文件结构

```
锻刀大师项目根目录/
├── AGENTS.md                      # Team Lead 规则（ZCode 每次会话自动加载）
├── docs/                          # 设计文档（策划案 + 系统详细设计，版本号命名）
├── plugins/                       # 本地插件市场（防线 hooks 插件化）
│   ├── marketplace.json           # 市场清单（name=dev-duanzao，条目 duanzao-defense）
│   └── duanzao-defense/           # 插件「锻刀防线 Hooks」
│       ├── .zcode-plugin/
│       │   └── plugin.json        # 插件清单（name/version，hooks 指向 ./hooks/hooks.json）
│       └── hooks/
│           ├── hooks.json         # 插件格式注册（${CLAUDE_PLUGIN_ROOT} 定位脚本）
│           ├── ask_gate.cjs       # AskUserQuestion 强制人工确认（PreToolUse）
│           └── ask_timeout_gate.cjs  # 超时未答复 → 注入冻结指令（PostToolUse）
├── sim/ data/ scenes/ mesh/ fx/ ui/ audio/ tests/ tools/   # Godot 工程目录（M0 建立时落地）
└── .zcode/
    ├── config.json                # 项目级 MCP 配置（godot-ai 编辑器桥接 + godot-mcp）
    ├── docs/
    │   └── AGENTS_CONFIG.md       # 本文件（团队规程 + 平台实测结论）
    ├── agents/                    # 5 个自定义子代理类型定义（frontmatter 硬限工具）
    │   ├── planner.md  architect.md  programmer.md
    │   └── docs-updater.md  git-admin.md
    ├── skills/
    │   └── godot-code-style/      # GDScript 官方风格指南 skill（自 gonghui 原样迁移）
    └── memory/
        ├── MEMORY.md              # 永久记忆（项目架构、规则、约定）
        └── logs/                  # 每日工作日志 YYYY-MM-DD.md
```

## 记忆系统

- **永久记忆**：`.zcode/memory/MEMORY.md` — 主代理会话开始必读（根 AGENTS.md「会话启动检查」）；阶段性关键事实与决策追加（新条目放最上面）
- **工作日志**：`.zcode/memory/logs/YYYY-MM-DD.md` — 由 Team Lead 在 @docs-updater 完成后、@git-admin 提交前更新
- **Team Lead 唯一直改**记忆文件，其余项目文件修改全部通过子代理

## 防线 Hooks 插件（duanzao-defense 0.3.0）

自 gonghui-defense 0.3.0 迁移（hooks 脚本逐字节一致，已实弹闭环验证），运维知识必须保留：

- **必须 process 型**：`command:"node"` 走 PATH + `args` 以 `${CLAUDE_PLUGIN_ROOT}` 定位脚本。**勿改 command 型 `shell:"bash"`**——spawn 靠 PATH 裸名解析 bash，Windows 桌面进程 PATH 无 bash（Git 安装器默认只把 `<Git>\cmd` 加入系统 PATH，无 bash.exe）必 spawn ENOENT 秒败
- **为什么走插件**：配置文件 hooks（用户级+工作区）在本平台从未被 runner 执行（gonghui 2026-09-20 实测，含工作区信任门不生效）；插件 hooks 自动启用、无信任门、无需 enabled 标志
- **安装**（每台电脑 clone 后）：插件市场 → 添加 → 本地目录 `<仓库>/plugins` → 安装「锻刀防线 Hooks」。前置条件：机器装有 node
- **本地市场读快照**：「添加」时把 `plugins/` 复制为快照，改源文件后刷新无效——须**移除市场重新添加**强制重建快照才能识别新版本
- **插件更新后必须完整重启 ZCode**：热注册钩表会残留旧版 hook 配置，致「装了新版却按旧版失败」的假象

## 迁移记录（2026-10-15，自 gonghui）

- **原样复制**：`.zcode/config.json`（MCP：godot-ai 4.2.3 + godot-mcp）；`skills/godot-code-style/`（SKILL.md + static-typing.md）；防线 hooks 三件（ask_gate.cjs / ask_timeout_gate.cjs / hooks.json）
- **回填重写**：5 个角色文件（gonghui 槽位 → 锻刀大师：文档路径、架构铁律按系统详细设计 §0/§12、自查命令占位、git 仓库待建）；根 AGENTS.md（项目速查全新）；本文件（精简，保留全部平台实测知识）
- **初始化**：memory（MEMORY.md + logs 当日日志）
- **未迁移**：gonghui 的 plans/、memory 全部内容、DEMO 工具脚本与 23 份规划案（模式参考，不搬实体）
- **待办**：selfcheck.cmd 待 M0 建立 Godot 工程后参照 gonghui 版改造（GODOT_BIN 双路解析 + gdUnit4 全量 + headless 数据校验）；git 仓库待建（init 后回填 git-admin 与项目速查）
