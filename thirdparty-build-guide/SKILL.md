---
name: thirdparty-build-guide
description: 在 Camphora 构建系统中新增第三方库、修改第三方库构建逻辑时必用的操作指南。当用户要求"新增/接入一个第三方库"、"给某包加开关/选项/依赖"、"改某个包的 configure/build/install 步骤"、"第三方包装不进镜像/没被构建"时使用——即使用户只说"加个库"或"改一下构建"。阅读 thirdparty/build 与 build/modules/ThirdpartyBuild.cmake 后按本指南操作。
metadata:
   version: 1.1.0
   author: ziqiang.zhu
---

# 第三方库构建指南

第三方包 = **一个 Kconfig 条目 + 一个 `thirdparty/build/<pkg>.cmake` + （可选）源码目录**。机制由 `build/modules/ThirdpartyBuild.cmake` 提供，本指南是该机制的操作手册。动手前先通读本文件；需要完整实例时读 `references/examples.md`。

## 架构速览

- `thirdparty/CMakeLists.txt` —— 聚合入口：`include_thirdparty(<pkg>)` 逐个加载 `build/<pkg>.cmake`；定义 `THIRDPARTY_*` 路径变量、`NINJA_JOBS`、meson cross file；
- `thirdparty/build/<pkg>.cmake` —— 每包一个文件：门控 → 声明 → 分支（source/prebuilt）→ 注册；
- `build/modules/ThirdpartyBuild.cmake` —— 机制模块，提供四个接口：
  - `thirdparty_package_declare(...)`：许可证与版本声明（必填 `PACKAGE/VERSION/URL/MODIFIED/LICENSE_NAME/LICENSE_URL`），自动汇入文档站《开源软件声明》页，重复声明报错；
  - `thirdparty_package_add(pkg ...)`：源码构建注册（三阶段命令 + 步骤戳记 + 暂存目录 + sysroot 组 + 安装规则）；
  - `thirdparty_prebuilt_add(pkg ...)`：预编译快照注册（从 `bsp/prebuilt/<pkg>` 直接安装）；
  - `add_to_build_group(<pkg> sysroot)` 由上述函数内部自动完成（目标进入 `sysroot-group`）。

**两跳安装（已机制化）**：包的产物先由 `INSTALL_COMMAND` 暂存到 `STAGING_DIR`（`output/<pkg>/usr/...` 布局）；**sysroot 折叠由模块注册的 fold 步骤自动承担**（`copy_directory.cmake` 将 staging 拷入编译 sysroot），`INSTALL_COMMAND` 里**不要再手写拷贝段**。sysroot 不可信：`Makefile.top` 在每次 `.config` 变更后全删重建 sysroot 并 touch 信号，fold 步骤依赖 sysroot 目录 mtime、自动整体重折叠（纯拷贝），重建/安装步骤仍由命令清单门控。随后 `sysroot-init` 组件随全量安装（`make install`/`make nfs`）把编译 sysroot 原样装进目标前缀。（历史事故：smiley-sans 首次接入漏了折叠段、全量重装后字体消失——该事故促成了本机制的机制化。）

## 场景一：新增第三方库

按序完成以下七步（缺一不可）：

1. **源码就位**：`thirdparty/<pkg>/`（git 子模块或检出的上游源码）；变量命名统一 `<PKG>_SOURCE_DIR`/`_BUILD_DIR`/`_BINARY_DIR`（`THIRDPARTY_BUILD_DIR`/`THIRDPARTY_OUTPUT_DIR` 之下）。
2. **Kconfig 条目**（`build/Kconfigs/Thirdparty/Kconfig`）：`menuconfig ENABLE_<PKG>_THIRDPARTY`，**默认 n**；有依赖关系用 `select` 链表达（如 systemd select util-linux，GUI select qt6 与字体）。同时存在源码/预编译两种形态时加 `choice`（SOURCE/PREBUILT，`depends on ENABLE_<PKG>_THIRDPARTY`）；纯源码或纯预编译可不加 choice（在 cmake 注释里说明原因）。
3. **包文件** `thirdparty/build/<pkg>.cmake`，骨架（最小真实样例见 `references/examples.md` 的 smiley-sans 一节）：

   ```cmake
   include_guard(DIRECTORY)
   list(APPEND CMAKE_MESSAGE_CONTEXT "<pkg>")

   if(NOT CONFIG_ENABLE_<PKG>_THIRDPARTY)
       list(POP_BACK CMAKE_MESSAGE_CONTEXT)
       return()
   endif()

   thirdparty_package_declare(
       PACKAGE    <pkg>
       VERSION    <x.y.z>
       URL        https://...
       MODIFIED   OFF
       LICENSE_NAME <SPDX>
       LICENSE_URL  https://spdx.org/licenses/....html
   )

   set(<PKG>_SOURCE_DIR "${THIRDPARTY_DIR}/<pkg>")
   set(<PKG>_BUILD_DIR  "${THIRDPARTY_BUILD_DIR}/<pkg>")
   set(<PKG>_BINARY_DIR "${THIRDPARTY_OUTPUT_DIR}/<pkg>")

   thirdparty_package_add(<pkg>
       COMPONENT <pkg>
       STAGING_DIR ${<PKG>_BINARY_DIR}
       WORKING_DIRECTORY ${<PKG>_BUILD_DIR}
       CONFIGURE_COMMAND ...
       BUILD_COMMAND ...
       INSTALL_COMMAND
           ...（产物进 ${<PKG>_BINARY_DIR} 的 usr/ 布局；sysroot 折叠由
           fold 步骤自动完成，勿手写拷贝段）
   )
   ```

4. **注册**：`thirdparty/CMakeLists.txt` 追加 `include_thirdparty(<pkg>)`。
5. **验证**：`make olddefconfig` 后 `.config` 出现 `CONFIG_ENABLE_<PKG>_THIRDPARTY=y`（或有依赖时由 select 带出）；`make build` 三阶段戳记走完、`STAGING_DIR` 产物就位、**`.binary/sysroot` 里有产物（第二跳验证）**；`cmake --install .binary --component <pkg>` 可单独提取（调试用）。
6. **声明页**：`make docs` 后《开源软件声明》页出现该包。
7. **文档**：若包对使用方有契约（路径、组件名），同步相关分册。

## 场景二：修改第三方库构建逻辑

改的是 `thirdparty/build/<pkg>.cmake` 的三段命令或 `build/modules/ThirdpartyBuild.cmake` 的机制。规则：

- **戳记与重建**：每个包的三段命令全文写入 `steps/<pkg>.cmd` 并生成 `configure/build/install.stamp`。**命令清单有任何字节变化 → 该包自动全量重跑**；清单不变则戳记命中、零重建。修改逻辑前先想清楚代价：改动 CONFIGURE 段会重跑整个包。
- **阶段不变性**：三段命令在两阶段配置（P1 无 sysroot / P2 有 sysroot）下必须**逐字节相同**——否则命令清单在两阶段间来回翻转，戳记失效、每次构建都重跑。命令需要 sysroot 时显式写 `${THIRDPARTY_SYSROOT}`（两阶段同值），不要用 `${CMAKE_SYSROOT}`。
- **并行度**：make 类命令继承顶层 jobserver（**不要**自带 `-j`）；ninja 类命令用 `NINJA_JOBS` 显式封顶（ninja 不消费 GNU make jobserver，缺省会开核数+2）。
- **依赖**：`DEPENDS <other-pkg>` 表达构建顺序（如 qt6-host → qt6-target，glibc 最先）；不要为" sysroot 里有某头文件"之类理由加假依赖。
- **机制修改**（ThirdpartyBuild.cmake 本体）：改动影响所有包——修改前通读现有注释（阶段不变性、suid、假值常量等事故都有记录）；修改后至少验证两个包（一个 make 类一个 ninja 类）的戳记行为：清单不变时零重建、变化时精确重跑。

## 陷阱清单（真实事故）

- **staging 即终点**：`INSTALL_COMMAND` 只装 staging，sysroot 折叠由 fold 步骤机制化承担（依赖 sysroot 目录 mtime，每次 `.config` 变更后自动重折叠）——`INSTALL_COMMAND` 里不要再手写 copy_directory 拷贝段。
- **假值常量**：CMake 里 `if(NOT VAR)` 对值 `"OFF"`/`"0"` 判假——判断"是否提供"用 `STREQUAL ""`/`DEFINED`（declare 函数内 MODIFIED=OFF 的处理就是为此）。
- **正则误用**：对包名做 `MATCHES` 会把名字里的正则字符当语法（declare 的重复检测因此改用字面量比较）。
- **CACHE 残留**：跨运行的注册表用 `GLOBAL PROPERTY`（每次 configure 重置），不用 `CACHE INTERNAL` 列表（永不失效，重复配置误报）。
- **s 位**：镜像内全部进程以 root 运行，无 suid 需求；NFS root 环境下 suid 反而不可用（实测 mount 带 s 位失败）。安装后权限由统一规范化兜底，包内不要保留上游的 suid 位。

## 验证基线

任何改动收尾时：`make olddefconfig` + `make build` 全绿；受影响包戳记行为符合预期；`.binary/sysroot` 产物在位；`make docs` 0 告警且《开源软件声明》正确；上板（或 NFS 树）抽查产物可用。
