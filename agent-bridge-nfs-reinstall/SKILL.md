---
name: agent-bridge-nfs-reinstall
description: 当目标板从 NFS root（宿主机 tftp 目录）启动、且需要删除或整体重装该目录时使用：先重启平台并在 autoboot 倒计时内停在 U-Boot，宿主机按日期+时间改名备份旧 sysroot 后以普通用户执行 make nfs，再用 run netboot 重新引导。增量重部署（make install 覆盖）不走本流程，见文内边界说明。
metadata:
  author: ziqiang.zhu
  version: 1.5.0
---

# NFS root 重装流程（先停 U-Boot，再动服务端）

## 为什么必须先停 U-Boot

板子正从 NFS root 运行时，宿主机上一旦删除该目录，板上**所有文件句柄立即失效**（ESTALE / `Stale file handle`）：shell 无法执行任何外部命令——包括 `reboot`，连 `echo b > /proc/sysrq-trigger` 都因路径解析失败而无法写入，只能断电恢复。

正确顺序：先把板子停在 U-Boot 提示符（此状态完全不依赖 NFS），再删装服务端目录，最后 `run netboot` 引导。

## 适用边界

- **必须走本流程**：整体重装 NFS root（`make nfs`）、安装前缀全清（陈旧文件清理）、组件结构大调整；
- **不必停机**：增量重部署（`make install INSTALL_PREFIX=<tftp>/sysroot` 覆盖同名文件、追加镜像）可在板运行时直接进行，完成后 `reboot` 验证即可——但此时板上正在执行的二进制处于新旧混合状态，验证前务必重启一次。注意板子运行过之后目录里有 root 属主的 `/root`、`/etc/credstore*`、`/run`，普通用户改不动它们，覆盖安装可能中途失败，稳妥做法也走本流程的改名备份；
- 备份目录（`sysroot.bak.*`）累积后统一清理时才需要 `sudo`，日常重装全程普通用户。

## 流程（四步）

1. **重启平台**：板端 shell 执行 `systemctl reboot`（init 是 systemd，`reboot` 未必能直接执行）；
2. **打断 autoboot**：U-Boot 倒计时（以板端 `bootdelay` 为准，可用 `printenv bootdelay` 查询；本平台已调到 **1 秒**）内发送任意字符，停在 `=>`。窗口很短，可靠做法是**在同一个 TCP 连接里**先起一个后台按键循环、再发重启命令，让回车在倒计时期间持续到达（见下方「命令序列」）；
3. **备份旧目录并重装**：板子停在 U-Boot 期间，先按**日期+时间**改名备份旧目录，再以**普通用户**执行 `make nfs`：
   ```bash
   cd <workspace>
   mv <tftp>/sysroot <tftp>/sysroot.bak.$(date +%Y%m%d-%H%M%S)
   make nfs NFS_INSTALL_PREFIX=<tftp>/sysroot
   ```
   改名备份是免 root 的关键：`mv` 只要求父目录（`<tftp>`）可写，目录内有 root 属主条目也能整体挪走；改名后 `make nfs` 内置的擦除对不存在的目录是静默空操作（实测 exit 0），全新安装的文件全部是当前用户属主。**允许保留多个备份**（时间戳区分），累积太多时用 `sudo rm -rf <tftp>/sysroot.bak.*` 统一清理——备份里的 root 属主条目只有这一步需要提权；
4. **重新引导**：U-Boot 下执行 `run netboot`，按既定环境变量从 tftp 取 zImage/dtb 并以 nfsroot 挂根。

## 命令序列

第 1、2 步是时序联动，**优先直接用 agent-bridge-connection 附带的拦停脚本**（先判态再动作：板子已在 U-Boot 则原样返回；在 shell 才发重启；回车间隔 100ms、拦到 `=>` 立即停手；systemd 停服务/倒计时/到提示符逐态实时上报，全程可观察）：

```bash
bash .agents/skills/agent-bridge-connection/scripts/catch-uboot.sh <宿主机IP>
# 退出码 0 = 已停在 U-Boot；2 = 板子不在已知 shell（脚本拒绝盲目重启，需人工处理）
```

跨主机时传宿主机 IP（定位方法见 agent-bridge-connection 的「跨主机访问」快速路径）。手写等价序列时遵守该 skill「事件式等待」的四条纪律——尤其注意：连发间隔用 100ms（`bootdelay=1` 足够，20ms 只会刷屏）、匹配「独占一行」的 `=>` 立即 break、循环内对输出做状态上报。板子已跑过一轮而无人在盯时，注意 kernel 起来后按键会打到 getty，属无害噪声。

> 事件式写法（监听 `Hit any key to stop autoboot` 后精确按键）见 agent-bridge-embedded-uboot 的「修改 bootdelay 并重启后停留在 U-Boot」。

第 4 步 `run netboot` 后内核接管、输出超出 term 脚本约 20 秒的读循环上限，抓启动日志用长循环——**读到登录提示符即收尾**，固定时长只作兜底：

```bash
HOST=127.0.0.1; DUR=120
exec 3<>/dev/tcp/$HOST/2000 || exit 1
printf 'run netboot\r' >&3
out=""; END=$((SECONDS+DUR))
while [ $SECONDS -lt $END ]; do
    out+=$(timeout 1 dd bs=512 count=32 <&3 2>/dev/null | tr -d '\r')
    printf '%s' "$out" | grep -q 'root@' && break   # 登录提示符出现即收尾
done
exec 3<&-
printf '%s\n' "$out" | tail -20
```

dd 的读取参数用 `bs=512` 配 `count`（`bs=1` 是逐字节系统调用，日志刷屏时吞吐不足、读取滞后于设备输出）；过程观察与状态上报的纪律见 agent-bridge-connection 的「事件式等待」。

## 并行编排：让子代理等待板子

流程中的长等待段（重启后等引导完成、 ``run netboot`` 后等登录提示、部分安装后的整机重启） **不必让主代理原地阻塞** ：派一个 **后台子代理** 专职等待板子就绪，主代理并行继续其他工作（写代码/文档/构建其他目标），子代理完成时主代理会收到通知再回来做板端验证。

- **做法** ：以 ``run_in_background`` 派 general-purpose 子代理，提示词 **自包含** （主代理不留上下文）：桥主机 IP、等待脚本（ ``term-host.sh`` 循环轮询，见下）、就绪标记（ ``root@Camphora`` 登录提示符）、超时上限与回报要求（成功/超时 + 最后输出）；
- **串口独占（硬约束）** ：AgentBridge 共享同一条串口数据流——子代理等待期间主代理 **不得再开第二条串口连接** 做任何板端操作（并发读取会互相抢字节、命令互相穿插）；等待期内涉及板子的其他事务一并委托给该子代理；
- **职责边界** ：子代理只判定"板子就绪"（提示符出现）， **业务验证仍由主代理执行** ；
- 同样的等待段也出现在 running-test 的快速回路里（部分安装后整机重启取新内核/设备树），编排方式相同。

子代理提示词模板：

```text
通过 bash .agents/skills/agent-bridge-connection/scripts/term-host.sh <桥主机IP>
循环轮询板子串口（每次 sleep 3-5s），直到输出出现登录提示符 "root@Camphora"
（或最长 <N> 秒超时）。不要向板子发送任何命令，只读。回报：就绪与否 + 最后
10 行输出。工具与机制详见 .agents/skills/agent-bridge-connection/SKILL.md。
```

## 注意

- 打断 autoboot 后**不要**再连发回车以外的字符，避免误触发 U-Boot 命令回显；
- `run netboot` 依赖 U-Boot 环境变量（serverip、nfsroot、image、fdt_file 等）；若环境镜像与实网不一致（如 ipaddr 不符），先按 agent-bridge-embedded-uboot 的环境变量章节核对；
- 引导失败停在 U-Boot 时，用 `printenv` 核对 `bootcmd` 与相关变量，不要盲目重试。
