---
name: agent-bridge-nfs-reinstall
description: 当目标板从 NFS root（宿主机 tftp 目录）启动、且需要删除或整体重装该目录时使用：先重启平台并在 autoboot 倒计时内停在 U-Boot，宿主机按日期+时间改名备份旧 sysroot 后以普通用户执行 make nfs，再用 run netboot 重新引导。增量重部署（make install 覆盖）不走本流程，见文内边界说明。
metadata:
  author: ziqiang.zhu
  version: 1.3.0
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

第 1、2 步是时序联动，`term.sh` 的一次性收发不适用，用原始连接边读边按键（同机用 `/dev/tcp`；跨主机把 `HOST` 换成宿主机 IP，见 agent-bridge-connection 的「跨主机访问」）。`bootdelay=1` 时「发重启命令 → 再按键」往往来不及，**后台按键循环要和重启命令同时挂着**：

```bash
HOST=127.0.0.1   # 跨主机：宿主机 IP
exec 3<>/dev/tcp/$HOST/2000 || exit 1
timeout 0.3 dd bs=4096 count=1 <&3 >/dev/null 2>&1   # 排空残留
( while :; do printf '\r' >&3; sleep 0.02; done ) &  # 持续送键：关机阶段打到控制台无害
SPAM=$!
printf 'systemctl reboot\r' >&3
out=""
for i in $(seq 1 600); do
    out+=$(timeout 0.15 dd bs=1 count=8192 <&3 2>/dev/null)
    [[ "$out" == *'=> '* ]] && break
done
kill $SPAM 2>/dev/null
exec 3<&-
echo "$out" | tr -d '\r' | tail -5   # 应停在 => 提示符
```

> 事件式写法（监听 `Hit any key to stop autoboot` 后精确按键）见 agent-bridge-embedded-uboot 的「修改 bootdelay 并重启后停留在 U-Boot」；上面的连续回车更简单，效果相同。板子已跑过一轮而无人在盯时，注意 kernel 起来后按键会打到 getty，属无害噪声。

第 4 步 `run netboot` 后内核接管、输出超出 term 脚本约 20 秒的读循环上限，抓完整启动日志用长循环：

```bash
HOST=127.0.0.1; DUR=120
exec 3<>/dev/tcp/$HOST/2000 || exit 1
printf 'run netboot\r' >&3
END=$((SECONDS+DUR))
while [ $SECONDS -lt $END ]; do
    timeout 1 dd bs=1 count=16384 <&3 2>/dev/null
done
exec 3<&-
```

## 注意

- 打断 autoboot 后**不要**再连发回车以外的字符，避免误触发 U-Boot 命令回显；
- `run netboot` 依赖 U-Boot 环境变量（serverip、nfsroot、image、fdt_file 等）；若环境镜像与实网不一致（如 ipaddr 不符），先按 agent-bridge-embedded-uboot 的环境变量章节核对；
- 引导失败停在 U-Boot 时，用 `printenv` 核对 `bootcmd` 与相关变量，不要盲目重试。
