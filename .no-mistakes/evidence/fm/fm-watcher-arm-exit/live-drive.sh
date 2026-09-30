#!/usr/bin/env bash
# Drive real bin/fm-watch-arm.sh --restart in a disposable lab home.
# Usage: live-drive.sh <bin-dir> <label>
BIN=$1; LABEL=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$BIN/fm-lab-home.sh" create "$LAB" >/dev/null 2>&1 || /Users/marcus.moreira.br/.no-mistakes/worktrees/c7ba7bd9b7dd/01M3P5XP3W5C5AYSWV16E9XJES/bin/fm-lab-home.sh create "$LAB" >/dev/null
S=$LAB/state
# Reproduce the report: prior episode announced, never acked; rows queued; no session lock; no re-arm loop.
printf 'announced:downtime:seedgen1\n' > $S/.watcher-down; chmod 600 $S/.watcher-down
now=$(date +%s)
for i in $(seq 1 18); do printf '%s\t%s\tcheck\ttask-%s\tcheck: task %s in flight\n' $now $i $i $i; done > $S/.wake-queue
printf '18\n' > $S/.wake-queue.seq
echo "=== [$LABEL] lab=$LAB  session lock present? $( [ -e $S/.lock ] && echo yes || echo no )"
arm() {
  local n=$1 out=$LAB/arm-$n.out
  env -u NO_MISTAKES_GATE FM_HOME="$LAB" FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$BIN/fm-watch-arm.sh" --restart > $out 2>&1 &
  local apid=$!
  sleep 12
  local wpid=$(sed -n 's/^watcher: started pid=\([0-9]*\).*/\1/p' $out | head -1)
  echo "--- restart #$n output:"; sed 's/^/    /' $out | head -8
  echo "    arm alive after 12s: $(kill -0 $apid 2>/dev/null && echo YES || echo no)"
  echo "    watcher pid=$wpid alive: $( [ -n "$wpid" ] && kill -0 $wpid 2>/dev/null && echo YES || echo no)"
  echo "    state/.watch.lock present: $( [ -e $S/.watch.lock ] && echo YES || echo no)"
  echo "    marker: $(cat $S/.watcher-down)  reopen-count: $(cat $S/.watcher-down.reopen-count 2>/dev/null || echo -)  settled: $(cat $S/.watcher-down.reopen-settled 2>/dev/null || echo -)"
  echo "    beacon age: $(( $(date +%s) - $(stat -f %m $S/.last-watcher-beat 2>/dev/null || echo 0) ))s"
  LASTARM=$apid
}
arm 1; arm 2; arm 3
echo "--- queued rows still durable: $(wc -l < $S/.wake-queue | tr -d ' ')"
env -u NO_MISTAKES_GATE FM_HOME="$LAB" "$BIN/fm-watch-arm.sh" --stop 2>&1 | sed 's/^/    stop: /'
kill $LASTARM 2>/dev/null; sleep 1
echo "--- next-session drain shows rows:"; env -u NO_MISTAKES_GATE FM_HOME="$LAB" "$BIN/fm-wake-drain.sh" 2>/dev/null | grep -c 'task-' | sed 's/^/    rows presented: /'
rm -rf "$LAB"; echo "=== lab removed"
