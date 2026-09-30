#!/usr/bin/env bash
BIN=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); $BIN/fm-lab-home.sh create "$LAB" >/dev/null; S=$LAB/state
E=(env -u NO_MISTAKES_GATE FM_HOME=$LAB FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_RECOVERY_REOPEN_LIMIT=bogus)
printf 'announced:downtime:seedgen1\n' > $S/.watcher-down; chmod 600 $S/.watcher-down
printf '%s\t1\tcheck\ttask-1\tcheck: task 1\n' $(date +%s) > $S/.wake-queue; printf '1\n' > $S/.wake-queue.seq
echo "## FM_RECOVERY_REOPEN_LIMIT=bogus (typo) - must fall back to 1"
"${E[@]}" $BIN/fm-watch-arm.sh --restart > $LAB/a1 2>&1; echo "restart#1 (exited): $(tr '\n' ' ' < $LAB/a1)"
"${E[@]}" $BIN/fm-watch-arm.sh --restart > $LAB/a2 2>&1 & A2=$!
sleep 5; echo "restart#2: $(tr '\n' ' ' < $LAB/a2) marker=$(cat $S/.watcher-down)"
echo "## soak 60s"
for t in 20 40 60; do sleep 20; echo "t=${t}s arm alive=$(kill -0 $A2 2>/dev/null && echo YES || echo no) watch.lock=$( [ -e $S/.watch.lock ] && echo YES || echo no)"; done
echo "## genuine session ack, then a new durable wake: must still resurface once"
"${E[@]}" $BIN/fm-watch-arm.sh --stop | sed 's/^/stop: /'; wait $A2 2>/dev/null
"${E[@]}" $BIN/fm-wake-drain.sh > $LAB/d.out 2> $LAB/d.err
echo "drain presented: $(grep -c task-1 $LAB/d.out) row(s); $(grep '^WAKE_ACK_REQUIRED' $LAB/d.err || echo 'no ack line')"
SEQ=$(sed -n 's/.*--ack-through \([0-9]*\).*/\1/p' $LAB/d.err); GEN=$(sed -n 's/.*--recovery-generation \([^ ]*\)$/\1/p' $LAB/d.err)
if [ -n "$SEQ" ]; then "${E[@]}" $BIN/fm-wake-drain.sh --ack-through $SEQ ${GEN:+--recovery-generation $GEN} >/dev/null 2>&1; echo "ack rc=$? marker=$(cat $S/.watcher-down) settled=$(cat $S/.watcher-down.reopen-settled 2>/dev/null || echo -) queue=$(wc -l < $S/.wake-queue | tr -d ' ')"; fi
printf '%s\t9\tcheck\tnew-work\tcheck: new work\n' $(date +%s) >> $S/.wake-queue; printf '9\n' > $S/.wake-queue.seq
echo "marker before restart: $(cat $S/.watcher-down)"
"${E[@]}" $BIN/fm-watch-arm.sh --restart > $LAB/a3 2>&1; echo "restart after genuine ack+new row (exited): $(tr '\n' ' ' < $LAB/a3)"
rm -rf "$LAB"; echo "lab removed"
