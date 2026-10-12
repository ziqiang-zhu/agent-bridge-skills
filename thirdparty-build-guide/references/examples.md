# 参考实例（与 thirdparty/build/ 现行文件对照阅读）

## 最小源码包：smiley-sans（无 choice、无 prebuilt、门控 + 两跳）

`thirdparty/build/smiley-sans.cmake` 全文要点：

```cmake
include_guard(DIRECTORY)
list(APPEND CMAKE_MESSAGE_CONTEXT "smiley-sans")

# 门控：包不存在于构建时直接返回（与七包统一的模式）
if(NOT CONFIG_ENABLE_SMILEY_SANS_THIRDPARTY)
    list(POP_BACK CMAKE_MESSAGE_CONTEXT)
    return()
endif()

thirdparty_package_declare(
    PACKAGE    smiley-sans
    VERSION    2.0.1
    URL        https://github.com/atelier-anchor/smiley-sans
    MODIFIED   OFF
    LICENSE_NAME SIL-OFL-1.1
    LICENSE_URL  https://spdx.org/licenses/SIL-OFL-1.1.html
)

set(SMILEY_SANS_SOURCE_DIR "${THIRDPARTY_DIR}/smiley-sans")
set(SMILEY_SANS_BUILD_DIR  "${THIRDPARTY_BUILD_DIR}/smiley-sans")
set(SMILEY_SANS_BINARY_DIR "${THIRDPARTY_OUTPUT_DIR}/smiley-sans")

thirdparty_package_add(smiley-sans
    COMPONENT smiley-sans
    STAGING_DIR ${SMILEY_SANS_BINARY_DIR}
    WORKING_DIRECTORY ${SMILEY_SANS_BUILD_DIR}
    CONFIGURE_COMMAND
        ${CMAKE_COMMAND} -E env
        --
        python3 -m fontmake --version
    BUILD_COMMAND
        ${CMAKE_COMMAND} -E env
        --
        python3 -m fontmake
            -g ${SMILEY_SANS_SOURCE_DIR}/src/SmileySans.glyphspackage
            --output-dir ${SMILEY_SANS_BUILD_DIR}
            --master-dir {tmp}
            --timing
        COMMAND
        python3 -m fontTools.ttx
            -m ${SMILEY_SANS_BUILD_DIR}/SmileySans-Oblique.ttf
            -o ${SMILEY_SANS_BUILD_DIR}/SmileySans-Oblique.ttf
            ${SMILEY_SANS_SOURCE_DIR}/src/SmileySans.ttx
    INSTALL_COMMAND
        ${CMAKE_COMMAND} -E make_directory
            ${SMILEY_SANS_BINARY_DIR}/usr/local/qt6/lib/fonts
        COMMAND
        ${CMAKE_COMMAND} -E copy
            ${SMILEY_SANS_BUILD_DIR}/SmileySans-Oblique.ttf
            ${SMILEY_SANS_BINARY_DIR}/usr/local/qt6/lib/fonts/SmileySans-Oblique.ttf
        COMMAND
        # 第二跳：暂存折进编译 sysroot（漏掉它 = 全量镜像缺包）
        ${CMAKE_COMMAND} -P ${BUILD_DIR}/scripts/copy_directory.cmake
            ${SMILEY_SANS_BINARY_DIR} "${THIRDPARTY_SYSROOT}"
)
```

对应的 Kconfig 条目（`build/Kconfigs/Thirdparty/Kconfig`）：

```cmake
menuconfig ENABLE_SMILEY_SANS_THIRDPARTY
	bool "smiley-sans font"
	default n
	help
		The Smiley Sans (得意黑) UI font, built from source with the
		upstream fontmake pipeline. The Qt GUI cannot render text
		without a font.
```

`GUI_ENABLE` 对它的 select 在 `build/Kconfigs/System/Kconfig`（`select ENABLE_SMILEY_SANS_THIRDPARTY` 追加在 qt6 两行之后）。

## 源码 + choice + 交叉编译：util-linux（节选）

```cmake
if(NOT CONFIG_ENABLE_UTIL_LINUX_THIRDPARTY)
    list(POP_BACK CMAKE_MESSAGE_CONTEXT)
    return()
endif()

thirdparty_package_declare(
    PACKAGE    util-linux
    VERSION    2.42
    URL        https://www.kernel.org/pub/linux/utils/util-linux/
    MODIFIED   OFF
    LICENSE_NAME GPL-2.0-or-later
    LICENSE_URL  https://spdx.org/licenses/GPL-2.0-or-later.html
)

if(CONFIG_UTIL_LINUX_PREBUILT AND EXISTS "${BSP_PREBUILT_DIR}/util-linux" AND IS_DIRECTORY "${BSP_PREBUILT_DIR}/util-linux")
    thirdparty_prebuilt_add(util-linux
        SOURCE_DIR "${BSP_PREBUILT_DIR}/util-linux"
    )
    message(STATUS "binary directory: ${BSP_PREBUILT_DIR}/util-linux/")
else()
    ...（变量定义同上）...
    thirdparty_package_add(util-linux
        COMPONENT util-linux
        STAGING_DIR ${UTIL_LINUX_BINARY_DIR}
        WORKING_DIRECTORY ${UTIL_LINUX_BUILD_DIR}
        DEPENDS glibc
        CONFIGURE_COMMAND
            ${CMAKE_COMMAND} -E env
            PATH=${PATH}
            ${UTIL_LINUX_MAKE_ENV}
            --
            ${CMAKE_COMMAND} -E chdir ${UTIL_LINUX_SOURCE_DIR} ./autogen.sh
            COMMAND
            ...（configure 选项长清单）
        BUILD_COMMAND
            ${CMAKE_COMMAND} -E env
            PATH=${PATH}
            ${UTIL_LINUX_MAKE_ENV}
            --
            ${MAKE_EXECUTABLE} all
        INSTALL_COMMAND
            ${CMAKE_COMMAND} -E env
            PATH=${PATH}
            CHOWN=true
            --
            ${MAKE_EXECUTABLE} install DESTDIR=${UTIL_LINUX_BINARY_DIR}
            COMMAND
            ${CMAKE_COMMAND} -P ${BUILD_DIR}/scripts/copy_directory.cmake
                ${UTIL_LINUX_BINARY_DIR} "${THIRDPARTY_SYSROOT}"
    )
endif()
```

要点：交叉编译环境经 `MAKE_ENV`（CFLAGS/CXXFLAGS 带 `--sysroot=${THIRDPARTY_SYSROOT}`）；`DEPENDS glibc` 保证 sysroot 先有 libc；INSTALL 两段 = DESTDIR 暂存 + 第二跳折进 sysroot。

## 宿主工具 + 组件隔离：qt6-host（节选）

```cmake
if(CONFIG_QT6_HOST_PREBUILT AND EXISTS "${BSP_PREBUILT_DIR}/qt6-host" AND IS_DIRECTORY "${BSP_PREBUILT_DIR}/qt6-host")
    # host tools stay out of the target sysroot: the extraction-only
    # component keeps them out of the phase 1 sysroot fill
    thirdparty_prebuilt_add(qt6-host
        SOURCE_DIR "${BSP_PREBUILT_DIR}/qt6-host"
        COMPONENT qt6-host
    )
    ...
```

宿主工具（moc/rcc 等只在构建机用）用**独立组件**与目标 sysroot 隔离；`DEPENDS` 链示例：`qt6-target` 的 `thirdparty_package_add(qt6-target ... DEPENDS qt6-host ...)`。
