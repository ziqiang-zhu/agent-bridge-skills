#!/bin/bash
# Like term.sh but targets a configurable host (for VMware VM -> Windows host AgentBridge).
# Usage: term-host.sh <host_ip> 'echo __MARK_BEGIN__; <command>; echo __MARK_END__'
HOST="${1:?usage: term-host.sh <host_ip> <command>}"
CMD="$2"
exec 3<>/dev/tcp/"$HOST"/2000 || { echo "connect failed: $HOST:2000"; exit 1; }
sleep 1
# drain any pending banner from the fresh shell
timeout 0.3 dd bs=4096 count=1 <&3 >/dev/null 2>&1
printf '%s\r' "$CMD" >&3
out=""
for i in $(seq 1 40); do
  chunk=$(timeout 0.5 dd bs=4096 count=1 <&3 2>/dev/null)
  out+="$chunk"
  # 结束标记必须独占一行（U-Boot 会回显命令行，子串匹配会提前退出）
  [[ "$out" == *$'\n'"__MARK_END__"* || "$out" == *$'\r'"__MARK_END__"* ]] && break
done
printf '%s\n' "$out"
exec 3<&-
