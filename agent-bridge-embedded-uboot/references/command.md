# U-Boot 完整命令字典

> 本文档供 Agent 按需加载。U-Boot 是引导加载器，不是 Linux shell：命令由 `help` 列出，绝大多数以 `\r` 结尾（`term.sh` 已处理）。

## 1. 信息与环境 (Info & Environment)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `version` | 显示 U-Boot 版本与编译时间。 |
| `bdinfo` | 显示板级信息（内存起止、ethaddr、波特率等）。 |
| `printenv` | 打印全部环境变量。 |
| `printenv <name>` | 打印指定变量（如 `printenv bootargs`）。 |
| `setenv <name> <value>` | 设置变量（会话内有效）。 |
| `setenv <name>` | 删除变量（空值）。 |
| `saveenv` | 把环境变量写回存储，**断电后才不丢失**。 |
| `editenv <name>` | 交互式编辑（尽量避免，改用 setenv）。 |
| `help` | 列出所有命令；`help <cmd>` 查看单个命令用法。 |

## 2. 内存操作 (Memory)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `md <addr> [len]` | 十六进制查看内存（如 `md 0x40000000 0x100`）。 |
| `mw <addr> <val> [count]` | 写内存（按字）。 |
| `mh` / `mb` | 半字 / 字节读写（`mh.b` 字节显示）。 |
| `mm <addr>` | 交互式修改内存（尽量避免）。 |
| `cp <src> <dst> <count>` | 内存拷贝。 |

## 3. MMC / SD 存储 (MMC & SD)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `mmc list` | 列出检测到的 MMC/SD 控制器。 |
| `mmc dev [dev]` | 选择 / 查看当前 MMC 设备。 |
| `mmc part` | 打印当前 MMC 分区表。 |
| `mmc info` | 显示设备容量、规格。 |
| `ls mmc 0:1` / `ls mmc 0` | 列出分区 / 整盘目录。 |
| `fatls mmc 0:1` | 列出 FAT 分区目录。 |
| `ext4ls mmc 0:1` | 列出 ext4 分区目录。 |

## 4. NAND / NOR / SPI Flash

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `nand info` / `nand bad` | 查看 NAND 信息 / 坏块。 |
| `nand erase <off> <size>` | 擦除 NAND。**危险**：破坏数据，执行前确认。 |
| `nand write <addr> <off> <size>` | 写 NAND。 |
| `sf probe` | 探测 SPI NOR Flash。 |
| `sf erase <off> <size>` / `sf write <addr> <off> <size>` | 擦写 SPI NOR。**危险**。 |
| `flinfo` | 查看 NOR Flash 信息。 |

## 5. 文件加载与启动 (Load & Boot)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `load mmc 0:1 <addr> <file>` | 从 MMC 分区加载文件到内存（自动识别 fs）。 |
| `fatload mmc 0:1 <addr> <file>` | 从 FAT 分区加载。 |
| `ext4load mmc 0:1 <addr> <file>` | 从 ext4 分区加载。 |
| `tftp <addr> <file>` | 经 TFTP 加载（需先 `setenv serverip/ipaddr`）。 |
| `boot` | 按默认流程启动（跑 bootcmd）。 |
| `bootm <addr>` | 启动 Legacy uImage（含内核+initrd 头）。 |
| `bootz <addr>` | 启动 zImage。 |
| `booti <addr>` | 启动 arm64 Image。 |
| `go <addr>` | 跳转到裸地址执行（不经过 Linux 引导协议，谨慎）。 |

## 6. 网络 (Network)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `ping <ip>` | 测试网络连通（如 `ping 192.168.1.1`）。 |
| `dhcp` | 自动获取 IP。 |
| `setenv ipaddr <ip>` / `setenv serverip <ip>` | 设置板端 / 服务器 IP（配合 tftp）。 |

## 7. 其它 (Misc)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `reset` | 复位设备（回到上电引导）。 |
| `sleep <s>` | 延时若干秒（脚本中等待外设）。 |
| `echo <text>` | 回显文本（命令组合与标记）。 |
| `run <var>` | 执行环境变量里的命令串（如 `run bootcmd`）。 |

## 快捷组合技

```bash
# 一键查看板级信息与环境
echo __MARK_BEGIN__; version; bdinfo; printenv bootargs; echo __MARK_END__;

# 从 MMC 加载并启动 zImage（示例）
echo __MARK_BEGIN__; load mmc 0:1 0x40000000 zImage; bootz 0x40000000; echo __MARK_END__;
```
