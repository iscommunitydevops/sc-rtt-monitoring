#!/usr/bin/env bash
set -euo pipefail

# --- Utility: log helpers ---
log()  { printf "[entrypoint] %s\n" "$*"; }
err()  { printf "[entrypoint:ERROR] %s\n" "$*" >&2; }

TELEGRAF_ETC="/etc/telegraf"
TELEGRAF_D="${TELEGRAF_ETC}/telegraf.d"
CONFIG_DIR="${TELEGRAF_D}"
LOG_DIR="/var/log/telegraf"
ENV_FILE="/config/netprobe.env"   # optional bind-mounted .env

mkdir -p "${CONFIG_DIR}" "${LOG_DIR}"

# --- Merge .env (if present) into environment ---
if [[ -f "${ENV_FILE}" ]]; then
  log "Loading overrides from ${ENV_FILE}"
  while IFS='=' read -r key val; do
    [[ -z "${key}" ]] && continue
    [[ "${key}" =~ ^\# ]] && continue
    key="$(echo -n "${key}" | xargs)"
    val="$(echo -n "${val}" | sed 's/^ *//;s/ *$//')"
    export "${key}=${val}"
  done < <(grep -v '^[[:space:]]*$' "${ENV_FILE}" 2>/dev/null || true)
else
  log "No ${ENV_FILE} present; skipping env overrides"
fi

# ---------------- Core env (authoritative = fping2influx.sh) ----------------
: "${HOSTS:=1.1.1.1,8.8.8.8,cloudflare.com}"  # what to ping (script reads HOSTS)
: "${INTERVAL_MS:=200}"                       # generic ms knob (script fallback)
: "${F_INTERVAL_MS:=${INTERVAL_MS}}"         # fping period (ms) if script uses it
: "${ICMP_TIMEOUT_MS:=1000}"                 # fping -t <ms>

# Telegraf agent cadence for running the script (string like "10s")
: "${TELEGRAF_INTERVAL:=10s}"

# Derived vars for telegraf.conf (string formats)
export ICMP_INTERVAL="${TELEGRAF_INTERVAL}"
export ICMP_TIMEOUT="${ICMP_TIMEOUT_MS}ms"

# ---------------- Output file & permissions ----------------
OUTPUT_FILE="${OUTPUT_FILE:-${LOG_DIR}/netprobe_metrics.out}"
mkdir -p "${LOG_DIR}"
: > "${OUTPUT_FILE}" || true
chown -R telegraf:telegraf "${LOG_DIR}" || true
chmod 775 "${LOG_DIR}" || true
chmod 664 "${OUTPUT_FILE}" || true

# ---------------- Telegraf input (exec) ----------------
INPUT_FILE="${CONFIG_DIR}/00-input-icmp.conf"
cat > "${INPUT_FILE}" <<'CONF'
[[inputs.exec]]
  commands = ["/opt/netprobe/scripts/fping2influx.sh"]
  interval = "${ICMP_INTERVAL}"
  timeout  = "${ICMP_TIMEOUT}"
  data_format = "influx"
  name_override = "netprobe_icmp"
CONF

# ---------------- Telegraf output (file by default) ----------------
OUTPUT_FILE_CONF="${CONFIG_DIR}/99-output-file.conf"
cat > "${OUTPUT_FILE_CONF}" <<CONF
[[outputs.file]]
  files = ["${OUTPUT_FILE}"]
  influx_sort_fields = true
  data_format = "influx"
CONF

# ---------------- Telegraf output (file by default) ----------------
OUTPUT_FILE_CONF="${CONFIG_DIR}/98-output-influx.conf"
cat > "${OUTPUT_FILE_CONF}" <<CONF
[[outputs.influxdb_v2]]
  urls = ["${INFLUX_URL}"]
  token = "${INFLUX_TOKEN}"
  organization = "${INFLUX_ORG}"
  bucket = "${INFLUX_BUCKET}"
CONF

# ---------------- Show effective config ----------------
log "Effective (script) env:"
log "  HOSTS=${HOSTS}"
log "  INTERVAL_MS=${INTERVAL_MS}   F_INTERVAL_MS=${F_INTERVAL_MS}"
log "  ICMP_TIMEOUT_MS=${ICMP_TIMEOUT_MS}"
log "Derived (telegraf) env:"
log "  ICMP_INTERVAL=${ICMP_INTERVAL}   ICMP_TIMEOUT=${ICMP_TIMEOUT}"
log "  OUTPUT_FILE=${OUTPUT_FILE}"

# ---------------- Set default route via EGRESS_GATEWAY ----------------
if command -v ip >/dev/null 2>&1; then
  if [[ -n "${EGRESS_GATEWAY:-}" ]]; then
    log "Setting default route via ${EGRESS_GATEWAY}"
    ip route replace default via "${EGRESS_GATEWAY}"
    ip route || true
  else
    log "EGRESS_GATEWAY not set; leaving default route unchanged"
  fi
else
  log "ip command not found; skipping route checks"
fi


if command -v telegraf >/dev/null 2>&1; then
  log "Running telegraf --test (non-fatal)..."
  if ! telegraf --config "${TELEGRAF_ETC}/telegraf.conf" \
                --config-directory "${TELEGRAF_D}" --test >/dev/null 2>&1; then
    err "telegraf --test reported issues (continuing)."
  fi
fi


if id telegraf >/dev/null 2>&1; then
  exec chroot --userspec=telegraf:telegraf / /usr/bin/telegraf --config-directory /etc/telegraf/telegraf.d
else
  exec telegraf --config-directory /etc/telegraf/telegraf.d
fi
