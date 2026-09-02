---
name: agent-bridge-embedded-uboot
description: 当 AgentBridge 已连接的目标处于 U-Boot 引导终端（未启动内核）时，提供常用 U-Boot 操作命令：环境变量、内存读写、存储分区、网络启动、镜像烧写、启动内核等。连接与收发机制见 agent-bridge-connection。
metadata:
  author: ziqiang.zhu
  version: 1.0.0
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

## 注意事项

- 当建立连接成功，但是无输入输出时，可以发送换行符 `\r` 让设备回显 shell 提示符，确认已进入 Linux shell；
- 可通过终端提示符简单判断当前终端时 Linux shell 还是 U-Boot：Linux shell 通常以 `$` 或 `#` 结尾，一般包含登录用户名与主机名，U-Boot 以 `=>` 结尾；
- **U-Boot 不是 Linux shell**：没有 `/proc`、`lsusb`、`dmesg` 等 Linux 命令；命令是 U-Boot 内建命令（可用 `help` 列出）；
- 命令以 `\r` 结尾（`term.sh` 已处理）；
- **环境变量改动需 `saveenv` 才持久化**，否则断电丢失，临时测试不要将环境变量持久化存储；
- **危险操作谨慎**：`erase`/`write`（nand/nor/sf）会破坏存储内容，执行前向用户确认；
- `boot`/`bootm` 会启动内核并脱离 U-Boot，之后应改用 `agent-bridge-embedded-linux`；
- 输出字符流已由 AgentBridge 剥离 ANSI 转义序列。
