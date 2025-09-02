#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${NETPROBE_ENV:-/etc/telegraf/netprobe.env}"
[[ -f "$ENV_FILE" ]] && set -a && . "$ENV_FILE" && set +a

hosts="${HOSTS:-}"
interval_ms="${F_INTERVAL_MS:-${INTERVAL_MS:-200}}"
t_ms="${ICMP_TIMEOUT_MS:-1000}"
count="${FPING_COUNT:-1}"
size="${FPING_SIZE:-56}"

err() { echo "netprobe,level=error msg=\"$1\""; }

if ! command -v fping >/dev/null 2>&1; then
  err "fping not found"
  exit 0
fi

if [[ -z "$hosts" ]]; then
  err "HOSTS is empty"
  exit 0
fi

mapfile -t host_arr < <(echo "$hosts" | tr ',' '\n' | awk NF)
if [[ ${#host_arr[@]} -eq 0 ]]; then
  err "HOSTS parsed to empty set"
  exit 0
fi

out="$(fping -C "${count}" -b "${size}" -p $interval_ms -q -t "${t_ms}" "${host_arr[@]}" 2>&1)" || true

while IFS= read -r line; do
  h="$(awk -F':' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); print $1}' <<<"$line")"
  val="$(awk -F':' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2}' <<<"$line")"
  if [[ -z "$h" || -z "$val" ]]; then
    continue
  fi
  if [[ "$val" == "-"* ]]; then
    echo "icmp_probe,target=${h} sent=1i,rcvd=0i,loss_pct=100,rtt_ms=0,timeout_ms=${t_ms}i,period_ms=${interval_ms}i"
  else
    rtt="$(awk '{print $1+0}' <<<"$val")"
    echo "icmp_probe,target=${h} sent=1i,rcvd=1i,loss_pct=0,rtt_ms=${rtt},timeout_ms=${t_ms}i,period_ms=${interval_ms}i"
  fi
done <<<"$out"

exit 0
