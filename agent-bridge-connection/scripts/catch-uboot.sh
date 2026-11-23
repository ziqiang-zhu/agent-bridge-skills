#!/bin/bash
# Ensure the board is stopped at the U-Boot prompt, with live state feedback.
# Usage: catch-uboot.sh <host_ip> [reboot|stay]
#   reboot (default): probe first; if the board runs Linux, reboot it and
#                     catch autoboot; if already at U-Boot, do nothing.
#   stay:             never reboot - probe and report only.
# Exit codes: 0 = at U-Boot prompt; 2 = board not in a known state (or
#             'stay' on a running board); 1 = catch failed/timed out.
#
# Lessons baked in (vs the ad-hoc spam loops): probe before acting; key
# spam at 100ms (bootdelay is 1s - 20ms floods the console for nothing);
# stop at the first U-Boot prompt; report every state seen as it happens
# so "did the Enter land" is always answerable.
HOST="${1:?usage: catch-uboot.sh <host_ip> [reboot|stay]}"
MODE="${2:-reboot}"

say() { printf '[catch-uboot] %s\n' "$*" >&2; }

exec 3<>/dev/tcp/"$HOST"/2000 || { echo "connect failed: $HOST:2000"; exit 1; }
timeout 0.3 dd bs=4096 count=1 <&3 >/dev/null 2>&1   # drain residue

# phase 1: probe - one Enter, then see which prompt answers
printf '\r' >&3
probe=""
for i in $(seq 1 8); do
    probe+=$(timeout 0.25 dd bs=512 count=16 <&3 2>/dev/null)
done
probe=$(printf '%s' "$probe" | tr -d '\r')

if printf '%s' "$probe" | grep -q '^=>'; then
    say "board already at U-Boot prompt - nothing to do"
    exec 3<&-
    exit 0
fi

if ! printf '%s' "$probe" | grep -Eq 'root@|~ >'; then
    say "board not at a known shell prompt; refusing to act blindly"
    say "probe tail: $(printf '%s' "$probe" | tail -c 100)"
    exec 3<&-
    exit 2
fi

if [ "$MODE" != "reboot" ]; then
    say "board is running Linux; 'stay' mode leaves it alone"
    exec 3<&-
    exit 2
fi

# phase 2: reboot with a moderate key spam running alongside
say "Linux shell detected - rebooting and catching autoboot (keys every 100ms)"
( while :; do printf '\r' >&3; sleep 0.1; done ) &
SPAM=$!
trap 'kill $SPAM 2>/dev/null' EXIT

printf 'systemctl reboot\r' >&3
out=""
start=$SECONDS
deadline=$((SECONDS + 90))
while [ $SECONDS -lt $deadline ]; do
    chunk=$(timeout 0.2 dd bs=512 count=32 <&3 2>/dev/null)
    [ -n "$chunk" ] || continue
    out+="$chunk"
    clean=$(printf '%s' "$chunk" | tr -d '\r')
    case "$clean" in
    *Stopped* | *Stopping*)
        [ -z "$seen_stop" ] && { seen_stop=1; say "systemd is stopping services..."; } ;;
    *"Hit any key"*)
        [ -z "$seen_hit" ] && { seen_hit=1; say "autoboot countdown seen - keys landing"; } ;;
    esac
    if printf '%s' "$clean" | grep -q '^=>'; then
        say "U-Boot prompt reached after $((SECONDS - start))s"
        break
    fi
done

kill $SPAM 2>/dev/null
trap - EXIT
exec 3<&-

if printf '%s' "$out" | tr -d '\r' | grep -q '^=>'; then
    say "success - board stopped at U-Boot"
    printf '%s' "$out" | tr -d '\r' | tail -3
    exit 0
fi

say "FAILED - U-Boot prompt not reached in 90s; last output:"
printf '%s' "$out" | tr -d '\r' | tail -5
exit 1
