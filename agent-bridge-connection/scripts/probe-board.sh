#!/bin/bash
# probe-board.sh <桥IP> [总超时秒=180] [静默确认间隔秒=10]
#
# 重启后的到达探测：每 3 秒开一次短连接（连上→读→必要时写→断开），
# 读取串口累积输出并分类，到达目标态立即返回。桥是纯直播语义——
# 无客户端连接时的串口输出会丢失，所以"确认回车"与"读回显"必须在
# 同一连接内完成；主代理在探测期间不得占用桥。
#
# 分类：
#   shell —— root@… 提示符或 "~ #" / "~ >"（Linux 到达）
#   uboot —— "=> " 提示符（停在 U-Boot）
#   panic —— 内核崩溃（Kernel panic / not syncing）
# 静默超过间隔秒：同连接发一个回车并读回显（无副作用）；
# 总超时返回 timeout。
#
# 输出：VERDICT: <shell|uboot|panic|timeout> + 关键尾部输出。
# 退出码：0=shell 3=uboot 4=panic 2=timeout。
IP=${1:?usage: probe-board.sh <bridge-ip> [timeout=180] [silence=10]}
TMO=${2:-180}
SIL=${3:-10}
start=$(date +%s)
last_data=$(date +%s)
tail_out=""
classify() {
    case "$1" in
        *"Kernel panic"*|*"not syncing"*) echo panic ;;
        *'~ #'*|*'~ >'*) echo shell ;;
        *"root@"*) echo shell ;;
        *'=>'*) echo uboot ;;
    esac
}
while :; do
    now=$(date +%s)
    elapsed=$((now - start))
    if [ "$elapsed" -ge "$TMO" ]; then
        echo "VERDICT: timeout after ${elapsed}s"
        printf '%s' "$tail_out" | tail -5
        exit 2
    fi
    out=$(timeout 2 bash -c "exec 3<>/dev/tcp/$IP/2000 && dd bs=4096 count=8 <&3 2>/dev/null" 2>/dev/null)
    if [ -n "$out" ]; then
        last_data=$(date +%s)
        tail_out="$out"
        verdict=$(classify "$out")
        if [ -n "$verdict" ]; then
            echo "VERDICT: $verdict after ${elapsed}s"
            printf '%s' "$tail_out" | tail -5
            case "$verdict" in
                shell) exit 0 ;;
                uboot) exit 3 ;;
                panic) exit 4 ;;
            esac
        fi
    elif [ $((now - last_data)) -ge "$SIL" ]; then
        # 静默确认：同连接发回车并读回显（桥无缓存，分两次连接会丢回显）
        last_data=$(date +%s)
        out=$(timeout 3 bash -c "exec 3<>/dev/tcp/$IP/2000 && printf '\r' >&3 && dd bs=4096 count=8 <&3 2>/dev/null" 2>/dev/null)
        echo "probe: silent ${SIL}s - sent Enter, read ${#out} bytes ($((now - start))s elapsed)" >&2
        if [ -n "$out" ]; then
            tail_out="$out"
            verdict=$(classify "$out")
            if [ -n "$verdict" ]; then
                echo "VERDICT: $verdict after ${elapsed}s"
                printf '%s' "$tail_out" | tail -5
                case "$verdict" in
                    shell) exit 0 ;;
                    uboot) exit 3 ;;
                    panic) exit 4 ;;
                esac
            fi
        fi
    fi
    sleep 3
done
