#!/usr/bin/env bash
# =============================================================================
#  Sylvy — self-assessment tests (student)
#  Usage: sudo ./sylvy-test.sh ./path/to/sylvy
#  The script starts your agent itself, replays every scenario and checks
#  that the expected alert shows up in the agent's JSON output.
#  A scenario that is not detected = FAIL.
# =============================================================================
set -u
GRADE=0
WAIT=${WAIT:-10}            # max seconds for an exec-related alert to appear
PORT_WAIT=${PORT_WAIT:-12}  # port scanning may take a few seconds
IDLE_SECS=${IDLE_SECS:-20}
BURST_N=${BURST_N:-3000}

# ---------- Pre-flight -------------------------------------------------------
if [[ $EUID -ne 0 ]]; then echo "Run as root: sudo $0 ./sylvy"; exit 2; fi
if [[ $# -lt 1 || ! -x $1 ]]; then echo "Usage: sudo $0 ./sylvy"; exit 2; fi
for c in jq python3 setpriv ss awk getconf; do
  command -v "$c" >/dev/null || { echo "Missing tool: $c — install jq, python3, util-linux (setpriv) and iproute2 (ss) with your distro's package manager"; exit 2; }
done
AGENT=$(readlink -f "$1")
RES="$PWD/sylvy-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RES"
OUT="$RES/alerts.jsonl"; ERR="$RES/agent.stderr"; REPORT="$RES/report.md"
HZ=$(getconf CLK_TCK)

rnd()      { tr -dc 'a-z0-9' </dev/urandom | head -c 8; }
freeport() { local p; while :; do p=$((20000 + RANDOM % 40000)); ss -Htln "sport = :$p" | grep -q . || { echo "$p"; return; }; done; }

PIDS=(); FILES=()
cleanup() {
  kill "${PIDS[@]}" 2>/dev/null
  [[ -n ${AGENT_PID:-} ]] && kill "$AGENT_PID" 2>/dev/null
  rm -rf "${FILES[@]}" 2>/dev/null
}
trap cleanup EXIT

# ---------- Helpers ----------------------------------------------------------
# wait_event <timeout> <jq filter> [--argjson/--arg ...]: wait for a matching JSON line
wait_event() {
  local t=$1 f=$2; shift 2; local i=0 r
  while (( i < t * 10 )); do
    r=$(jq -cR "$@" "fromjson? | select($f)" "$OUT" 2>/dev/null | head -n1)
    [[ -n $r ]] && { echo "$r"; return 0; }
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
# no_event <jq filter> [args]: true if no line matches
no_event()  { local f=$1; shift; [[ -z $(jq -cR "$@" "fromjson? | select($f)" "$OUT" 2>/dev/null | head -n1) ]]; }
cpu_ticks() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $12+$13+$14+$15}'; }
rss_kb()    { awk '/VmRSS/{print $2}' "/proc/$1/status" 2>/dev/null; }
alive()     { kill -0 "$AGENT_PID" 2>/dev/null; }

SCORE=0; TOTAL=0; BONUS=0; FAILED=0; MAXRSS=0
declare -A CAT_S CAT_T
{ echo "# Sylvy test report"; echo; echo "Agent: \`$AGENT\` · Date: $(date -Is)"; echo;
  echo "| Test | Category | Points | Result | Detail |"; echo "|---|---|---|---|---|"; } >"$REPORT"

result() { # result <id> <category> <points> <description> <0=ok|1=ko> [detail]
  local id=$1 cat=$2 pts=$3 desc=$4 ok=$5 det=${6:-}
  if [[ $cat == bonus ]]; then
    [[ $ok -eq 0 ]] && BONUS=$((BONUS + pts))
  else
    TOTAL=$((TOTAL + pts)); CAT_T[$cat]=$(( ${CAT_T[$cat]:-0} + pts ))
  fi
  if [[ $ok -eq 0 ]]; then
    [[ $cat != bonus ]] && { SCORE=$((SCORE + pts)); CAT_S[$cat]=$(( ${CAT_S[$cat]:-0} + pts )); }
    printf '  \e[32m✔ PASS\e[0m  %-4s %s %s\n' "$id" "$desc" "${det:+($det)}"
    echo "| $id $desc | $cat | $pts/$pts | ✅ | $det |" >>"$REPORT"
  else
    [[ $cat != bonus ]] && FAILED=$((FAILED + 1))
    CAT_S[$cat]=${CAT_S[$cat]:-0}
    printf '  \e[31m✘ FAIL\e[0m  %-4s %s %s\n' "$id" "$desc" "${det:+($det)}"
    echo "| $id $desc | $cat | 0/$pts | ❌ | $det |" >>"$REPORT"
  fi
  sample_rss
}
skip() { # skip <id> <description> <reason>: not applicable, excluded from the total
  printf '  \e[33m– SKIP\e[0m  %-4s %s (%s)\n' "$1" "$2" "$3"
  echo "| $1 $2 | — | — | ⏭️ | $3 |" >>"$REPORT"
}
# "Negative" tests (performance, false positives) only score if the agent really
# detects exec events (T1a): an agent that does nothing scores nothing.
CORE=0
gresult() { if [[ $CORE -eq 1 ]]; then result "$@"; else result "$1" "$2" "$3" "$4" 1 "not evaluated: agent does not detect exec events"; fi; }
# spec <rule>: the rule was NOT emitted for the legitimate reference processes.
# An agent that alerts on everything therefore scores nothing on detection tests.
spec() {
  local p port
  if [[ $1 == UNKNOWN_LISTEN_PORT ]]; then
    for port in $BASELINE_PORTS; do no_event '.rule=="UNKNOWN_LISTEN_PORT" and .port==$port' --argjson port "$port" || return 1; done
  else
    for p in "${LEGIT_PIDS[@]}"; do no_event '.pid==$p and .rule==$r' --argjson p "$p" --arg r "$1" || return 1; done
  fi
}
# detect <id> <cat> <pts> <desc> <rule> <0|1>: detection result with specificity check
detect() {
  if [[ $6 -ne 0 ]]; then result "$1" "$2" "$3" "$4" 1 "not detected"
  elif ! spec "$5"; then result "$1" "$2" "$3" "$4" 1 "$5 also emitted for legitimate processes"
  else result "$1" "$2" "$3" "$4" 0; fi
}
sample_rss() { local r; r=$(rss_kb "$AGENT_PID"); [[ -n $r && $r -gt $MAXRSS ]] && MAXRSS=$r; }
# run_from <path> <args...>: copy sleep to <path> and run it in the background, sets P
run_copy() { local dst=$1; shift; cp /usr/bin/sleep "$dst"; FILES+=("$dst"); "$dst" "$@" & P=$!; PIDS+=($P); }

# ---------- Start the agent --------------------------------------------------
BASELINE_PORTS=$(ss -Htln | awk '{n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')
echo "▶ Starting agent: $AGENT"
"$AGENT" >"$OUT" 2>"$ERR" &
AGENT_PID=$!
sleep 4
if ! alive; then echo "✘ The agent exited during startup. See $ERR"; exit 1; fi
echo "  PID $AGENT_PID · ports listening at startup: $BASELINE_PORTS"

# ---------- P1: idle CPU -----------------------------------------------------
echo; echo "▶ Idle performance (${IDLE_SECS}s)"
c0=$(cpu_ticks "$AGENT_PID"); sleep "$IDLE_SECS"; c1=$(cpu_ticks "$AGENT_PID")
IDLE=$(awk -v d=$((c1 - c0)) -v hz="$HZ" -v s="$IDLE_SECS" 'BEGIN{printf "%.2f", d*100/(hz*s)}')
echo "  measured: ${IDLE} % (scored at the end)"

# ---------- F1: process events -----------------------------------------------
echo; echo "▶ F1 · Process events"
D="7.$RANDOM"
/usr/bin/sleep "$D" & P=$!; PIDS+=($P); LEGIT_PIDS=($P)
if E=$(wait_event "$WAIT" '.rule=="EXEC" and .pid==$p and .exe=="/usr/bin/sleep"' --argjson p "$P"); then
  result T1a F1 8 "exec detected (pid + exe)" 0; CORE=1
  ok=1; [[ $(jq -r '.ppid' <<<"$E") == "$$" && $(jq -r '.cmdline' <<<"$E") == *"$D"* ]] && ok=0
  result T1b F1 5 "ppid and cmdline are correct" $ok "ppid=$(jq -r .ppid <<<"$E") expected=$$"
else
  result T1a F1 8 "exec detected (pid + exe)" 1 "no EXEC event for pid $P"
  result T1b F1 5 "ppid and cmdline are correct" 1
fi
setpriv --reuid=65534 --regid=65534 --clear-groups /usr/bin/sleep 7 & P=$!; PIDS+=($P); LEGIT_PIDS+=($P)
E=$(wait_event "$WAIT" '.rule=="EXEC" and .pid==$p and .exe=="/usr/bin/sleep"' --argjson p "$P") && ok=$([[ $(jq -r .uid <<<"$E") == 65534 ]] && echo 0 || echo 1) || ok=1
result T1c F1 5 "uid is correct (user nobody)" $ok
/usr/bin/tail -f /dev/null & P=$!; PIDS+=($P); LEGIT_PIDS+=($P)
python3 -c 'import time; time.sleep(7)' & P=$!; PIDS+=($P); LEGIT_PIDS+=($P)

# ---------- F2: suspicious paths ---------------------------------------------
echo; echo "▶ F2 · Suspicious paths"
run_copy "/tmp/$(rnd)" 7
wait_event "$WAIT" '.rule=="SUSPICIOUS_PATH" and .pid==$p' --argjson p "$P" >/dev/null; ok=$?
detect T2a F2 6 "execution from /tmp" SUSPICIOUS_PATH $ok
run_copy "/dev/shm/$(rnd)" 7
wait_event "$WAIT" '.rule=="SUSPICIOUS_PATH" and .pid==$p' --argjson p "$P" >/dev/null; ok=$?
detect T2b F2 6 "execution from /dev/shm" SUSPICIOUS_PATH $ok

# ---------- F3: listening ports ----------------------------------------------
echo; echo "▶ F3 · Listening ports"
PORT=$(freeport)
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 & P=$!; PIDS+=($P)
if E=$(wait_event "$PORT_WAIT" '.rule=="UNKNOWN_LISTEN_PORT" and .port==$port' --argjson port "$PORT"); then
  detect T3a F3 8 "new listening port $PORT reported" UNKNOWN_LISTEN_PORT 0
  ok=$([[ $(jq -r .pid <<<"$E") == "$P" ]] && echo 0 || echo 1)
  result T3b F3 2 "port attributed to the right process" $ok "pid=$(jq -r .pid <<<"$E") expected=$P"
else
  result T3a F3 8 "new listening port $PORT reported" 1 "not detected"
  result T3b F3 2 "port attributed to the right process" 1
fi

# ---------- Attack scenarios -------------------------------------------------
echo; echo "▶ Attack scenarios"
if [[ $GRADE -eq 1 ]]; then AP=3; else AP=4; fi

DIR="/tmp/.$(rnd)"; mkdir -p "$DIR"; FILES+=("$DIR")
run_copy "$DIR/kworker" 7
wait_event "$WAIT" '.rule=="SUSPICIOUS_PATH" and .pid==$p' --argjson p "$P" >/dev/null; ok=$?
detect A1 scenarios $AP "masquerading as kworker in a hidden directory" SUSPICIOUS_PATH $ok

B="/usr/local/bin/$(rnd)"; cp /usr/bin/sleep "$B"
python3 -c "import os,sys; fd=os.open(sys.argv[1], os.O_RDONLY); os.unlink(sys.argv[1]); os.execve(fd, ['upd', '7'], {})" "$B" & P=$!; PIDS+=($P)
wait_event "$WAIT" '.rule=="DELETED_BINARY" and .pid==$p' --argjson p "$P" >/dev/null; ok=$?
detect A2 scenarios $AP "binary deleted from disk before execution" DELETED_BINARY $ok

python3 -c "import os; f=os.memfd_create('$(rnd)'); os.write(f, open('/usr/bin/sleep','rb').read()); os.execve(f, ['sleep', '7'], {})" & P=$!; PIDS+=($P)
wait_event "$WAIT" '.rule=="MEMFD_EXEC" and .pid==$p' --argjson p "$P" >/dev/null; ok=$?
detect A3 scenarios $AP "fileless execution (memfd)" MEMFD_EXEC $ok

PY=$(command -v python3); B="/tmp/.$(rnd)"; cp "$PY" "$B"; FILES+=("$B"); PORT2=$(freeport)
"$B" -c "import socket,time; a=chr(49)+chr(50)+chr(55)+chr(46)+chr(48)+chr(46)+chr(48)+chr(46)+chr(49); s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind((a,$PORT2)); s.listen(); time.sleep(40)" & P=$!; PIDS+=($P)
ok=1
if wait_event "$WAIT" '.rule=="SUSPICIOUS_PATH" and .pid==$p' --argjson p "$P" >/dev/null &&
   wait_event "$PORT_WAIT" '.rule=="UNKNOWN_LISTEN_PORT" and .port==$port' --argjson port "$PORT2" >/dev/null; then ok=0; fi
spec UNKNOWN_LISTEN_PORT || ok=1
detect A4 scenarios $AP "backdoor: interpreter copied into /tmp listening on $PORT2" SUSPICIOUS_PATH $ok


# ---------- Bonus: package provenance ----------------------------------------
echo; echo "▶ Bonus · Package provenance (optional)"
run_copy "/usr/local/bin/$(rnd)" 7
UNPKG_PID=$P
wait_event 3 '.rule=="UNPACKAGED_BINARY" and .pid==$p' --argjson p "$P" >/dev/null; ok=$?
if [[ $ok -eq 0 ]] && ! spec UNPACKAGED_BINARY; then ok=1; fi
result B1 bonus 4 "binary outside any installed package reported (optional)" $ok

# ---------- False positives --------------------------------------------------
echo; echo "▶ False positives"
ok=0; bad=""
for p in "${LEGIT_PIDS[@]}"; do no_event '.pid==$p and (.level=="warn" or .level=="alert")' --argjson p "$p" || { ok=1; bad+="$p "; }; done
no_event '.pid==$p and .rule=="SUSPICIOUS_PATH"' --argjson p "$UNPKG_PID" || { ok=1; bad+="/usr/local/bin "; }
gresult FP1 scenarios 2 "no alert on legitimate processes (sleep, tail, python3)" $ok "$bad"
ok=0; bad=""
for port in $BASELINE_PORTS; do no_event '.rule=="UNKNOWN_LISTEN_PORT" and .port==$port' --argjson port "$port" || { ok=1; bad+="$port "; }; done
gresult FP2 scenarios 2 "no alert on ports that were open before the agent started" $ok "$bad"

# ---------- P3/P4: exec burst ------------------------------------------------
echo; echo "▶ Performance under load ($BURST_N executions)"
n0=$(jq -cR 'fromjson? | select(.rule=="EXEC")' "$OUT" | wc -l)
c0=$(cpu_ticks "$AGENT_PID"); t0=$(date +%s%N)
for ((i = 0; i < BURST_N; i++)); do /usr/bin/true; done
t1=$(date +%s%N); sleep 2; c1=$(cpu_ticks "$AGENT_PID"); sample_rss
n1=$(jq -cR 'fromjson? | select(.rule=="EXEC")' "$OUT" | wc -l)
SECS=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", (b-a)/1e9 + 2}')
RATE=$(awk -v n="$BURST_N" -v a="$t0" -v b="$t1" 'BEGIN{printf "%d", n/((b-a)/1e9)}')
LOAD=$(awk -v d=$((c1 - c0)) -v hz="$HZ" -v s="$SECS" 'BEGIN{printf "%.2f", d*100/(hz*s)}')
CAPT=$(awk -v n=$((n1 - n0)) -v t="$BURST_N" 'BEGIN{x=n*100/t; if (x>100) x=100; printf "%.1f", x}')
gresult P3 perf 3 "CPU under load < 10 % (~$RATE exec/s)" "$(awk -v x="$LOAD" 'BEGIN{print (x<10)?0:1}')" "${LOAD} %"
gresult P4 perf 2 "at least 90 % of executions captured" "$(awk -v x="$CAPT" 'BEGIN{print (x>=90)?0:1}')" "${CAPT} %"

# ---------- Format, memory, stability ----------------------------------------
echo; echo "▶ Format, memory and stability"
BADL=$(jq -cR '(fromjson? // null) | select(. == null or (has("ts") and has("pid") and has("rule") and (.level|IN("info","warn","alert"))) == false)' "$OUT" | wc -l)
TOTL=$(wc -l <"$OUT")
result T4 F4 5 "stdout is valid JSON Lines ($TOTL lines)" "$([[ $BADL -eq 0 && $TOTL -gt 0 ]] && echo 0 || echo 1)" "$BADL invalid line(s)"
gresult P1 perf 4 "idle CPU < 1 %" "$(awk -v x="$IDLE" 'BEGIN{print (x<1)?0:1}')" "${IDLE} %"
MB=$(awk -v k="$MAXRSS" 'BEGIN{printf "%.1f", k/1024}')
gresult P2 perf 4 "peak RAM < 30 MB" "$(awk -v x="$MB" 'BEGIN{print (x>0 && x<30)?0:1}')" "${MB} MB"
alive; gresult P5 perf 2 "agent still alive at the end" $?

# ---------- Summary ----------------------------------------------------------
FINAL=$((SCORE + BONUS)); (( FINAL > TOTAL )) && FINAL=$TOTAL
echo
echo "════════════════════════════════════════════"
printf '  Score: %d / %d  (+%d bonus → %d / %d)  ·  %d failure(s)\n' "$SCORE" "$TOTAL" "$BONUS" "$FINAL" "$TOTAL" "$FAILED"
for c in F1 F2 F3 F4 scenarios perf; do printf '    %-10s %2d / %2d\n' "$c" "${CAT_S[$c]:-0}" "${CAT_T[$c]:-0}"; done
NOTE=$(awk -v s="$FINAL" -v t="$TOTAL" 'BEGIN{printf "%.1f", s*16/t}')
echo "  Automatic grade: $NOTE / 16  (+ 4 points at the oral)"
echo "  Report: $REPORT"
echo "════════════════════════════════════════════"
{ echo; echo "**Score: $SCORE / $TOTAL, bonus +$BONUS, final $FINAL / $TOTAL — automatic grade $NOTE / 16**"; echo;
  echo "Idle CPU: ${IDLE} % · CPU under load: ${LOAD} % (~$RATE exec/s) · capture: ${CAPT} % · peak RAM: ${MB} MB"; } >>"$REPORT"
[[ $FAILED -eq 0 ]]
