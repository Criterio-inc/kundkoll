#!/bin/bash
# Mäter vad ett kommando kostar datorn: samplar CPU och minne per process
# (whisper, Ollama, Python-röstanalysen, appen, Teams) var halva sekund medan
# kommandot kör, och skriver toppar och medel efteråt.
#
#     scripts/mat-belastning.sh <namn> <kommando …>
#
# Råsamplen hamnar i docs/matningar/<namn>.csv, så att en siffra i docs/
# alltid går att spåra till sin körning.
set -uo pipefail
cd "$(dirname "$0")/.."

NAMN="${1:?namn på mätningen}"; shift
UT="docs/matningar"; mkdir -p "$UT"
CSV="$UT/$NAMN.csv"
MONSTER='whisper-server|whisper-cli|ollama|llama-server|rostanalys|python|Kundkoll|Teams|mlx_whisper'

fritt_mb() { vm_stat | awk '/Pages free/{f=$3} /Pages speculative/{s=$3} END{printf "%d", (f+s)*16/1024}'; }
swap_mb()  { sysctl -n vm.swapusage | sed 's/.*used = \([0-9.]*\)M.*/\1/' | cut -d. -f1; }

echo "tid,fritt_mb,swap_mb,pid,cpu,rss_mb,namn" > "$CSV"
START=$(date +%s.%N)
(
  while :; do
    t=$(printf '%.1f' "$(echo "$(date +%s.%N) - $START" | bc)")
    f=$(fritt_mb); s=$(swap_mb)
    ps -axo pid,pcpu,rss,comm | grep -E "$MONSTER" | grep -v grep | \
      awk -v t="$t" -v f="$f" -v s="$s" '{printf "%s,%s,%s,%s,%s,%d,%s\n", t, f, s, $1, $2, $3/1024, $4}' | sed "s|$HOME|~|g" >> "$CSV"
    sleep 0.5
  done
) &
SAMPLARE=$!

echo "→ $NAMN: $*"
T0=$(date +%s.%N)
"$@"
KOD=$?
T1=$(date +%s.%N)
kill "$SAMPLARE" 2>/dev/null; wait "$SAMPLARE" 2>/dev/null

printf '\n== %s: %.1f s, avslutningskod %d ==\n' "$NAMN" "$(echo "$T1 - $T0" | bc)" "$KOD"
awk -F, 'NR>1 {
    n=$7; sub(/.*\//,"",n)
    if ($5>cpu[n]) cpu[n]=$5
    if ($6>rss[n]) rss[n]=$6
    sum[n]+=$5; cnt[n]++
    if ($2<fritt || fritt=="") fritt=$2
    if ($3>swap) swap=$3
  }
  END {
    printf "%-16s %8s %8s %8s\n", "process", "cpu topp", "cpu snitt", "rss topp"
    for (n in cpu) printf "%-16s %7.0f%% %7.0f%% %6d MB\n", n, cpu[n], sum[n]/cnt[n], rss[n]
    printf "minst fritt RAM: %d MB   mest swap: %d MB\n", fritt, swap
  }' "$CSV"
echo "rådata: $CSV"
exit $KOD
