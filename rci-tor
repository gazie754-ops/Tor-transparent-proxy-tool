#!/usr/bin/env bash
#
# rci-tor – System-wide Tor transparent proxy for Kali Linux
# Author : Ertugrul Ghazi
# Org    : Red Cell Intelligence
# Version: 1.0.0
#
# WARNING: This tool is for authorised penetration testing only.
#          Read the README and test in an isolated VM before use.
#
set -euo pipefail

# ─── Metadata ────────────────────────────────────────────────────────────────
readonly VERSION="1.0.0"
readonly AUTHOR="Ertugrul Ghazi"
readonly ORG="Red Cell Intelligence"
readonly PROG="rci-tor"

# ─── Paths & constants ───────────────────────────────────────────────────────
readonly TORRC="/etc/tor/torrc"
readonly TORRC_BACKUP="/etc/tor/torrc.rci-tor.bak"
readonly TORRC_SNIPPET="/etc/tor/torrc.d/99-rci-transparent.conf"
readonly IPTABLES_BACKUP_V4="/var/lib/rci-tor/iptables.v4.bak"
readonly IPTABLES_BACKUP_V6="/var/lib/rci-tor/iptables.v6.bak"
readonly STATE_DIR="/var/lib/rci-tor"
readonly STATE_FILE="${STATE_DIR}/state"
readonly LOCK_FILE="${STATE_DIR}/lock"
readonly LOG_FILE="/var/log/rci-tor.log"

readonly TRANS_PORT=9040
readonly DNS_PORT=5353
readonly TOR_USER="debian-tor"   # Kali package user; adjust if needed

# ─── Colour helpers ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; NC=$'\e[0m'
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
fi

log()  { printf '%s [%s] %s\n' "$(date '+%F %T')" "$$" "$*" >>"$LOG_FILE"; }
info() { printf '%s[*]%s %s\n' "$BLUE" "$NC" "$*"; log "INFO: $*"; }
warn() { printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$*"; log "WARN: $*"; }
die()  { printf '%s[✗]%s %s\n' "$RED" "$NC" "$*" >&2; log "FATAL: $*"; exit 1; }
ok()   { printf '%s[✓]%s %s\n' "$GREEN" "$NC" "$*"; log "OK: $*"; }

# ─── Root check ──────────────────────────────────────────────────────────────
require_root() {
    [[ $EUID -eq 0 ]] || die "This command requires root. Re-run with: sudo $PROG $*"
}

# ─── Dependency check ────────────────────────────────────────────────────────
check_dependencies() {
    local missing=()
    command -v tor   >/dev/null 2>&1 || missing+=("tor")
    command -v curl  >/dev/null 2>&1 || missing+=("curl")
    command -v iptables >/dev/null 2>&1 || missing+=("iptables")

    if ((${#missing[@]})); then
        die "Missing dependencies: ${missing[*]}. Install with:
    sudo apt update && sudo apt install -y tor curl iptables"
    fi

    # Verify Tor user exists (package dependent)
    if ! getent passwd "$TOR_USER" >/dev/null; then
        warn "User '$TOR_USER' not found; falling back to 'tor'."
        TOR_USER="tor"
        getent passwd "$TOR_USER" >/dev/null || die "No Tor system user found (tried debian-tor, tor)."
    fi
}

# ─── Lock handling ───────────────────────────────────────────────────────────
acquire_lock() {
    mkdir -p "$STATE_DIR"
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        die "Another instance is running (lock: $LOCK_FILE). Remove it only if you are sure."
    fi
    trap 'rm -rf "$LOCK_FILE"' EXIT INT TERM
}

# ─── State helpers ───────────────────────────────────────────────────────────
write_state()   { echo "$1" >"$STATE_FILE"; }
read_state()    { [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "stopped"; }
is_active()     { [[ "$(read_state)" == "active" ]]; }

# ─── Backup / restore torrc ──────────────────────────────────────────────────
backup_torrc() {
    if [[ ! -f "${TORRC}.rci-tor.bak" ]]; then
        cp -a "$TORRC" "${TORRC}.rci-tor.bak"
        ok "Backed up torrc → ${TORRC}.rci-tor.bak"
    fi
}

restore_torrc() {
    if [[ -f "${TORRC}.rci-tor.bak" ]]; then
        cp -a "${TORRC}.rci-tor.bak" "$TORRC"
        rm -f "${TORRC}.rci-tor.bak"
        ok "Restored original torrc"
    fi
    # Remove our snippet if present
    rm -f "$TORRC_SNIPPET"
}

# ─── Backup / restore iptables ───────────────────────────────────────────────
backup_iptables() {
    mkdir -p "$STATE_DIR"
    iptables-save   >"$IPTABLES_BACKUP_V4"
    ip6tables-save  >"$IPTABLES_BACKUP_V6" 2>/dev/null || true
    ok "Backed up iptables state (v4 & v6)"
}

restore_iptables() {
    [[ -f "$IPTABLES_BACKUP_V4" ]] && iptables-restore <"$IPTABLES_BACKUP_V4" && ok "Restored IPv4 iptables"
    [[ -f "$IPTABLES_BACKUP_V6" ]] && ip6tables-restore <"$IPTABLES_BACKUP_V6" 2>/dev/null && ok "Restored IPv6 iptables" || true
    rm -f "$IPTABLES_BACKUP_V4" "$IPTABLES_BACKUP_V6"
}

# ─── Torrc snippet ───────────────────────────────────────────────────────────
write_torrc_snippet() {
    mkdir -p "$(dirname "$TORRC_SNIPPET")"
    cat >"$TORRC_SNIPPET" <<EOF
## rci-tor transparent proxy – managed by ${PROG} ${VERSION}
TransPort 127.0.0.1:${TRANS_PORT}
DNSPort 127.0.0.1:${DNS_PORT}
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
EOF
    # Ensure main torrc includes the snippet (Kali torrc uses %include /etc/tor/torrc.d/*.conf)
    if ! grep -q 'torrc.d/\*.conf' "$TORRC" 2>/dev/null; then
        printf '\n%%include %s\n' "$TORRC_SNIPPET" >>"$TORRC"
    fi
    ok "Wrote Tor transparent-proxy configuration"
}

# ─── iptables rules ──────────────────────────────────────────────────────────
apply_iptables_rules() {
    local tor_uid
    tor_uid=$(id -u "$TOR_USER")

    # ---- IPv4 ----
    # NAT table: redirect TCP & DNS to Tor, skip Tor's own traffic and loopback
    iptables -t nat -N RCI_TOR_NAT 2>/dev/null || iptables -t nat -F RCI_TOR_NAT
    iptables -t nat -A RCI_TOR_NAT -o lo -j RETURN
    iptables -t nat -A RCI_TOR_NAT -m owner --uid-owner "$tor_uid" -j RETURN
    iptables -t nat -A RCI_TOR_NAT -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
    iptables -t nat -A RCI_TOR_NAT -p tcp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
    iptables -t nat -A RCI_TOR_NAT -p tcp -j REDIRECT --to-ports "$TRANS_PORT"
    iptables -t nat -A OUTPUT -j RCI_TOR_NAT

    # Filter table: kill-switch + allow Tor + loopback
    iptables -N RCI_TOR_FILTER 2>/dev/null || iptables -F RCI_TOR_FILTER
    iptables -A RCI_TOR_FILTER -o lo -j ACCEPT
    iptables -A RCI_TOR_FILTER -m owner --uid-owner "$tor_uid" -j ACCEPT
    iptables -A RCI_TOR_FILTER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A RCI_TOR_FILTER -p udp --dport 53 -j ACCEPT   # DNS redirected later
    iptables -A RCI_TOR_FILTER -j DROP
    iptables -A OUTPUT -j RCI_TOR_FILTER

    # ---- IPv6: block everything except loopback (Tor does not route IPv6) ----
    ip6tables -N RCI_TOR_FILTER6 2>/dev/null || ip6tables -F RCI_TOR_FILTER6
    ip6tables -A RCI_TOR_FILTER6 -o lo -j ACCEPT
    ip6tables -A RCI_TOR_FILTER6 -j DROP
    ip6tables -A OUTPUT -j RCI_TOR_FILTER6

    ok "Applied IPv4 redirect & kill-switch, and IPv6 leak prevention"
}

remove_iptables_rules() {
    # IPv4
    iptables -D OUTPUT -j RCI_TOR_FILTER 2>/dev/null || true
    iptables -D OUTPUT -j RCI_TOR_NAT    2>/dev/null || true
    iptables -F RCI_TOR_FILTER           2>/dev/null || true
    iptables -X RCI_TOR_FILTER           2>/dev/null || true
    iptables -F RCI_TOR_NAT              2>/dev/null || true
    iptables -X RCI_TOR_NAT              2>/dev/null || true

    # IPv6
    ip6tables -D OUTPUT -j RCI_TOR_FILTER6 2>/dev/null || true
    ip6tables -F RCI_TOR_FILTER6           2>/dev/null || true
    ip6tables -X RCI_TOR_FILTER6           2>/dev/null || true

    ok "Removed rci-tor iptables rules"
}

# ─── Tor service helpers ─────────────────────────────────────────────────────
tor_running() {
    systemctl is-active --quiet tor 2>/dev/null
}

start_tor_service() {
    if tor_running; then
        info "Tor service already running."
    else
        systemctl start tor
        sleep 2
        tor_running || die "Tor failed to start. Check: journalctl -u tor -n 30"
        ok "Tor service started"
    fi
}

stop_tor_service() {
    if tor_running; then
        systemctl stop tor
        ok "Tor service stopped"
    else
        info "Tor service was not running."
    fi
}

# ─── Rollback on failure ─────────────────────────────────────────────────────
rollback() {
    warn "Rolling back partial changes…"
    remove_iptables_rules 2>/dev/null || true
    restore_iptables 2>/dev/null || true
    restore_torrc 2>/dev/null || true
    stop_tor_service 2>/dev/null || true
    write_state "stopped"
    die "Startup failed – system restored to previous state."
}

# ─── Safety banner ───────────────────────────────────────────────────────────
print_safety_warning() {
    cat <<EOF
${YELLOW}
╔══════════════════════════════════════════════════════════════════════════════╗
║  SAFETY WARNING – READ BEFORE CONTINUING                                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  • Changing hostname or MAC address can itself be identifying. Review      ║
║    whether it is appropriate for your engagement.                          ║
║  • Do NOT run Tor Browser alongside system-wide Tor; the two exit          ║
║    paths can conflict and weaken anonymity. Close Tor Browser first.       ║
║  • System-wide transparent proxying does NOT protect against               ║
║    applications that leak identity through their own protocols,            ║
║    accounts, or browser fingerprints.                                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
${NC}
EOF
}

# ─── Commands ────────────────────────────────────────────────────────────────
cmd_start() {
    require_root start
    check_dependencies
    acquire_lock

    if is_active; then
        die "rci-tor is already active. Run '$PROG stop' first."
    fi

    print_safety_warning

    # Backups first
    backup_torrc
    backup_iptables

    # Ensure clean state
    remove_iptables_rules 2>/dev/null || true
    write_torrc_snippet

    # Apply rules and start Tor; rollback on any failure
    trap 'rollback' ERR
    apply_iptables_rules
    start_tor_service
    trap - ERR

    write_state "active"
    ok "Tor transparent-proxy mode ENABLED."
    info "All TCP and DNS traffic is now routed through Tor."
    info "IPv6 and non‑DNS UDP are blocked to prevent leaks."
    echo
    info "Test with: $PROG verify"
}

cmd_stop() {
    require_root stop
    acquire_lock

    if ! is_active; then
        # Still attempt cleanup in case of stale state
        warn "State says stopped; running defensive cleanup."
    fi

    # Flush conntrack to drop existing cleartext flows
    if command -v conntrack >/dev/null 2>&1; then
        conntrack -F >/dev/null 2>&1 || true
    fi

    remove_iptables_rules
    restore_iptables
    restore_torrc
    stop_tor_service

    write_state "stopped"
    ok "Tor transparent-proxy mode DISABLED. Normal networking restored."
}

cmd_status() {
    require_root status

    local state tor_state rules_v4 rules_v6
    state=$(read_state)
    if tor_running; then tor_state="${GREEN}running${NC}"; else tor_state="${RED}not running${NC}"; fi

    if iptables -C OUTPUT -j RCI_TOR_FILTER 2>/dev/null; then
        rules_v4="${GREEN}present${NC}"
    else
        rules_v4="${RED}absent${NC}"
    fi

    if ip6tables -C OUTPUT -j RCI_TOR_FILTER6 2>/dev/null; then
        rules_v6="${GREEN}present${NC}"
    else
        rules_v6="${RED}absent${NC}"
    fi

    printf '\n%s rci-tor status %s\n' "$BLUE" "$NC"
    printf '  Mode (state file) : %s\n' "$state"
    printf '  Tor service       : %b\n' "$tor_state"
    printf '  IPv4 rules        : %b\n' "$rules_v4"
    printf '  IPv6 block        : %b\n' "$rules_v6"
    printf '  TransPort         : %s\n' "$TRANS_PORT"
    printf '  DNSPort           : %s\n' "$DNS_PORT"
    printf '  Tor user          : %s\n' "$TOR_USER"

    if is_active && tor_running && iptables -C OUTPUT -j RCI_TOR_FILTER 2>/dev/null; then
        ok "System is in Tor transparent-proxy mode."
    else
        warn "System is NOT fully in Tor mode."
    fi
}

cmd_ip() {
    require_root ip
    check_dependencies

    info "Fetching exit IP through Tor…"
    local json ip istor
    json=$(curl --socks5-hostname "127.0.0.1:9050" -s --max-time 15 \
               "https://check.torproject.org/api/ip" 2>/dev/null) || true

    if [[ -z "$json" ]]; then
        die "Could not reach Tor check API. Is Tor running and are rules applied?"
    fi

    ip=$(printf '%s' "$json" | sed -n 's/.*"IP":"\([^"]*\)".*/\1/p')
    istor=$(printf '%s' "$json" | sed -n 's/.*"IsTor":\([^,}]*\).*/\1/p')

    printf '\n  Exit IP : %s\n' "$ip"
    if [[ "$istor" == "true" ]]; then
        ok "Traffic IS exiting through Tor."
    else
        warn "Traffic does NOT appear to be using Tor."
    fi
}

cmd_restart() {
    require_root restart
    check_dependencies
    acquire_lock

    if ! is_active; then
        die "Tor mode is not active. Run '$PROG start' first."
    fi

    info "Restarting Tor to obtain a new circuit…"
    systemctl restart tor
    sleep 3

    if ! tor_running; then
        die "Tor failed to restart. System may be offline. Run '$PROG stop' immediately."
    fi

    ok "Tor restarted. Transparent-proxy rules remain in place."
    info "Use '$PROG ip' to see the new exit node."
}

cmd_verify() {
    require_root verify
    check_dependencies

    info "Verifying Tor connectivity via check.torproject.org…"
    local body
    body=$(curl --socks5-hostname "127.0.0.1:9050" -s --max-time 20 \
               "https://check.torproject.org/api/ip" 2>/dev/null) || true

    if [[ -z "$body" ]]; then
        die "Verification FAILED: no response from Tor check endpoint."
    fi

    local istor ip
    istor=$(printf '%s' "$body" | sed -n 's/.*"IsTor":\([^,}]*\).*/\1/p')
    ip=$(printf '%s' "$body" | sed -n 's/.*"IP":"\([^"]*\)".*/\1/p')

    if [[ "$istor" == "true" ]]; then
        ok "VERIFIED: Traffic is going through Tor."
        info "Exit IP: $ip"
        return 0
    else
        warn "NOT VERIFIED: Tor check reports IsTor=$istor (IP: $ip)."
        warn "Possible leak or Tor not active. Run '$PROG status'."
        return 1
    fi
}

cmd_version() {
    printf '%s %s\nAuthor : %s\nOrg    : %s\n' "$PROG" "$VERSION" "$AUTHOR" "$ORG"
}

cmd_help() {
    cat <<EOF
${PROG} ${VERSION} – ${ORG} / ${AUTHOR}

Usage: sudo ${PROG} <command>

Commands:
  start      Enable Tor transparent-proxy mode (TCP + DNS → Tor, IPv6/UDP blocked)
  stop       Disable Tor mode and restore original networking
  status     Show whether Tor mode, Tor service, and firewall rules are active
  ip         Show current public IP and whether it is a Tor exit
  restart    Restart Tor to obtain a new circuit (mode preserved)
  verify     Query check.torproject.org through Tor and report result
  version    Print version and author information
  help       Show this help

Dependencies: tor, curl, iptables (all ship with Kali)
Root is required for every operational command.

WARNING: Use only for authorised penetration testing. Read README.md.
EOF
}

# ─── Dispatch ────────────────────────────────────────────────────────────────
case "${1:-}" in
    start)   cmd_start   ;;
    stop)    cmd_stop    ;;
    status)  cmd_status  ;;
    ip)      cmd_ip      ;;
    restart) cmd_restart ;;
    verify)  cmd_verify  ;;
    version) cmd_version ;;
    help|--help|-h) cmd_help ;;
    *)       cmd_help; exit 1 ;;
esac