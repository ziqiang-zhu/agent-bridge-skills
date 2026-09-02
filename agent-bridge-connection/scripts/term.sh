#!/bin/bash
# Send a command to the AgentBridge raw TCP terminal at 127.0.0.1:2000 and print the response.
# Usage: term.sh 'echo __MARK_BEGIN__; <command>; echo __MARK_END__'
exec 3<>/dev/tcp/127.0.0.1/2000 || exit 1
sleep 1
# drain any pending banner from the fresh shell
timeout 0.3 dd bs=4096 count=1 <&3 >/dev/null 2>&1
printf '%s\r' "$1" >&3
out=""
for i in $(seq 1 40); do
  chunk=$(timeout 0.5 dd bs=4096 count=1 <&3 2>/dev/null)
  out+="$chunk"
  [[ "$out" == *"__MARK_END__"* ]] && break
done
printf '%s\n' "$out"
exec 3<&-
