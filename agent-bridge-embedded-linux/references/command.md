# TCP 终端完整命令字典

> 本文档供 Agent 按需加载。当用户询问未在 `SKILL.md` 中列出的特定硬件或深度调试信息时，请参考以下分类命令。

## 1. 系统与内核 (System & Kernel)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `uname -a` | 显示内核名称、网络名、内核版本、架构。 |
| `cat /proc/version` | 显示内核编译版本和 GCC 版本。 |
| `cat /etc/os-release` | 查看发行版信息（Buildroot / OpenWrt / Yocto）。 |
| `uptime` | 查看系统运行时间及平均负载。 |
| `dmesg` | 内核环形缓冲区日志。**注意**：`dmesg \| grep -i error` 快速排查驱动报错。 |
| `dmesg \| grep -i "mmc\|sd\|usb\|i2c"` | 过滤特定外设的枚举日志。 |
| `cat /proc/cmdline` | 查看内核启动参数（bootargs）。 |
| `watch -n 1 'cat /proc/loadavg'` | 动态监测负载（注意板上可能无 `watch`，可用 `while` 循环替代）。 |

## 2. CPU 与性能 (CPU & Performance)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `cat /proc/cpuinfo` | 查看 SoC 型号、BogoMIPS、硬件序列号。**查找 `Hardware` 字段确认板型**。 |
| `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq` | 当前 CPU 频率（kHz），需内核开启 cpufreq。 |
| `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies` | 支持的所有频率档位。 |
| `cat /sys/devices/system/cpu/possible` | 查看 CPU 核心数量（如 0-3 表示四核）。 |
| `top -n 1 -b` | 批处理模式查看实时进程资源占用（`-b` 去除交互转义）。 |
| `ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu \| head -10` | 查看 CPU 占用最高的 10 个进程。 |

## 3. 内存与存储 (Memory & Storage)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `cat /proc/meminfo` | 详细内存分配（MemTotal, MemFree, Cached, SwapTotal）。 |
| `free -m` | 以 MB 为单位查看内存使用。 |
| `vmstat 1 5` | 虚拟内存统计（进程、内存、分页、阻塞进程数）。 |
| `cat /proc/mtd` | 查看 MTD 分区表（SPI NAND/NOR 布局）。 |
| `cat /proc/partitions` | 查看块设备分区（eMMC/SD 卡）。 |
| `df -h` | 查看文件系统磁盘空间占用。 |
| `du -sh /* 2>/dev/null \| sort -hr \| head -10` | 查看根目录下占用最大的前 10 个文件夹（排查存储爆满）。 |
| `lsblk` | 列出所有块设备及其挂载点（若 BusyBox 支持）。 |
| `mount` | 查看当前挂载的文件系统列表。 |

## 4. USB 与总线 (USB & Bus)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `lsusb` | 列出 USB 设备树（VID:PID）。**非 `1d6b` 即为外接设备**。 |
| `lsusb -t` | 树形显示 USB 拓扑结构（HUB 层级）。 |
| `ls -l /sys/bus/usb/devices/` | 查看 USB 设备目录，`-` 开头是端口，`:1.0` 结尾是接口。 |
| `cat /sys/kernel/debug/usb/devices` | 详细 USB 设备描述符（需内核开启 debug）。 |
| `dmesg \| grep -i usb \| tail -20` | 查看 USB 热插拔识别日志。 |

## 5. 网络与无线 (Network & WiFi)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `ifconfig -a` 或 `ip addr` | 查看所有网络接口 IP 地址。 |
| `iwconfig` | 查看无线接口（wlan0）的 SSID、信号强度、速率。 |
| `route -n` 或 `ip route` | 查看内核路由表（网关配置）。 |
| `cat /proc/net/dev` | 查看各网络接口的收发包统计（排查丢包）。 |
| `cat /sys/class/net/wlan0/operstate` | 查看 WiFi 连接状态（up/down）。 |
| `cat /sys/class/net/wlan0/speed` | 查看当前协商速率（Mbps）。 |
| `ping -c 4 8.8.8.8` | 测试外网连通性。 |
| `netstat -anp \| grep LISTEN` | 查看监听中的端口（调试服务绑定）。 |

## 6. I2C / SPI / 传感器 (Peripherals)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `i2cdetect -l` | 列出可用的 I2C 总线编号。 |
| `i2cdetect -y <总线号>` | 扫描该总线上的设备地址（如 `1-005d` 表示总线1地址0x5d）。 |
| `i2cget -y <总线号> <地址> <寄存器>` | 读取指定寄存器值（需知道芯片手册）。 |
| `ls /sys/bus/spi/devices/` | 查看挂载的 SPI 设备。 |
| `cat /sys/bus/iio/devices/iio:device0/in_temp_input` | 读取 CPU 内部温度传感器（路径可能不同）。 |
| `find /sys -name "*temp*" \| grep iio` | 自动查找温度传感器节点。 |

## 7. GPIO 与 中断 (GPIO & Interrupts)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `cat /proc/interrupts` | 查看所有中断统计。**观察 GPIO 中断号计数是否增长，判断按键/外设触发**。 |
| `cat /sys/kernel/debug/gpio` | 查看 GPIO 申请和占用状态（需内核 debug）。 |
| `ls /sys/class/gpio/` | 查看导出后的 GPIO 文件节点（若有）。 |
| `cat /proc/iomem` | 查看 SoC 寄存器物理地址映射，常用于裸机/驱动调试。 |

## 8. 进程与调试 (Processes & Debug)

| 命令 | 说明与解析要点 |
| :--- | :--- |
| `ps -ef \| grep [进程名]` | 查找特定进程的 PID。 |
| `kill -9 <PID>` | 强制结束进程。 |
| `cat /proc/<PID>/cmdline` | 查看进程启动的完整命令（含参数）。 |
| `strace -p <PID> -c` | 统计进程的系统调用（板上不一定有 strace）。 |
| `watch -n 1 'cat /proc/<PID>/status \| grep VmRSS'` | 动态监控进程内存占用。 |
| `fd` 或 `ls -l /proc/<PID>/fd/` | 查看进程打开的文件描述符。 |

## 9. 快捷组合技 (One-liner 组合)

当需要快速综合诊断时，可以用分号串联多个命令（注意用 `\r` 结尾）：

```bash
# 一键打印系统关键信息
echo __MARK_BEGIN__; uname -a; free -m; df -h; lsusb; ifconfig; echo __MARK_END__;

```
