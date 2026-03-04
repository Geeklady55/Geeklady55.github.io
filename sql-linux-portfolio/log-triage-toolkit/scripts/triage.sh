#!/usr/bin/env bash
# triage.sh — Incident Triage Kit (evidence collector + anomaly flags)
# Author: Geeklady55
# Purpose: Collect host/service evidence quickly, flag common "bad smells",
#          and produce report.md + report.json + optional evidence bundle.
#
# Safe-by-default: Read-only collection. Writes ONLY to a local triage_* output folder.
#
# Usage:
#   bash triage.sh --since "2h"
#   bash triage.sh --since "6h" --service nginx
#   bash triage.sh --since "6h" --service nginx --bundle
#
# Notes:
# - Works best on systemd-based Linux (Ubuntu/RHEL). Falls back where possible.
# - Avoid running on prod if your org forbids evidence capture; redact secrets if needed.

set -euo pipefail

# -----------------------------
# Defaults
# -----------------------------
SINCE="2h"
SERVICE=""
BUNDLE="false"
OUTDIR=""
VERBOSE="false"

# thresholds
DISK_WARN_PCT=85
LOAD_MULT=1.50   # load1 > (cores * LOAD_MULT) => warn
TOP_PORTS_LIMIT=120

# -----------------------------
# Helpers
# -----------------------------
ts() { date +"%Y-%m-%d_%H%M%S"; }
log() { echo "[$(date +"%H:%M:%S")] $*"; }
warn() { echo "[$(date +"%H:%M:%S")] WARN: $*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
triage.sh — Incident Triage Kit

Options:
  --since "<time>"     Time window for logs (default: "2h"). Examples: "30m", "2h", "1 day ago"
  --service <name>     systemd unit name to focus on (e.g., nginx, ssh, docker)
  --bundle             Create tar.gz evidence bundle at end
  --verbose            Print extra info to stdout
  -h, --help           Show help

Examples:
  bash triage.sh --since "2h"
  bash triage.sh --since "6h" --service nginx
  bash triage.sh --since "6h" --service nginx --bundle
EOF
}

json_escape() {
  # Escape JSON special chars for a single-line string.
  # shellcheck disable=SC2001
  echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'
}

write_file() {
  # write_file <filepath> <command...>
  local f="$1"; shift
  {
    echo "### Command:"
    echo "$*"
    echo
    echo "### Output:"
    "$@" 2>&1 || true
  } > "$f"
}

append_md_section() {
  # append_md_section "Title" "file.txt"
  local title="$1"
  local file="$2"
  {
    echo
    echo "## $title"
    echo
    echo '```'
    sed -e 's/\x1b\[[0-9;]*m//g' "$file" 2>/dev/null | tail -n 120 || true
    echo '```'
  } >> "$REPORT_MD"
}

severity_add() {
  # severity_add LEVEL MESSAGE
  local lvl="$1"
  local msg="$2"
  SEVERITIES+=("$lvl|$msg")
}

# -----------------------------
# Arg parsing
# -----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      shift
      [[ $# -gt 0 ]] || die "--since requires a value"
      SINCE="$1"
      shift
      ;;
    --service)
      shift
      [[ $# -gt 0 ]] || die "--service requires a value"
      SERVICE="$1"
      shift
      ;;
    --bundle)
      BUNDLE="true"
      shift
      ;;
    --verbose)
      VERBOSE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

# -----------------------------
# Output dir + files
# -----------------------------
OUTDIR="triage_$(ts)"
mkdir -p "$OUTDIR"
mkdir -p "$OUTDIR/service" "$OUTDIR/security"

REPORT_MD="$OUTDIR/report.md"
REPORT_JSON="$OUTDIR/report.json"

touch "$REPORT_MD" "$REPORT_JSON"

log "Output directory: $OUTDIR"
log "Log window (--since): $SINCE"
[[ -n "$SERVICE" ]] && log "Service focus: $SERVICE"
[[ "$BUNDLE" == "true" ]] && log "Bundle: enabled"

# -----------------------------
# Collectors
# -----------------------------
SEVERITIES=()

collect_identity() {
  log "Collecting identity..."
  write_file "$OUTDIR/identity.txt" bash -lc '
    echo "hostname: $(hostname 2>/dev/null || true)"
    echo "date: $(date)"
    echo
    uname -a || true
    echo
    if command -v lsb_release >/dev/null 2>&1; then
      lsb_release -a 2>/dev/null || true
    else
      cat /etc/os-release 2>/dev/null || true
    fi
    echo
    uptime || true
  '
}

collect_cpu_mem_disk() {
  log "Collecting CPU/Mem/Disk..."
  write_file "$OUTDIR/cpu_mem.txt" bash -lc '
    echo "uptime/load:"
    uptime || true
    echo
    echo "top (30 lines):"
    top -b -n1 2>/dev/null | head -n 30 || true
    echo
    echo "free -m:"
    free -m 2>/dev/null || true
  '

  write_file "$OUTDIR/disk.txt" bash -lc '
    echo "df -h:"
    df -h 2>/dev/null || true
    echo
    echo "lsblk:"
    lsblk 2>/dev/null || true
  '

  if have iostat; then
    write_file "$OUTDIR/iostat.txt" iostat -xz 1 1
  else
    echo "iostat not installed (skipping)" > "$OUTDIR/iostat.txt"
  fi
}

collect_network() {
  log "Collecting network..."
  write_file "$OUTDIR/network.txt" bash -lc '
    echo "ip a:"
    ip a 2>/dev/null || true
    echo
    echo "ip r:"
    ip r 2>/dev/null || true
    echo
    echo "ss -tulpn (top):"
    ss -tulpn 2>/dev/null | head -n 120 || true
    echo
    echo "DNS:"
    if command -v resolvectl >/dev/null 2>&1; then
      resolvectl status 2>/dev/null || true
    else
      cat /etc/resolv.conf 2>/dev/null || true
    fi
  '
}

collect_kernel_logs() {
  log "Collecting kernel/dmesg tail..."
  write_file "$OUTDIR/dmesg_tail.txt" bash -lc 'dmesg -T 2>/dev/null | tail -n 200 || true'
}

collect_journal_tail() {
  log "Collecting journal tail..."
  if have journalctl; then
    write_file "$OUTDIR/journal_tail.txt" bash -lc '
      journalctl -xe --no-pager 2>/dev/null | tail -n 250 || true
    '
  else
    echo "journalctl not available (skipping)" > "$OUTDIR/journal_tail.txt"
  fi
}

collect_service() {
  [[ -n "$SERVICE" ]] || return 0
  log "Collecting service evidence for: $SERVICE"

  # systemd unit name normalization: allow passing nginx or nginx.service
  local UNIT="$SERVICE"
  if [[ "$UNIT" != *.service && "$UNIT" != *.socket && "$UNIT" != *.target ]]; then
    UNIT="${UNIT}.service"
  fi

  if have systemctl; then
    write_file "$OUTDIR/service/${SERVICE}_status.txt" bash -lc "systemctl status \"$UNIT\" --no-pager || true"
    write_file "$OUTDIR/service/${SERVICE}_show.txt" bash -lc "systemctl show \"$UNIT\" || true"
    write_file "$OUTDIR/service/${SERVICE}_recent_restarts.txt" bash -lc "systemctl show \"$UNIT\" -p NRestarts -p ExecMainStatus -p ExecMainCode -p ActiveEnterTimestamp || true"
  else
    echo "systemctl not available (skipping service status)" > "$OUTDIR/service/${SERVICE}_status.txt"
  fi

  if have journalctl; then
    write_file "$OUTDIR/service/${SERVICE}_logs.txt" bash -lc "journalctl -u \"$UNIT\" --since \"$SINCE\" --no-pager 2>/dev/null | tail -n 500 || true"
  else
    echo "journalctl not available (skipping service logs)" > "$OUTDIR/service/${SERVICE}_logs.txt"
  fi

  # Optional config checksum for nginx (and similar patterns)
  if [[ "$SERVICE" == "nginx" ]]; then
    if have nginx; then
      write_file "$OUTDIR/service/nginx_config_test.txt" nginx -t
      # checksum of primary config + conf.d if readable
      {
        echo "### Command:"
        echo "sha256sum /etc/nginx/nginx.conf /etc/nginx/conf.d/* (if readable)"
        echo
        echo "### Output:"
        (sha256sum /etc/nginx/nginx.conf 2>/dev/null || true)
        (sha256sum /etc/nginx/conf.d/* 2>/dev/null || true)
      } > "$OUTDIR/service/nginx_config_checksum.txt"
    else
      echo "nginx binary not found; skipping nginx config test/checksum" > "$OUTDIR/service/nginx_config_test.txt"
      echo "nginx binary not found; skipping checksum" > "$OUTDIR/service/nginx_config_checksum.txt"
    fi
  fi
}

collect_security_signals() {
  log "Collecting security signals..."
  # SSH failures
  if have journalctl; then
    write_file "$OUTDIR/security/ssh_failures.txt" bash -lc '
      # Try common units: ssh.service (Debian/Ubuntu), sshd.service (RHEL)
      (journalctl -u ssh.service  --since "24 hours ago" --no-pager 2>/dev/null || true) \
        | grep -Ei "failed|invalid|authentication|bad protocol|refused" | tail -n 120 || true
      (journalctl -u sshd.service --since "24 hours ago" --no-pager 2>/dev/null || true) \
        | grep -Ei "failed|invalid|authentication|bad protocol|refused" | tail -n 120 || true
    '
    write_file "$OUTDIR/security/sudo_usage.txt" bash -lc 'journalctl -t sudo --since "24 hours ago" --no-pager 2>/dev/null | tail -n 200 || true'
  else
    echo "journalctl not available; limited security capture" > "$OUTDIR/security/ssh_failures.txt"
    echo "journalctl not available; limited security capture" > "$OUTDIR/security/sudo_usage.txt"
  fi

  # Recent users / logins (best-effort)
  write_file "$OUTDIR/security/users_recent.txt" bash -lc '
    echo "Last logins (last):"
    last -n 20 2>/dev/null || true
    echo
    echo "New-ish local users (last 10 from /etc/passwd):"
    tail -n 10 /etc/passwd 2>/dev/null || true
  '
}

# -----------------------------
# Detectors (bad smells)
# -----------------------------
detect_disk_pressure() {
  # flag if any filesystem usage > DISK_WARN_PCT (ignore tmpfs/devtmpfs)
  local df_out="$OUTDIR/disk.txt"
  local hit="false"

  # Parse df -h section from our captured file (more portable to run df again)
  while read -r pct mount; do
    [[ -z "$pct" ]] && continue
    local num="${pct%%%}"
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= DISK_WARN_PCT )); then
      severity_add "HIGH" "Disk usage ${pct} on mount ${mount} (>= ${DISK_WARN_PCT}%)"
      hit="true"
    fi
  done < <(df -hP 2>/dev/null | awk 'NR>1 && $1 !~ /tmpfs|devtmpfs/ {print $5, $6}' || true)

  [[ "$hit" == "true" && "$VERBOSE" == "true" ]] && warn "Disk pressure detected"
}

detect_load_high() {
  local cores load1
  cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"

  # Compare float load1 > (cores * LOAD_MULT) using awk
  local threshold
  threshold="$(awk -v c="$cores" -v m="$LOAD_MULT" 'BEGIN{printf "%.2f", c*m}')"

  local is_high
  is_high="$(awk -v l="$load1" -v t="$threshold" 'BEGIN{print (l>t) ? 1 : 0}')"

  if [[ "$is_high" == "1" ]]; then
    severity_add "MED" "High load average: load1=${load1} (cores=${cores}, threshold≈${threshold})"
    [[ "$VERBOSE" == "true" ]] && warn "High load detected"
  fi
}

detect_oom_kills() {
  # Look for OOM kill strings in dmesg tail capture or live dmesg
  local oom="false"
  if grep -Ei "out of memory|oom-killer|Killed process" "$OUTDIR/dmesg_tail.txt" >/dev/null 2>&1; then
    oom="true"
  else
    if dmesg -T 2>/dev/null | tail -n 400 | grep -Ei "out of memory|oom-killer|Killed process" >/dev/null 2>&1; then
      oom="true"
    fi
  fi

  if [[ "$oom" == "true" ]]; then
    severity_add "HIGH" "OOM kill indicators found (dmesg)"
    [[ "$VERBOSE" == "true" ]] && warn "OOM indicators detected"
  fi
}

detect_restart_loops() {
  [[ -n "$SERVICE" ]] || return 0
  have systemctl || return 0

  local UNIT="$SERVICE"
  [[ "$UNIT" != *.service && "$UNIT" != *.socket && "$UNIT" != *.target ]] && UNIT="${UNIT}.service"

  local nrestarts
  nrestarts="$(systemctl show "$UNIT" -p NRestarts --value 2>/dev/null || echo "")"
  if [[ "$nrestarts" =~ ^[0-9]+$ ]] && (( nrestarts >= 3 )); then
    severity_add "MED" "Service ${UNIT} has NRestarts=${nrestarts} (possible restart loop)"
    [[ "$VERBOSE" == "true" ]] && warn "Restart loop suspected"
  fi
}

detect_unexpected_listeners() {
  # Basic signal: highlight listening ports; reviewers can decide if unexpected.
  # Optional: flag if privileged ports open by non-root? (best-effort)
  local listeners
  listeners="$(ss -lntup 2>/dev/null | head -n "$TOP_PORTS_LIMIT" || true)"
  echo "$listeners" > "$OUTDIR/listeners.txt"

  # If SSH is listening on nonstandard ports, mention it (example heuristic)
  if echo "$listeners" | grep -E ":22 " >/dev/null 2>&1; then
    : # normal ssh port present
  else
    if echo "$listeners" | grep -Ei "sshd" >/dev/null 2>&1; then
      severity_add "LOW" "sshd listening but not on :22 (verify if intended)"
    fi
  fi
}

detect_auth_failures_spike() {
  # If we have many ssh failure lines in 24h window, flag as suspicious
  local f="$OUTDIR/security/ssh_failures.txt"
  [[ -f "$f" ]] || return 0
  local c
  c="$(grep -cE "." "$f" 2>/dev/null || echo 0)"
  if [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 25 )); then
    severity_add "MED" "High volume of SSH/auth failure signals in last 24h (lines=${c})"
  fi
}

# -----------------------------
# Report writers
# -----------------------------
write_report_md() {
  log "Writing report.md..."
  {
    echo "# Incident Triage Report"
    echo
    echo "- Generated: $(date)"
    echo "- Output folder: \`$OUTDIR\`"
    echo "- Log window: \`$SINCE\`"
    [[ -n "$SERVICE" ]] && echo "- Service focus: \`$SERVICE\`"
    echo
    echo "## Severity Summary"
    echo
    if [[ ${#SEVERITIES[@]} -eq 0 ]]; then
      echo "- No major anomalies flagged by heuristics."
    else
      for s in "${SEVERITIES[@]}"; do
        lvl="${s%%|*}"
        msg="${s#*|}"
        echo "- **${lvl}**: ${msg}"
      done
    fi
    echo
    echo "## Quick Next Steps"
    echo
    echo "- If **HIGH** items exist: address those first (disk pressure, OOM kills, crash loops)."
    echo "- Validate service health: \`systemctl status\`, then confirm logs for errors in the window."
    echo "- Check dependencies: DNS, upstream endpoints, DB connectivity, cert expiry."
    echo
    echo "## Evidence (snippets)"
    echo
    echo "> The files in this folder contain full outputs. Below are short excerpts for quick review."
  } > "$REPORT_MD"

  append_md_section "Identity" "$OUTDIR/identity.txt"
  append_md_section "CPU / Memory" "$OUTDIR/cpu_mem.txt"
  append_md_section "Disk" "$OUTDIR/disk.txt"
  append_md_section "Network" "$OUTDIR/network.txt"
  append_md_section "dmesg tail" "$OUTDIR/dmesg_tail.txt"
  append_md_section "journal tail" "$OUTDIR/journal_tail.txt"
  append_md_section "Listening ports" "$OUTDIR/listeners.txt"

  if [[ -n "$SERVICE" ]]; then
    append_md_section "Service status (${SERVICE})" "$OUTDIR/service/${SERVICE}_status.txt"
    append_md_section "Service logs (${SERVICE}, since ${SINCE})" "$OUTDIR/service/${SERVICE}_logs.txt"
    if [[ "$SERVICE" == "nginx" ]]; then
      append_md_section "nginx -t" "$OUTDIR/service/nginx_config_test.txt"
      append_md_section "nginx config checksum" "$OUTDIR/service/nginx_config_checksum.txt"
    fi
  fi

  append_md_section "Security: SSH failure signals" "$OUTDIR/security/ssh_failures.txt"
  append_md_section "Security: sudo usage" "$OUTDIR/security/sudo_usage.txt"
}

write_report_json() {
  log "Writing report.json..."

  local host now svc
  host="$(hostname 2>/dev/null || echo "unknown")"
  now="$(date -Is 2>/dev/null || date)"
  svc="$SERVICE"

  # Build severity JSON array
  local sev_json="[]"
  if [[ ${#SEVERITIES[@]} -gt 0 ]]; then
    sev_json="["
    local first="true"
    for s in "${SEVERITIES[@]}"; do
      local lvl msg
      lvl="${s%%|*}"
      msg="${s#*|}"
      if [[ "$first" == "true" ]]; then first="false"; else sev_json+=", "; fi
      sev_json+="{\"level\":\"$(json_escape "$lvl")\",\"message\":\"$(json_escape "$msg")\"}"
    done
    sev_json+="]"
  fi

  cat > "$REPORT_JSON" <<EOF
{
  "generated_at": "$(json_escape "$now")",
  "host": "$(json_escape "$host")",
  "since": "$(json_escape "$SINCE")",
  "service": "$(json_escape "$svc")",
  "thresholds": {
    "disk_warn_pct": $DISK_WARN_PCT,
    "load_multiplier": $LOAD_MULT
  },
  "severity": $sev_json,
  "artifacts": {
    "identity": "identity.txt",
    "cpu_mem": "cpu_mem.txt",
    "disk": "disk.txt",
    "network": "network.txt",
    "listeners": "listeners.txt",
    "dmesg_tail": "dmesg_tail.txt",
    "journal_tail": "journal_tail.txt",
    "security_ssh_failures": "security/ssh_failures.txt",
    "security_sudo_usage": "security/sudo_usage.txt",
    "service_status": "$( [[ -n "$SERVICE" ]] && echo "service/${SERVICE}_status.txt" || echo "" )",
    "service_logs": "$( [[ -n "$SERVICE" ]] && echo "service/${SERVICE}_logs.txt" || echo "" )"
  }
}
EOF
}

make_bundle() {
  [[ "$BUNDLE" == "true" ]] || return 0
  log "Creating evidence bundle..."
  local bundle="${OUTDIR}.tar.gz"
  tar -czf "$bundle" "$OUTDIR" >/dev/null 2>&1 || true
  log "Bundle created: $bundle"
}

# -----------------------------
# Run
# -----------------------------
collect_identity
collect_cpu_mem_disk
collect_network
collect_kernel_logs
collect_journal_tail
collect_service
collect_security_signals

# detectors
detect_disk_pressure
detect_load_high
detect_oom_kills
detect_restart_loops
detect_unexpected_listeners
detect_auth_failures_spike

# reports
write_report_md
write_report_json
make_bundle

log "Done."
log "Report: $REPORT_MD"
log "JSON:   $REPORT_JSON"
[[ "$BUNDLE" == "true" ]] && log "Bundle: ${OUTDIR}.tar.gz"
