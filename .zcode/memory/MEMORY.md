# duanzao 项目 · 永久记忆

> Team Lead 会话启动必读；阶段性关键事实追加到「近期关键记录」（新条目放最上面），过时条目及时清理。

## 项目状态（2026-10-16 重启）

- **项目重启**：用户判定旧进度偏差，决定从头开始设计（2026-10-16 用户指令）。旧 M0 实现、设计文档、开发记录已全部清理，旧信息一律以 git 历史为准（关键提交：cbfffdd 旧设计文档 / e6deab6 M0 原型 / 2748876+c303fc7+85d73bb 最后两轮修改），**不得把旧设计当作现行依据**
- 当前仓库状态：团队工作流骨架——.zcode/ 团队体系、plugins/ 防线插件、AGENTS.md（速查已重置）、addons/（gdUnit4 + godot_ai 工具链）、最小 project.godot（仅插件注册与 autoload，无主场景无输入表）；无业务代码、无设计文档
- 下一步：等待用户新需求 → @planner 走策划流程；新设计立项时重定架构与工程规范（旧版铁律/selfcheck/auto-play 基建已随旧设计清理，git 历史可查）

## 合规红线（长期有效，不随重启失效）

- 赛制思想（三轮淘汰/测试裁决/限定材料）可用；节目名（Forged in Fire/锻刀大赛/千锤百炼）、真人评委姓名肖像、节目口号（"It will Keal"）、演播室视觉**全部不可碰**，一律原创；营销素材不蹭节目名

## 团队体系

- 五子代理（planner/architect/programmer/docs-updater/git-admin）+ Team Lead；工作规则见根 AGENTS.md，平台机制见 .zcode/docs/AGENTS_CONFIG.md
- 防线插件 duanzao-defense（ask_gate / ask_timeout_gate）——每台电脑安装：插件市场 → 添加本地目录 `plugins/` → 装「锻刀防线 Hooks」；改源须移除市场重加；更新须完整重启 ZCode
- 事故红线三条：用户未答复=冻结 / 转达必标来源 / 追认≠预授权

## 工具链事实

- Godot 4.7.2 在 PATH；gdUnit4 直跑须大写 G + `--ignoreHeadlessMode`（addons 已保留；selfcheck/视觉冒烟/auto-play 等验证基建待新项目重建）
- 仓库：origin = https://github.com/ligoudan95/duanzao.git，main 分支，历史保留
