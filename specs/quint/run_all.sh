#!/usr/bin/env bash
# Re-run the whole verification matrix (sampled simulation, `quint run` only).
# Usage: ./run_all.sh [max-samples] [max-steps]
# Writes one counterexample trace per violated (instance, invariant) to traces/.
set -u
cd "$(dirname "$0")"
SAMPLES="${1:-10000}"
STEPS="${2:-30}"
SEED=0x5a6a   # fixed seed -> reproducible matrix
INSTANCES="ideal asIs redelivery bookFailure cancelFailure allFaults"
INVARIANTS="BR1_confirmedEndIsFullyBooked BR2_noOrphanAfterCompensation BR3_noUnrequestedBooking \
BR4_atMostOneActiveBooking BR5_displayMatchesSupplier BR6_cancelTargetsRealBooking \
BR7_endIsAllOrNothing BR8_neverStuckHoldingBookings"

quint typecheck bookHoliday.qnt >/dev/null || exit 1
quint typecheck bookHolidayInstances.qnt >/dev/null || exit 1

mkdir -p traces
rm -f traces/*.txt traces/*.md traces/*.itf.json
TMP_ITF="$(mktemp -d)"
printf "%-14s" "instance"; for inv in $INVARIANTS; do printf "%-6s" "${inv%%_*}"; done; echo
for m in $INSTANCES; do
  printf "%-14s" "$m"
  for inv in $INVARIANTS; do
    rm -f "$TMP_ITF"/*.itf.json
    out=$(quint run bookHolidayInstances.qnt --main="$m" --invariant="$inv" \
          --max-samples="$SAMPLES" --max-steps="$STEPS" --seed="$SEED" \
          --out-itf="$TMP_ITF/t_{seq}.itf.json" 2>&1)
    if echo "$out" | grep -q "\[violation\]"; then
      printf "%-6s" "✗"
      base="traces/${m}__${inv%%_*}"
      mv "$TMP_ITF/t_0.itf.json" "$base.itf.json"
      python3 summarize_trace.py "$base.itf.json" "$m / $inv" > "$base.md"
    elif echo "$out" | grep -q "\[ok\]"; then
      printf "%-6s" "✓"
    else
      printf "%-6s" "ERR"; echo "$out" > "traces/${m}__${inv%%_*}.ERR.txt"
    fi
  done
  echo
done
