---
name: agent-bridge-screenshot
description: 当 AgentBridge 已连接嵌入式 Linux 目标板、需要查看屏幕显示内容时使用：用板上预装的 screenshot 工具抓取 framebuffer 为 BMP，再在宿主侧解析像素判断显示内容（颜色占比、关键元素），无需肉眼。适用于验证 UI 是否渲染、排查黑屏/花屏、确认图形应用的实际输出。
metadata:
  author: ziqiang.zhu
  version: 1.0.0
---

# agent-bridge-screenshot：目标板屏幕查看

## 前置条件

- 目标板已部署 `screenshot` 工具（`/usr/local/bin/screenshot`，见 system 仓库 `tools/screenshot`；缺它时见文末"应急替代"）；
- 串口链路可用（连接与收发机制见 agent-bridge-connection）；
- 宿主侧有 Python3（解析 BMP 用，板上无需 Python）。

## 基本流程（三步）

### 1. 板上抓屏（BMP 格式，落 NFS 可读路径）

```bash
bash .agents/skills/agent-bridge-connection/scripts/term-host.sh <板IP> \
  'echo M; LD_LIBRARY_PATH=/usr/local/qt6/lib /usr/local/bin/screenshot -f bmp -o /usr/data/screen.bmp; ls -l /usr/data/screen.bmp'
```

要点：

- 格式选 **bmp**（解析最简单；png 也可以但多一层 zlib）；
- 输出路径必须在**宿主可直接读**的位置：NFS root 的 `/usr/data/`（板上 tmpfs 的 `/tmp` 宿主看不到）；
- `LD_LIBRARY_PATH` 指向 Qt6 运行库（`/usr/local/qt6/lib`）——工具动态链接 QtCore。

### 2. 宿主侧解析（板上跑、宿主读，因为 NFS root 就是宿主目录）

```bash
python3 - <<'EOF'
import struct, collections
d = open('/home/ziqiang-zhu/linux/tftp/sysroot/usr/data/screen.bmp','rb').read()
off = struct.unpack('<I', d[10:14])[0]
w, h = struct.unpack('<ii', d[18:26])
stride = (w*3+3)&~3
cnt = collections.Counter()
for y in range(0, h, 4):                  # 隔行采样足够判性
    row = off + (h-1-y)*stride
    for x in range(0, w, 4):
        i = row + x*3
        cnt[(d[i], d[i+1], d[i+2])] += 1  # BGR
print('尺寸:', w, h)
print('top 颜色:', cnt.most_common(5))
EOF
```

### 3. 结论判读

- **全黑**（唯一颜色 `(0,0,0)` 占比约 100%）：没有任何窗口渲染——图形进程未运行、已崩溃，或窗口从未 `show`；
- **纯色单一**：某个窗口/背景在显示但内容元素（文字、按钮）未渲染，优先查字体（linuxfb 无字体时文字不画，见《Camphor Framework》手册）；
- **多颜色分布**：内容正常，按具体颜色对号（各应用的背景色是已知的，如 demo Page1 深蓝 `#182433`、Page2 深红 `#331824`）。

## 典型用法：验证"修复后画面是否变化"

修复渲染问题后，**前后各抓一张并逐字节比较**最可靠：

```bash
cmp /home/ziqiang-zhu/linux/tftp/sysroot/usr/data/a.bmp \
    /home/ziqiang-zhu/linux/tftp/sysroot/usr/data/b.bmp && echo 未变化
```

无变化说明修复未生效（或改的进程没在跑）——先查进程与二进制新旧（`md5sum` 对比宿主构建树与部署树），再看渲染。

## 注意

- 抓的是 **framebuffer 当前内容**：多进程同时写 fb 时拍到的是混合结果；验证某进程的输出前先停掉其他 fb 写入者（如 annotator 与图形 shell 会互相覆盖）；
- 截图动作本身不影响显示；
- 板端时间未同步时 `ls -l` 的文件时间可能是旧日期，以文件存在性为准；
- 排查黑屏时的固定三连：进程活着吗（`systemctl is-active`）→ 二进制/插件新旧（`md5sum`）→ fb 内容（本 skill）。

## 应急替代（screenshot 工具不可用时）

`dd if=/dev/fb0 of=/usr/data/screen.raw bs=2457600 count=1` 抓原始帧（1024×600×4 字节 BGRA），宿主侧按 `struct.unpack` 逐像素解析；仅查几何与 bpp 时 `cat /sys/class/graphics/fb0/virtual_size`、`bits_per_pixel`。
