---
name: agent-bridge-emmc-flash
description: 当用户要求烧录 eMMC、刷写镜像到板上 eMMC 槽位、更新运行时镜像、验证 eMMC 启动、切换 A/B 槽位（boot_slot）、回退镜像版本，或在 AgentBridge 连接的板上执行 update-emmc-flash、update-uboot、update-uboot-env、对 /dev/disk/by-partlabel dd 时使用：提供三态判读（NFS/eMMC/U-Boot 决定能写什么）、安全写入规则、长命令后台轮询模式、重启拦停与 netboot 回路、烧录后验证清单与排障。连接与收发机制见 agent-bridge-connection。
metadata:
  author: ziqiang.zhu
  version: 1.0.0
---

# agent-bridge-emmc-flash：板上 eMMC 烧录与真机验证

## 概述

- 前提：AgentBridge 已连接（见 agent-bridge-connection）；Camphora 工作区可用（镜像与烧录脚本随 `make install` 产出，板端脚本在 `/usr/sbin/update-*`，镜像在 `/images`）；
- 本 skill 覆盖：三态判读、安全写入规则、增量刷写（dd 单槽）、全量烧录（`update-emmc-flash`）、A/B 切换与回退、验证清单、排障；
- 方案与原理在 bsp 域文档：《EMMC 烧录》（操作口径）、《emmc 存储管理》（分区设计与让渡）、《合成 EMMC 烧录文件》（整盘合成）、《BOOT 流程》（引导链与命令）——本 skill 只负责「Agent 该怎么操作」；
- NFS 根的快速软件迭代（部分安装 + 服务重启）走 running-test，与本 skill 互补：eMMC 相关改动才走本流程。

## 三态判读（先判态，再动手）

接入后先发一个回车读 1–2 秒（方法见 agent-bridge-connection 的判态节），按下表决定能做什么—— **状态决定 eMMC 的可写性** ：

| 状态 | 识别特征 | eMMC 可写性 | 典型下一步 |
|---|---|---|---|
| NFS 运行态 | `cat /proc/cmdline` 含 `root=/dev/nfs` | **整盘空闲**，任意槽与引导区可写 | 直接 dd / `update-emmc-flash` |
| eMMC 运行态 | cmdline 含 `root=PARTLABEL=rootfs-<槽>` | 整盘与 **运行槽不可写**；另一槽可写 | 刷引导组件或全量 → 先回 NFS |
| U-Boot 提示符 | `=> ` | 不可（板端 Linux 工具不可用） | `run netboot` 回 NFS，或 `setenv boot_slot=…; saveenv` 切槽 |

## 安全写入规则

- **绝不写正在运行的槽位**：eMMC 态下 rootfs-a 是挂载中的 squashfs 的 backing device，覆写属未定义行为；要换它就写另一槽再 `boot_slot` 切换；
- **警惕 /images 里的陈旧文件**：NFS 根的 `/images` 由宿主手工拷入，可能落后于板上已修复的版本——用它刷 U-Boot/env 会 **回灌已修复的缺陷**（实例：usdhc1 误禁用的 U-Boot 曾被旧镜像回灌，复发 U016）。刷引导组件前核对宿主 `out/sysroot/images/` 的构建时间与 `.binary` 产物一致，必要时先 `make install` 再拷贝；
- **增量优先**：日常迭代只 dd 变更的镜像槽，不动 env 与 U-Boot（回灌面最小）；全量刷（含引导组件）才走 `update-emmc-flash --yes`；
- 每次写入后读回校验是固定动作（脚本内置；手工 dd 用 `head -c $(wc -c < img) <dev> | cmp - img`）。

## 长命令：后台 + 日志轮询（固定模式）

term 脚本的单次问答窗口约 20 秒；dd 一个 86 MiB 的 rootfs、`update-emmc-flash` 全量（数分钟）都会超窗。 **不要同步硬等** ，按模板后台执行、轮询日志：

```bash
# 启动（一条 term 命令内完成）
rm -f /tmp/job.log; (sh -c '
  for t in rootfs sdk app; do
    dd if=/images/$t.img of=/dev/disk/by-partlabel/$t-a bs=4M conv=fsync 2>>/tmp/job.log \
      && echo $t-dd-done >>/tmp/job.log
    head -c $(wc -c < /images/$t.img) /dev/disk/by-partlabel/$t-a | cmp -s - /images/$t.img \
      && echo $t-cmp-OK >>/tmp/job.log || echo $t-cmp-FAIL >>/tmp/job.log
  done; echo ALLDONE >>/tmp/job.log') >/dev/null 2>&1 & echo launched

# 轮询（每隔 30–45 秒一条 term 命令）
cat /tmp/job.log
```

`update-emmc-flash --yes` 同法：`(update-emmc-flash --yes > /tmp/flash.log 2>&1; echo rc=$? >> /tmp/flash.log) &`，读到 `done.` / `rc=0` 为止。

## 文件传输：分块 base64

串口交互 shell 的行编辑器限长约 1 KiB，超长命令被截断（现象：命令行中段折断、出现续行提示、执行不完整）。向板上传文件用分块 base64（ technique 细节亦见 agent-bridge-connection 的文件传输节）：

1. 宿主：`base64 -w0 <文件> > /tmp/x.b64`，按 **600 字符** 分块；
2. 逐块 `printf '%s' '<块>' >> /tmp/x.b64`（每块一条 term 命令）；
3. 板上：`base64 -d /tmp/x.b64 > <目标>`，`chmod +x`，`sha1sum` 与宿主 `base64 -d /tmp/x.b64 | sha1sum` 对比。

**热修通道** ：`/run` 是 tmpfs，生成器类脚本放 `/run/systemd/system-generators/<名>`（该目录在 systemd 生成器搜索路径内）后 `systemctl daemon-reload` 即时生效——不重刷即可验证修复；验证通过再把修复落到源码重建重刷。

## 重启、拦停与运行态回路

- **eMMC/NFS → U-Boot**：`bash .agents/skills/agent-bridge-connection/scripts/catch-uboot.sh <桥IP>`（判态 → 重启 → bootdelay 窗口拦停）；
- **U-Boot → NFS**：`run netboot`，等 75–90 秒；到达后 `cat /proc/cmdline` 确认 `root=/dev/nfs`；
- **重启验证**：`systemctl reboot`（勿用裸 `reset`）；轮询 `cat /proc/cmdline` 判定到达目标态——eMMC 最小根数十秒，NFS 全量 60–90 秒。

## 烧录/切换后验证清单

1. `cat /proc/cmdline`——`root=PARTLABEL=rootfs-<槽>` 与 `gpt` 参数在位（缺 `gpt` 则分区枚举整体失败）；
2. `mount | grep squashfs`——根 ro + `/usr/local`（p4）与 `/system`（p6）两笔 payload 挂载；
3. `systemctl is-active usr-local.mount system.mount graphical.target camphora-shell`——全 active；
4. `mmc part`——九分区枚举正常；
5. 画面：agent-bridge-screenshot（网络配置落地后 eMMC 根 `eth0` 启动即得 DHCP 地址，NFS 挂宿主目录作落盘路径即可；networkd 未启用的旧镜像才需手工配址）。

## 排障

| 现象 | 根因与处置 |
|---|---|
| 生成器/服务日志记 "succeeded" 但毫无效果 | systemd 以精简环境调生成器，PATH 不含 busybox applet 目录（板上报 `cat: not found`）——生成器脚本内 **不得经 PATH 解析外部命令**：`read` 读 /proc/cmdline、外部命令钉死绝对路径（/bin/mkdir、/bin/ln）。定位手段：分块 base64 放追踪副本到 /run 生成器目录 + daemon-reload |
| sfdisk 后分区设备未出现 | 等 `udevadm settle`；总控已内置 |
| ping 宿主不通但 NFS 挂载成功 | 宿主对 ICMP 不响应， **以挂载成功为准** ，不要因 ping 误判网络 |
| 网卡名不对 | U009 已以 `.link` 钉名结案：主口恒 `eth0`（次口 `eth1`）；仅在未含钉名文件的旧镜像上才会见 `end1`/`end0` |
| cmp 校验 FAIL | 先查 `/images` 文件新旧（wc -c 尺寸对宿主）与目标槽位拼写 |
| 命令执行不完整/出现续行提示 | 串口行编辑器限长，见上「文件传输：分块 base64」 |
| 板上卡在 netboot 回不来 | eMMC 态 env 的 bootcmd 含 netboot 自动回落；拦停进 U-Boot 后 `run mmcboot` 可强制走 eMMC |

## 注意事项

- `update-uboot-env` 无参默认写生产形态 `uboot_env_mmc`；开发/救援形态需显式 `/images/uboot_env`；
- 升级旧板（非冗余 U-Boot）补冗余体系：**先 `update-uboot` 后 `update-uboot-env`**（旧 U-Boot 读不了带 flag 字节的 env）；
- A/B 切换三步：`setenv boot_slot=b; saveenv; reset`，以 `/proc/cmdline` 实证；回退即切回；
- 抓屏、串口连接、NFS 根重装分别见 agent-bridge-screenshot、agent-bridge-connection、agent-bridge-nfs-reinstall。
