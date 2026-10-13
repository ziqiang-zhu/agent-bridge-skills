---
name: running-test
description: 板上快速验证改动的高速迭代流程：小范围软件改动用 cmake --install 的 --component/--prefix 部分安装到 NFS 根，再经 AgentBridge 用 systemctl 重启对应服务即可看效果，跳过整体重装与整机重启；仅 boot/kernel/init 等必须整机重启的改动才重新部署 NFS sysroot。当用户要求部署刚改的代码到板子、快速验证修改效果、判断部分安装还是整体重装、或重启板上服务看效果时使用——即使用户只说"部署一下"、"上板看看"、"验证一下"。
metadata:
  author: ziqiang.zhu
  version: 1.0.0
---

# running-test：板上快速验证（部分安装 + 服务重启）

## 原则

整体重装 NFS 根 + 整机重启的验证回路要数分钟；绝大多数软件改动只需"换几个文件 + 重启一个服务"。 **默认走部分安装，整体重装留给真正需要的改动** 。

两个前提：

- `.binary` 构建树已配置（历史上 `make config` 过一次；没有则按 camphor-build 流程先做）；
- 板子在 **运行态** （systemctl 可用）。注意这与 nfs-reinstall 相反——那条流程要求先停在 U-Boot。

## 快速回路（默认路径）

1. **构建** ： ``cmake --build .binary -j6`` （并行度不超过 -j6；本环境直调 ``cmake`` 若报 ``unknown flag 'build'`` 是 snap 垫片拦截，改用 ``snap run cmake`` 或经 ``make`` 目标）；
2. **部分安装** ： ``cmake --install .binary --component <组件名> --prefix /home/ziqiang-zhu/linux/tftp/sysroot`` （NFS 根路径；组件名查法见下表）；
3. **重启对应服务** （经 AgentBridge，连接方法见 agent-bridge-connection）：
   ``systemctl restart camphor-shell`` ——用 ``systemctl restart <unit>`` ， **永远不要 reboot 整机** ；
4. **验证** ：看日志 ``journalctl -u camphor-shell -b --no-pager | tail`` ；看画面用 agent-bridge-screenshot（重启后等两三秒再抓帧）。

## 改动 → 组件 → 恢复动作对照表

| 改了什么 | 组件（--component） | 恢复动作 |
|-----|-----|-----|
| 应用插件（testing/launcher） | ``testing`` / ``launcher`` | ``systemctl restart camphor-shell`` |
| shell 本体（base/core） | ``camphor-shell`` | 同上 |
| framework / ui / platform 库 | ``camphor-framework`` / ``camphor-ui`` / ``camphor-platform`` | 同上（shell 与插件都链接它们，一次重启全生效） |
| systemd 单元定义 | ``systemd-units`` | ``systemctl daemon-reload`` ，再视单元 restart |
| os-release / platform.conf | ``os-release`` / ``platform-conf`` | 通常无需重启（新进程下次启动读到） |
| 文档站 | ``sphinx-docs`` | 无需重启，浏览器刷新即可 |
| 内核 / U-Boot / dtb / 镜像 | —（ ``images/`` 产物） | **必须整体重装** |
| init（busybox/systemd）/ glibc / 第三方库 | — | **必须整体重装** |

组件名来自各 ``CMakeLists.txt`` 的 ``install(... COMPONENT ...)`` 规则；找不到归属时 ``grep -rn "COMPONENT" <相关目录>`` 。一条 ``--install`` 只带一个 ``--component`` ，多组件就多执行几次。

## 陷阱（每条都实测踩过）

1. **U015 同秒跳装** ： ``cmake --install`` 对 **同 mtime 文件视为最新而跳过** ——快速连续构建+安装时刚改的产物可能被跳过，安装报成功、板上没变化。核验部署树文件的 mtime 是否刷新； **不能用 md5 判新旧** （共享库经安装期 RPATH 重链，字节必不同）。稳妥做法：先 ``rm`` 部署树里的目标文件再 install。
2. **部分安装只增不删** ：改名/删除的文件会留在部署树成为陈旧残留——手动 ``rm`` 或转整体重装。
3. **插件没有热加载** ：插件 ``.so`` 由 camphor-shell 启动时加载，换文件不重启就不生效；重启 camphor-shell 后屏幕黑一下再回桌面，属预期。
4. **root 属主摩擦** ：板子跑过的 NFS 根里有 root 属主条目（ ``/root`` 、 ``/run`` 、 ``etc/credstore*`` 等）。部分安装不碰它们，普通用户可执行；一旦需要 **擦目录/清理备份** 才需要提权或转流程。
5. **服务重启即验证态重置** ：重启 camphor-shell 会重置全部 UI 状态（返回栈、应用内状态），验证交互流程时从头操作。

## 何时必须整体重装

- boot/U-Boot、内核、设备树、镜像类改动；
- init 形态（busybox/systemd）、glibc、第三方库——它们是根文件系统基座，且多为运行中进程本身，无法热替换；
- 首次部署、部署树结构大改、陈旧文件批量清理（U005/U012 场景）。

整体重装走 agent-bridge-nfs-reinstall（先停 U-Boot 再动 NFS 根，全程普通用户）。

## 常用一条龙（camphor-shell 为例）

```bash
cd /home/ziqiang-zhu/linux/AgentWorkSpace
snap run cmake --build .binary -j6
snap run cmake --install .binary --component camphor-shell \
    --prefix /home/ziqiang-zhu/linux/tftp/sysroot
bash .agents/skills/agent-bridge-connection/scripts/term-host.sh <桥主机IP> \
    'systemctl restart camphor-shell; sleep 3; journalctl -u camphor-shell -b --no-pager | tail -5'
```
