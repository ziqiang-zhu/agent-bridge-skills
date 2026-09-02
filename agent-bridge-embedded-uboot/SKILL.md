---
name: agent-bridge-embedded-uboot
description: 当 AgentBridge 已连接的目标处于 U-Boot 引导终端（未启动内核）时，提供常用 U-Boot 操作命令：环境变量、内存读写、存储分区、网络启动、镜像烧写、启动内核等。连接与收发机制见 agent-bridge-connection。
metadata:
  author: ziqiang.zhu
  version: 1.1.0
---

# AgentBridge 嵌入式 U-Boot 操作

## 概述

本 skill 假设 **AgentBridge 已建立连接**，且目标设备停在 **U-Boot 引导终端**（提示符常为 `=>` 或 `U-Boot>`），内核尚未启动或启动被打断。它提供常用 U-Boot 命令，用于查看/修改环境变量、读写内存与存储、网络启动、烧写镜像、引导内核。

连接建立、命令收发、排错机制请先使用 `agent-bridge-connection`；本 skill 只负责「在 U-Boot 里该敲什么」。

## 前置条件

1. 已按 `agent-bridge-connection` 建立连接；
2. 设备停在 U-Boot 提示符（若已进入 Linux shell，改用 `agent-bridge-embedded-linux`）。

## 命令速查

| 目的 | 推荐命令 |
|-----|-----|
| 查看版本/板型 | `version`、`bdinfo` |
| 环境变量 | `printenv`、`printenv <name>`、`setenv <name> <value>`、`saveenv` |
| 内存读写 | `md <addr> [len]`、`mw <addr> <val> [len]`、`mm <addr>` |
| MMC/SD | `mmc list`、`mmc dev`、`mmc part`、`mmc info` |
| 分区/文件系统 | `ls mmc 0:1`、`fatls mmc 0:1`、`ext4ls mmc 0:1` |
| 加载镜像 | `load mmc 0:1 <addr> <file>`、`fatload mmc 0:1 <addr> <file>` |
| 网络 | `ping <ip>`、`dhcp`、`tftp <addr> <file>` |
| 启动内核 | `boot`、`bootm <addr>`、`bootz <addr>`、`booti <addr>` |
| 复位 | `reset` |

## 按需加载完整命令字典

> 需要更完整的 U-Boot 命令（NAND/NOR/SPI flash、环境变量详解、网络启动流程等）时，读取同级目录 `references/command.md`。

> 也可以在 U-Boot 提示符下执行 `help` 查看当前设备支持的命令列表。

## 示例：查看并修改启动参数

1. 查看当前环境变量：

```bash
bash .agents/skills/agent-bridge-connection/scripts/term.sh 'echo __MARK_BEGIN__; printenv bootargs; echo __MARK_END__'
```

2. 修改并保存：

```bash
bash .agents/skills/agent-bridge-connection/scripts/term.sh 'echo __MARK_BEGIN__; setenv bootargs console=ttyS0,115200 root=/dev/mmcblk0p2; saveenv; echo __MARK_END__'
```

> Windows 下把 `term.sh 'echo __MARK_BEGIN__; ...; echo __MARK_END__'` 换成 `node .agents/skills/agent-bridge-connection/scripts/term.js '...'`（term.js 自动加标记，无需手写 `echo`）。

## 实战：修改 bootdelay 并重启后停留在 U-Boot

场景：把 bootdelay 改为 5s、重启平台、并在自动启动倒计时内按任意键停在 U-Boot。

1. 查看当前值：

```bash
node .agents/skills/agent-bridge-connection/scripts/term.js 'printenv bootdelay'
```

2. 修改并持久化（必须 `saveenv`，否则断电丢失）：

```bash
node .agents/skills/agent-bridge-connection/scripts/term.js 'setenv bootdelay 5; saveenv'
```

3. 复位。复位后 AgentBridge 的 TCP 连接**不会断开**，输出继续经同一连接回传：

```bash
node .agents/skills/agent-bridge-connection/scripts/term.js 'reset'
```

4. 复位后回显里出现倒计时 `Hit any key to stop autoboot:  5  4  3  2  1  0`，在倒计时结束前发送任意键（如空格 `\x20`）即中断自动启动，停在 `=>`。

> 第 4 步需要「边读输出边按键」的联动：连接后监听输出，命中 `Hit any key to stop autoboot` 就写一个字符。`term.js` 是一次性命令、不适用此场景，需写带事件判断的小脚本（Node.js `net` 客户端，检测到该字符串后 `socket.write(' ')`）。

## 实战：获取设备信息

查询完整设备信息的最小命令组合：

```bash
node .agents/skills/agent-bridge-connection/scripts/term.js 'version'
node .agents/skills/agent-bridge-connection/scripts/term.js 'bdinfo'
node .agents/skills/agent-bridge-connection/scripts/term.js 'mmc list'
node .agents/skills/agent-bridge-connection/scripts/term.js 'mmc info'
node .agents/skills/agent-bridge-connection/scripts/term.js 'printenv'
```

各命令作用：

- `version`：U-Boot 版本、构建时间、工具链（gcc/ld 版本）；
- `bdinfo`：板级信息——DRAM 起止/大小、baudrate、MAC、IP、显示帧缓冲、lmb 内存布局等；
- `mmc list`：列出 SD/eMMC 控制器（如 `FSL_SDHC: 0`、`FSL_SDHC: 1 (eMMC)`）；
- `mmc info`：当前 MMC 设备详情（型号、MMC 版本、容量、总线宽度/速度等）；
- `printenv`：完整环境变量（`board_name`、`board_rev`、`serial#`、`ipaddr`、`bootcmd` 等）。

## 注意事项

- 当建立连接成功，但是无输入输出时，可以发送换行符 `\r` 让设备回显 shell 提示符，确认已进入 Linux shell；
- 可通过终端提示符简单判断当前终端时 Linux shell 还是 U-Boot：Linux shell 通常以 `$` 或 `#` 结尾，一般包含登录用户名与主机名，U-Boot 以 `=>` 结尾；
- **U-Boot 不是 Linux shell**：没有 `/proc`、`lsusb`、`dmesg` 等 Linux 命令；命令是 U-Boot 内建命令（可用 `help` 列出）；
- 命令以 `\r` 结尾（`term.sh`/`term.js` 已处理）；
- **环境变量改动需 `saveenv` 才持久化**，否则断电丢失，临时测试不要将环境变量持久化存储；
- **危险操作谨慎**：`erase`/`write`（nand/nor/sf）会破坏存储内容，执行前向用户确认；
- `boot`/`bootm` 会启动内核并脱离 U-Boot，之后应改用 `agent-bridge-embedded-linux`；
- 输出字符流已由 AgentBridge 剥离 ANSI 转义序列；
- `reset` 复位后 AgentBridge 的 TCP 连接**不会断开**，后续输出仍经同一连接回传，无需重连；
- 上一次连接超时/断开后，设备可能仍在后台继续 boot（如 TFTP 下载 zImage），下次连接应先发 `\r` 确认是否停在 `=>`，再执行 `reset` 等命令；否则命令可能被忽略或排队；
- 自动启动倒计时提示 `Hit any key to stop autoboot: 5 4 3 2 1 0`（数字为 bootdelay），期间任意键可中断并停在 U-Boot；
- U-Boot 会**回显命令行**：用结束标记判断输出完成时须按「独占一行」匹配（见 `agent-bridge-connection`）。
