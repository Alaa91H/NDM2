#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <ndm2-pid> <daemon-pid> <duration-seconds> <output-csv>" >&2
  exit 64
fi

ndm_pid="$1"
daemon_pid="$2"
duration="$3"
output="$4"
mkdir -p "$(dirname "$output")"
printf 'elapsed_seconds,ndm_rss_kib,ndm_cpu_percent,daemon_rss_kib,daemon_cpu_percent,protected_health\n' > "$output"
start="$(date +%s)"
while true; do
  now="$(date +%s)"
  elapsed="$((now - start))"
  (( elapsed > duration )) && break
  ndm_stats="$(ps -p "$ndm_pid" -o rss=,pcpu= 2>/dev/null | awk '{$1=$1; print}' || true)"
  daemon_stats="$(ps -p "$daemon_pid" -o rss=,pcpu= 2>/dev/null | awk '{$1=$1; print}' || true)"
  ndm_rss="$(awk '{print $1}' <<<"$ndm_stats")"
  ndm_cpu="$(awk '{print $2}' <<<"$ndm_stats")"
  daemon_rss="$(awk '{print $1}' <<<"$daemon_stats")"
  daemon_cpu="$(awk '{print $2}' <<<"$daemon_stats")"
  health="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 -H "Authorization: Bearer ${NOVA_INTEGRATION_API_TOKEN:?}" http://127.0.0.1:3199/api/downloads 2>/dev/null || true)"
  printf '%s,%s,%s,%s,%s,%s\n' "${elapsed}" "${ndm_rss:-NA}" "${ndm_cpu:-NA}" "${daemon_rss:-NA}" "${daemon_cpu:-NA}" "${health:-000}" >> "$output"
  sleep 15
done
