---
name: agent-bridge-connection
description: 通过 Serial Port Terminal 插件的 AgentBridge（本地 TCP 端口）连接嵌入式设备的串口终端，建立通信、执行命令并读取输出。当需要与串口设备建立 AgentBridge 连接、了解命令收发/排错机制时使用。
metadata:
  author: ziqiang.zhu
  version: 1.1.0
---

# AgentBridge 连接（基础）

## 概述

本 skill 是 **AgentBridge 的连接基础**：教 AI 如何通过本地 TCP 端口连接嵌入式设备的串口终端，执行命令并读取输出。它只负责「连得上、发得出、收得到」。

AgentBridge 由 VS Code 插件 **Serial Port Terminal** 提供，插件内置三个共享同一份串口数据流的组件：

- **Terminal（终端）**：用户在 VS Code 中直接与设备交互的窗口。
- **LogRecorder（日志记录器）**：记录所有输入输出，便于回溯。
- **AgentBridge（代理桥）**：把串口终端桥接到本地 TCP 端口（默认 `2000`），为 AI Agent 提供交互接口。

```
        Terminal（VS Code 终端）←→ 用户
        ↕（共享同一数据流）
设备 ←→ 串口 ←→ AgentBridge（TCP :2000）←→ AI Agent（本 skill）
        ↕
        LogRecorder（记录所有交互）←→ 文件系统
```

**安全协作**：AI Agent 收发的是纯文本命令与输出，但**不应**代输敏感信息（密码、密钥）。需要时提示用户在 Terminal 中手动输入，避免敏感数据进入 AI 上下文。

## 前置条件

1. 已安装 VS Code 插件 **Serial Port Terminal** 并连接串口设备；
2. 插件的 **AgentBridge** 已启动，默认端口 `2000`；
3. 设备已通过串口连接并上电。

> 若 TCP 连接返回 `Connection refused`，说明 AgentBridge 未启动——**提示用户开启**，不要误判设备离线。

## 访问方法

**先选对脚本**：Linux/macOS 的 bash 支持 `/dev/tcp`，可直接用 `term.sh`；Windows 的 Gow/Git Bash 通常**不支持** `/dev/tcp`（`term.sh` 会以退出码 1 静默失败），请改用 `term.js`。

### 方法一：term.sh（Linux/macOS 或支持 /dev/tcp 的 bash）

```bash
bash .agents/skills/agent-bridge-connection/scripts/term.sh 'echo __MARK_BEGIN__; <命令>; echo __MARK_END__'
```

脚本会向 `127.0.0.1:2000` 发送命令（自动加 `\r`），持续读取输出直到遇到独占一行的 `__MARK_END__`。

### 方法二：term.js（Windows，推荐；需本机 Node.js）

```bash
node .agents/skills/agent-bridge-connection/scripts/term.js '<命令>'
```

`term.js` 会自动用 `__MARK_BEGIN__`/`__MARK_END__` 包住命令、自动加 `\r`，先排空残留输出，读到「独占一行的 `__MARK_END__`」后停止。用 `node -v` 确认 Node.js 可用。

### 方法三：手动 TCP 连接（备用）

```bash
exec 3<>/dev/tcp/127.0.0.1/2000 || exit 1
sleep 1
timeout 0.3 dd bs=4096 count=1 <&3 >/dev/null 2>&1   # 排空残留 banner
printf '%s\r' "$1" >&3                               # 命令必须以 \r 结尾
out=""
for i in $(seq 1 40); do
  chunk=$(timeout 0.5 dd bs=4096 count=1 <&3 2>/dev/null)
  out+="$chunk"
  [[ "$out" == *$'\n'"__MARK_END__"* || "$out" == *$'\r'"__MARK_END__"* ]] && break
done
printf '%s\n' "$out"
exec 3<&-
```

### 方法四

若前几种都不可用，可自行尝试其它可行方案（务必遵守下方注意事项，尤其是「标记回显」陷阱）。

## 关键注意事项

1. **禁止 HTTP 客户端**：不要用 `curl`/`wget` 访问该端口，其请求行会被设备当作命令执行。
2. **用 dd + timeout 读输出**：避免用管道（`head -c`、`cat`）读取，管道缓冲会吞数据。
3. **每条命令以 `\r` 结尾**（随附脚本已处理）。
4. **超时与截断**：读取循环最多 40×0.5s = 20s，长输出建议拆分命令。
5. **异步等待**：执行异步命令时，需要预设等待时长，确保读取所有输出。
6. **连接被拒绝**：立即提示用户开启 AgentBridge，等待反馈，不要自行重试或判定设备离线。
7. **敏感输入**：出现 `login:`/密码提示时，让用户在 VS Code Terminal 手动输入，不要经 TCP 代输。
8. **设备环境**：目标板通常无 Python，用纯 Bash。
9. **字符流已去 ANSI**：AgentBridge 转发给客户端的字符流已剥离 ANSI 转义序列，输出中通常没有颜色码/控制序列，无需 `cat -v` 处理。
10. **标记回显陷阱**：U-Boot 会回显整条命令行，因此命令行里的 `echo __MARK_END__` 会让 `__MARK_END__` 在命令真正执行前就出现在输出里。检测结束标记时**必须匹配「独占一行的 `__MARK_END__`」**（即其前面是 `\n` 或 `\r`），不要用简单的子串 `includes`/`== *"__MARK_END__"*`，否则会提前结束读取、只拿到半截输出。

## 通用执行模式

1. 构造带标记的命令：`echo __MARK_BEGIN__; <命令>; echo __MARK_END__`；
2. 用 `term.sh`（Linux）或 `term.js`（Windows）执行，从输出中截取两个标记之间的内容；
3. **结束标记必须按「独占一行」匹配**（见注意事项第 10 条），否则在回显命令行的终端（如 U-Boot）上会提前结束；
4. 输出为空或不完整时，参考下方故障排查。

## 故障排查

| 问题 | 可能原因 | 解决方法 |
|-----|-----|-----|
| Connection refused | AgentBridge 未启动 / 端口错误 | 提示用户开启，确认端口 |
| `term.sh` 退出码 1、无输出 | Windows 的 Gow/Git Bash 不支持 `/dev/tcp` | 改用 `term.js` |
| 输出只到 `__MARK_BEGIN__` 就停止 | 结束标记被命令行回显提前触发 | 改为匹配「独占一行」的 `__MARK_END__`（term.js 已处理）|
| 无输出 / 不完整 | 超时或截断 | 增加循环次数或拆分命令 |
| 命令执行后卡死 | 未发 `\r` 或命令等待输入 | 确保 `\r` 结尾，避免交互式命令 |
| 出现登录提示 | 设备未自动登录 | 提示用户在 Terminal 手动登录 |
| 复位/重连后收到旧 boot 残留 | 上一次连接断开后设备仍在后台继续 boot | 先发 `\r` 确认是否停在提示符再操作 |
