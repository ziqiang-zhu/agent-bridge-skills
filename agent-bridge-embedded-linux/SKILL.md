---
name: agent-bridge-embedded-linux
description: 当 AgentBridge 已连接的目标是嵌入式 Linux 设备（已进入 shell）时，提供常用 Linux 诊断与操作命令：系统/内核、CPU、内存、存储、USB、网络、I2C/SPI、GPIO、进程等。连接与收发机制见 agent-bridge-connection。
metadata:
  author: ziqiang.zhu
  version: 1.0.0
---

# AgentBridge 嵌入式 Linux 操作

## 概述

本 skill 假设 **AgentBridge 已建立连接**，且目标设备已进入 **Linux shell**（如 BusyBox/ash 提示符）。它提供常用 Linux 诊断与操作命令，用于查询硬件信息、排查问题。

连接建立、命令收发、排错机制请先使用 `agent-bridge-connection`；本 skill 只负责「进 Linux 后该敲什么」。

## 前置条件

1. 已按 `agent-bridge-connection` 建立连接；
2. 设备已启动完成并进入 Linux shell（若停在 `=>` 的 U-Boot 提示符，改用 `agent-bridge-embedded-uboot`）；
3. 若出现 `login:`/密码提示，请用户在 VS Code Terminal 手动登录。

## 命令速查

| 目的 | 推荐命令 |
|-----|-----|
| 系统/内核 | `uname -a`、`cat /etc/os-release`、`busybox \| head -1` |
| CPU 信息 | `cat /proc/cpuinfo`（找 `Hardware` 字段）、`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq` |
| 内存状态 | `free`、`cat /proc/meminfo \| head -20` |
| 存储分区 | `cat /proc/mtd`、`cat /proc/partitions`、`df -h` |
| USB 设备 | `lsusb`、`ls -1 /sys/bus/usb/devices/` |
| 网络接口 | `ifconfig` 或 `ip a`、`ls /sys/class/net/` |
| 内核日志 | `dmesg \| tail -50` |
| 进程列表 | `ps aux` 或 `ps -ef`、`top -n 1` |

> 上表命令中出现的 `\|` 是 markdown 表格转义，实际命令中不需要加反斜杠。

## 按需加载完整命令字典

> 上述命令无法满足需求、或用户询问不熟悉的外设（I2C、SPI、GPIO、传感器等）时，读取同级目录 `references/command.md`，其中按外设分类收录了 50+ 条详细命令与解析要点。

## 示例：查询 USB 设备

用户：「查看当前连接的 USB 设备」

```bash
bash .agents/skills/agent-bridge-connection/scripts/term.sh 'echo __MARK_BEGIN__; lsusb; echo __MARK_END__'
```

从输出中截取两个标记之间的内容：非 `1d6b:0002` 的 VID:PID 即外接设备。

## 注意事项

- 当建立连接成功，但是无输入输出时，可以发送换行符 `\r` 让设备回显 shell 提示符，确认已进入 Linux shell；
- 可通过终端提示符简单判断当前终端时 Linux shell 还是 U-Boot：Linux shell 通常以 `$` 或 `#` 结尾，一般包含登录用户名与主机名，U-Boot 以 `=>` 结尾；
- 目标板通常为 **BusyBox** 环境：无 Python，命令集精简，`watch`/`strace`/`lsof` 可能不存在；
- 命令以 `\r` 结尾（`term.sh` 已处理）；
- 输出字符流已由 AgentBridge 剥离 ANSI 转义序列；
- 交互式命令（如 `top`、`vi`）不适合经 TCP 代跑，改用 `top -n 1` 等批处理形态。
- 若需在设备上创建并执行脚本，可先在本地写好脚本内容，使用 `echo -e` 通过 AgentBridge 写入设备上的 /tmp 位置，再赋予执行权限并执行。
