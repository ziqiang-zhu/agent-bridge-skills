---
name: agent-bridge-skill-creater
description: 当用户要求「把设备操作 / <tool> --help 整理成 skill」「新建/补充 agent-bridge 相关 skill」，或在 AgentBridge 连接的设备上执行操作时发现该操作未被现有 skill 囊括（新工具、新领域、现有 skill 缺少某选项、实际行为与 skill 描述不符）时，用于引导用户把操作经验生成/更新为 agent-bridge-* 工具 skill。总结 skill 制作与维护经验：设备信息采集、与用户确认背景、SKILL.md 模板、命名规范、skill 集联动。禁止 AI 自行生成 skill——必须经用户要求或明确确认。
metadata:
  author: ziqiang.zhu
  version: 1.0.0
---

# AgentBridge Skill 创建指南（agent-bridge-skill-creater）

## 核心规则（务必先读）

1. **禁止自行生成 skill**：AI **不得**主动创建或修改 `.agents/skills/` 下的任何内容。只有两种情况下可以动手：
   - 用户**明确要求**（如「执行 X --help，整理成一份 skill」）；
   - AI 提示后，用户**明确确认**（如「好，生成吧」「可以」）。
2. **未被囊括的操作必须提醒并引导**：执行任务时，出现以下任一情况，应在合适的时机提醒用户，并主动建议把操作经验沉淀为 skill：
   - 用户要求的操作**没有任何 skill 覆盖**（新工具、新领域，如出现 `usb_control`/`logset` 之外的新控制工具）；
   - 现有 skill 只**部分覆盖**：实际用到的参数/选项/子命令不在 skill 中；
   - 命令的**实际行为与 skill 描述不符**（发现笔误、参数语义、副作用、崩溃等未记录的现象）。
3. **提醒话术示例**：「当前的 X 操作还没有 skill 覆盖（或 X skill 缺少 Y 选项）。我可以执行 `X --help`（必要时加几次实际命令），把输出整理成 skill 放到 `.agents/skills/` 下，之后这类操作就有章可循了。需要我生成吗？」——**得到明确确认后再动手**。
4. 提醒不阻塞任务：先完成用户当前要求的事，再在总结中提出 skill 建议。

## 适用场景

- 用户明确要求：「把 <tool> 的 help 整理成 skill」「新建一个 skill」「把这次的操作经验加进 skill」；
- AI 在 AgentBridge 设备上操作时发现上述「未被囊括」情况（见核心规则 2）。

> 通用 skill 写作规范可参考 `skill-creator` skill；本 skill 是 **agent-bridge 工具 skill 集**（`agent-bridge-usb-controller` 等 10 份）特有的制作与维护流程。

## 经验总结（既定工作流）

现有 agent-bridge 工具 skill（usb_control / device_control / volume_control / nw_control / classic_bt_test / aacmd / dumpsys AppleCarPlay / ver / logset）均按以下流程沉淀，可直接复用：

### 1. 设备上采集信息

- 按 `agent-bridge-connection` 执行 `<tool> --help`（Windows 用 `term.js`，Linux 用 `term.sh`）；
- **help 形式因工具而异**：多数工具支持 `--help`；`logset` 对任意非法参数输出 `error type!` + usage；`dumpsys AppleCarPlay` 直接执行（不带选项）即输出帮助——只要输出含参数列表即可整理；
- **help 之外必须记录实测观察**（这是 skill 最有价值的部分）：
  - 输出形态：是否混入日志行、是否重复输出、日志是否异步延迟（出现在提示符之后）；
  - 副作用：仅执行工具（哪怕 `--help`）是否触发服务初始化（如 `classic_bt_test`、`aacmd`）；
  - 稳定性：退出是否崩溃（如 `classic_bt_test` 的 Segmentation fault）；
  - 版本信息：client/server 版本是否一致（如 `aacmd --ver`）；
  - help 文本笔误：原文照录 + 标注（如 `VERSIION`、`useage`、`--set_opotions`）；
  - 工具若是脚本（如 `ver`），可 `cat` 脚本确认输出是构建时固化的静态文本。

### 2. 向用户确认背景信息

help 只有语法，以下信息**通常需要用户提供**，整理前先问清楚：

- 工具定位：哪个进程的测试工具？管理什么服务/能力？（如 `nw_control` 属于 `networkmanager`，`aacmd` 依赖 `aa_manager_service` + `aa_accessory_service`）
- 依赖进程名：故障排查用 `ps | grep <进程名>` 检查（如 `device_server`、`apple_carplay_server`）；
- 用户惯用的触发短语：「通过 X manager 操作」「通过 X 服务控制」等，写入 description 提升触发可靠性；
- 已知限制：如 `classic_bt_test` 输出与实际 API 可能对不上、不完全可用；
- 泛指歧义：如「device service」指 `device_server` 进程整体而非某个 manager，需写明路由规则。

### 3. 创建 skill

- 目录：`.agents/skills/agent-bridge-<name>/SKILL.md`（frontmatter `name` 与目录名一致）；
- 命名惯例：`agent-bridge-<工具名或领域>-<类型>`，如 `agent-bridge-usb-controller`、`agent-bridge-aacmd`、`agent-bridge-carplay-dump`、`agent-bridge-platform-version`、`agent-bridge-logset`；
- 结构模板见下节；
- 创建后确认该 skill 已出现在可用 skill 列表中（加载成功）。

### 4. skill 集联动（保持一致性）

- **同进程家族**：依赖同一进程的工具（usb/device/volume → `device_server`）各自加「与 <进程> 的关系」章节（服务 → 工具 → skill 对照表 + 按操作对象的路由规则），并说明进程外的工具区别（如 `networkmanager` 独立于 `device_server`）；
- **软件版本确认**：每份工具 skill 注意事项末尾统一加一条，引用 `agent-bridge-platform-version`（执行 `ver` 查看平台版本）；
- **注册联动清单**：新 skill 加入 `agent-bridge-platform-version` 的「与其他 skill 的联动」章节清单；
- **触发短语不冲突**：新增触发短语时检查是否与其它 skill 重叠，泛指短语必须按操作对象拆分；
- **版本号管理**：新建 1.0.0；每次更新 +0.1（1.0.0 → 1.1.0 → 1.2.0）；重命名时同步改目录名 + frontmatter `name`，并全局搜索旧名清理引用。

## SKILL.md 模板

```markdown
---
name: agent-bridge-<name>
description: 当用户要求「通过 <X> manager 操作」「通过 <X> 服务控制」<触发短语>，或涉及 <能力关键词>，或需要在 AgentBridge 连接的嵌入式 Linux 设备上使用 <tool> 时，提供 <tool>（<依赖进程> 提供的 <服务> 的测试工具）的完整用法：<能力摘要>。命令无效时用 ps|grep <依赖进程> 排查进程。连接与收发机制见 agent-bridge-connection。
metadata:
  author: ziqiang.zhu
  version: 1.0.0
---

# AgentBridge <领域>（<tool>）

## 概述
- 前提（AgentBridge 已连接 + Linux shell + 工具存在）
- 工具定位：<依赖进程> 提供的 <服务> 的测试工具（帮助文本中称 "xxx"）
- 能力覆盖清单
- **适用场景**：触发短语
- （device_server 家族适用）与 device_server 的关系
- 连接与收发机制见 agent-bridge-connection；本 skill 只负责「<tool> 该敲什么」

## 前置条件
1. 已按 agent-bridge-connection 建立连接
2. 设备已进入 Linux shell
3. 工具存在（which <tool>）
4. <依赖进程> 已存活

## 命令速查（按用途分组，表格）

## 参数详解（位掩码 / 枚举值 / 键值表）

## 示例（term.js 调用；敏感参数用占位符并提示用户手动输入）

## 故障排查：命令无效 / 无响应
1. ps | grep <依赖进程>（排除 grep 自身行）
2. 工具特有检查（服务是否 startup、参数顺序、版本核对等）

## 注意事项
- 工具特有坑（日志噪声 / 副作用 / 笔误 / 敏感参数 / 版本不一致）
- 命令以 \r 结尾（term.js/term.sh 已处理）；输出已剥离 ANSI
- 不确定选项含义时，在设备上执行 <tool> --help（或等价帮助命令）
- **软件版本确认**：排障需要记录/对比版本时执行 ver，见 agent-bridge-platform-version
```

## 更新流程（用户纠正 / 新发现）

1. 定位要改的章节（frontmatter description / 概述 / 速查表 / 注意事项）；
2. 修改内容，必要时补充实测依据；
3. metadata `version` +0.1；
4. 涉及命名/定位变化的，同步更新：目录名、frontmatter `name`、其它 skill 中的引用、`agent-bridge-platform-version` 的联动清单。

## 注意事项

- **再次强调**：未经用户要求或确认，禁止生成/修改任何 skill；提醒时只「建议 + 询问」，不直接动手；
- 敏感信息**不得写入 skill**：真实 WiFi 密码、证书、密钥等一律用占位符（如 `<密码>`），并在 skill 中注明「禁止经 TCP 代输，用户手动输入」；
- 不确定的语义（help 未展开的参数、笔误处的真实含义）标注「实机验证后再使用」，不臆断；
- skill 面向「下次执行该操作的 AI」，写作时保持自包含：不依赖本次会话上下文。
