---
name: camphora-build
description: Camphora 工作区的编译构建流程。当用户要求编译、构建项目、配置（menuconfig/defconfig）、构建或安装 sysroot、生成文档站（sphinx-docs）时使用本技能。提供 Makefile+Kconfig 驱动的完整命令序列，每步均含可直接执行的完整命令。
metadata:
	author: ziqiang.zhu
	version: 1.11.0
---

# Camphora 编译构建流程

本工作区（Camphora BSP，i.MX6ULL ALPHA V2.2）的构建由顶层 **Makefile**
（repo 从 `build/Makefile.top` 拷贝）驱动：**Kconfig 管配置，CMake 管构建**。
构建目录为 `.binary/`。

## 前置条件

- 主机工具：`make`、`python3`（含 curses）、`cmake`（≥4.2）、`meson`、`ninja`；
  文档构建额外需要 `sphinx-build` 与 furo
- 交叉工具链已内置在 `bsp/toolchains/`，无需设置任何环境变量
- 并行度默认 `-j6`

## 标准流程

```bash
cd /home/ziqiang-zhu/linux/AgentWorkSpace
make imx6ull_alientek_alpha_v2.2_defconfig   # 载入平台预设（先 distclean 清空构建树）并自动完成两阶段配置
make all                                      # 全量构建 + 安装
```

kconfig 类目标（`make menuconfig`、`make <board>_defconfig` 等）只写 `.config`，不触发任何
Cmake 动作；`.config` 变更后下一次 `make build`/`make all`/`make config` 会先删基础 sysroot
与第三方步骤戳记、重跑两阶段（第三方全量重配重编，预编译包代价小）；`make sysroot`
与 `make config` 是两个阶段的 PHONY 手动入口；内核/U-Boot defconfig 的应用在 `make build`
的构建图内按需发生（defconfig 变更才重新应用，内容未变只刷戳记不重配），无独立入口。
载入板级预设会清空构建树（含第三方构建产物），触发一次全量重建，属预期行为。

## Agent 执行环境注意

在 Agent 的 Bash 工具中，直接子进程的 `argv[0]` 会被包装替换，会导致：

- 顶层 make 的 `$(MAKE)` 指向应用自身可执行文件，内部递归 `make config` 的
  目标（`%_defconfig`、`menuconfig`、`guiconfig`）会去启动该程序而非 make；
- snap 安装的 cmake 拿不到程序名，表现为 `cmake --version` 打印 snap 版本、
  `cmake -E ...` 报 unknown flag。
- Bash 工具是持久 shell，cwd 跨调用保留：每条命令以
  `cd /home/ziqiang-zhu/linux/AgentWorkSpace &&` 开头或用绝对路径——cwd 残留在
  子仓或已删目录时，相对路径与技能发现会失效（详见 agent-work-agreement 的
  「工作目录纪律」）。

执行时加两个覆盖参数即可（用户在真实终端不需要）：

```bash
make MAKE=/usr/bin/make CMAKE="snap run cmake" imx6ull_alientek_alpha_v2.2_defconfig
make MAKE=/usr/bin/make CMAKE="snap run cmake" all
```

## 各目标

```bash
make list              # 列出板级配置及编号（make <编号> 等价于 make <board>_defconfig）
make help              # 打印所有目标与可覆盖变量
make menuconfig        # 交互式配置（Kconfiglib）
make sysroot           # 阶段一：填基础 sysroot（libc、C++ 运行时、第三方软件）
make config            # 阶段二：设 CMAKE_SYSROOT 的二次配置
make build             # 构建（.config 较新时自动先失效重跑两阶段；内核/U-Boot defconfig 按需应用）
make install           # 构建 + 安装到 out/sysroot（镜像在 images/）
make nfs               # 擦除 NFS 根后用同一个 cmake --install 装进去（须给 NFS_INSTALL_PREFIX，擦除要 sudo）
make docs              # 单独构建文档站（sphinx-docs 已入默认构建）
make savedefconfigs    # 重新生成内核/U-Boot defconfig（构建树内生成 + 打印路径，需人工核对）
make clean             # 删除 .binary（保留 .config）
make distclean         # 删除 .binary 与 .config
```

clean（保留 .config）后直接 `make all` 会自动重配再构建；distclean（连 .config 一起删）后
`make all` 会以 "Run 'make menuconfig' ..." 报错停下。

## 更新板级 defconfig（内核 / U-Boot）

**用 `make savedefconfigs` 生成**：它在构建树内重新生成内核与 U-Boot 的最小 defconfig，
并打印产物路径与源码树目标路径。该目标只负责生成与提示，**不自动校验、不自动写回**；
拷贝前后请按下面的命令人工回灌核对。

```bash
cd /home/ziqiang-zhu/linux/AgentWorkSpace
make savedefconfigs
# Defconfig artifacts (check and copy them back by hand):
#   kernel: .binary/bsp/kernel/defconfig
#           -> bsp/source/kernel/arch/arm/configs/imx6ull_alientek_ALPHA_V2.2_defconfig
#   uboot:  .binary/bsp/uboot/defconfig
#           -> bsp/source/uboot/configs/mx6ull_14x14_evk_emmc_alientek_alpha_v2.2_defconfig
```

人工回灌核对（拷贝后在临时构建树里加载，与当前 `.config` 逐字节比对）：

```bash
TC=$PWD/bsp/toolchains/arm-gnu-toolchain-12.3.rel1-x86_64-arm-none-linux-gnueabihf/bin
cp .binary/bsp/kernel/defconfig \
   bsp/source/kernel/arch/arm/configs/imx6ull_alientek_ALPHA_V2.2_defconfig
rm -rf /tmp/kb-check && mkdir -p /tmp/kb-check
env PATH=$TC:$PATH make -C bsp/source/kernel O=/tmp/kb-check ARCH=arm \
  CROSS_COMPILE=arm-none-linux-gnueabihf- imx6ull_alientek_ALPHA_V2.2_defconfig
diff /tmp/kb-check/.config .binary/bsp/kernel/.config && echo "回灌一致，可以提交"
```

U-Boot 侧同理，把上面的路径与 defconfig 名换成 `uboot` 对应的值即可。

defconfig 名称是 Kconfig 选项（BSP → "Build options" 里的 `KERNEL_DEFCONFIG`、
`UBOOT_DEFCONFIG`），换板只改选项，不动构建文件；内核 defconfig 与 U-Boot 一样按
**最小形态**保存。

**不要在源码树根目录直接 `make savedefconfig`**：`O=` 模式下真正生效的配置在
`.binary/bsp/{kernel,uboot}/.config`，源码树里的旧 `.config` 会生成出静默丢掉平台配置的
defconfig（详见《构建系统陷阱与排查》）。

Agent 环境下 make 换用 `/usr/bin/make`（见上文"Agent 执行环境注意"）。

## 关键机制

- `.config`（Kconfig 真源）经 `-DDOT_CONFIG=...` 传入 CMake，由最先加载的
  `build/cmake/Kconfig.cmake` 模块逐符号镜像进 CMake 缓存：出现的符号精确
  `set`，随后用 `get_cmake_property` 枚举缓存变量，`CONFIG_` 前缀且不在 `.config`
  中的（因 `depends on` 隐藏而消失）精确 `unset`——约定 CMake 构建系统内
  禁止定义 `CONFIG_` 开头的变量，该命名空间专属 Kconfig；无 prompt 的派生符号（如
  `CONFIG_INIT_PROCESS`、`CONFIG_BUILD_TYPE`，由 Kconfig default 条件链生成）
  同样落盘并被 CMake 直接读取（`build/sysroot_init/CMakeLists.txt`、
  `build/CMakeLists.txt`），仅构建类型在缺失时回退 `Debug`
- 工具链文件是 Kconfig 配置项（`CONFIG_TOOLCHAIN_FILE`，menuconfig 可改，
  默认 `bsp/toolchain_files/imx6u_alpha_v2.2_12.3.cmake`）；顶层 Makefile
  经 `sinclude .config` 读取并以 `-D` 传给 cmake
- 内核/U-Boot 用 `O=` 外部输出：产物全部在 `.binary/bsp/{kernel,uboot}/`，
  源码树零残留；`make clean` 一并清除
- 安装：一条 `cmake --install` 即全量安装——`sysroot-init` 组件把编译 sysroot
  （`.binary/sysroot`）原样搬进安装前缀，`sysroot-base`（glibc 与源码模式补入的
  C++ 头/库）等组件再叠加；`--prefix` 指到 `.binary/sysroot` 本身会被守卫直接拒绝
- tftp/NFS 部署：`make nfs` **擦除 NFS 根后用同一个 `cmake --install` 装进去**
  （`NFS_INSTALL_PREFIX`，无默认值、必须设置，为空则不动作；不再依赖 `out/sysroot`、
  也不经过拷贝；板子跑过之后该目录里有 root 属主状态，擦除需 `sudo make nfs ...`，
  擦除失败则不安装）；目标板还开着时先按 agent-bridge-nfs-reinstall 停到 U-Boot 再擦，
  增量覆盖（不擦除）走 `make install INSTALL_PREFIX=<NFS 根>`；部署前若板端已运行过，
  先删除其以 root 属主重建的 `/etc/credstore*`（否则安装会因 chmod 被拒而中断，
  见《已知问题》U012）
- 组件开关在 menuconfig 中配置（如 systemd/ncurses 默认关闭；
  systemd、util-linux 无预编译件时走源码编译，耗时长）

## 输出布局

- `out/sysroot/images/`：zImage、dtb、u-boot-dtb.imx、uboot_env
- `out/sysroot/`：sysroot 组件（glibc、busybox、Qt 等）
- `out/sysroot/share/doc/`：文档站 HTML
- `.binary/bsp/{kernel,uboot}/`：内核/U-Boot 构建中间产物
