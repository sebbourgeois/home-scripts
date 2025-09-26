#!/usr/bin/env bash
# fix-nordlayer-lan.sh
# Re-route local LAN outside NordLayer (full-tunnel) on Ubuntu 24.04.
# Optional arg: interface name (e.g., wlp4s0). If omitted, auto-detects.

set -euo pipefail

log(){ echo -e "[*] $*"; }
err(){ echo -e "[!] $*" >&2; }
need_root(){
  if [[ $EUID -ne 0 ]]; then
    log "Elevating with sudo..."
    exec sudo -E bash "$0" "${IFACE_ARG:-}"
  fi
}

IFACE_ARG="${1:-}"

# --- Detect Wi-Fi interface ---
detect_iface(){
  local iface="$IFACE_ARG"

  # 1) If arg provided, trust it
  if [[ -n "${iface}" ]]; then
    echo "${iface}"
    return
  fi

  # 2) Try 'iw' (wireless interface)
  if command -v iw >/dev/null 2>&1; then
    iface="$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}')"
    if [[ -n "${iface}" ]]; then
      echo "${iface}"
      return
    fi
  fi

  # 3) Fallback: pick default route that's NOT tun/wg/nord
  iface="$(ip -4 route show default \
    | awk '{
        for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1)}
      }' \
    | grep -vE '^(tun|wg|nord|nordlynx)' \
    | head -n1)"
  if [[ -n "${iface}" ]]; then
    echo "${iface}"
    return
  fi

  return 1
}

# --- Detect gateway for that interface ---
detect_gw(){
  local iface="$1"
  local gw

  # Prefer default via this iface
  gw="$(ip -4 route show default dev "$iface" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1)"
  if [[ -z "${gw}" ]]; then
    # Try any default line that mentions the iface
    gw="$(ip -4 route show default | awk -v d="$iface" '$0 ~ ("dev " d) {for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1)"
  fi
  [[ -n "${gw}" ]] && echo "${gw}" || return 1
}

# --- Detect LAN subnet/CIDR on that interface ---
detect_cidr(){
  local iface="$1"
  # Kernel-populated connected route (scope link) carries the CIDR we need
  ip -4 route show dev "$iface" \
    | awk '/proto kernel/ && /scope link/ {print $1; exit}'
}

main(){
  local iface gw cidr

  iface="$(detect_iface)" || { err "Could not detect a suitable LAN interface. Pass it explicitly, e.g.:  sudo bash $0 wlp4s0"; exit 1; }
  log "Using interface: ${iface}"

  gw="$(detect_gw "$iface")" || { err "Could not detect default gateway for ${iface}."; exit 1; }
  log "Detected gateway: ${gw}"

  cidr="$(detect_cidr "$iface")" || { err "Could not detect LAN CIDR on ${iface}."; exit 1; }
  log "Detected LAN CIDR: ${cidr}"

  need_root

  # Ensure custom routing table exists
  if ! grep -qE '^[[:space:]]*100[[:space:]]+lan([[:space:]]+|$)' /etc/iproute2/rt_tables 2>/dev/null; then
    echo '100 lan' >> /etc/iproute2/rt_tables
    log "Added table 'lan' (100) to /etc/iproute2/rt_tables"
  else
    log "Routing table 'lan' already present"
  fi

  # Clean up any prior lan rules (regardless of pref)
  while read -r pref; do
    [[ -n "$pref" ]] && ip rule del pref "$pref" || true
  done < <(ip rule list | awk '/lookup lan/ {print $1}' | tr -d ':')

  # Install dynamic route (no fixed src) in 'lan' table
  ip route replace "$cidr" dev "$iface" table lan
  log "Installed route: table lan -> $cidr dev $iface"

  # Add a high-priority rule so LAN traffic hits 'lan' table before VPN rules
  # 50 is typically well before VPN/NM rules and after kernel-reserved 0/32766/32767.
  if ! ip rule list | grep -q "to $cidr .* lookup lan"; then
    ip rule add to "$cidr" lookup lan pref 50
    log "Added policy rule: pref 50 to $cidr lookup lan"
  else
    log "Policy rule already present"
  fi

  # Quick verification
  log "Routing decision for router:"
  ip -4 route get "$gw" || true

  # Try an interface-bound ping (does not rely on current default table)
  if command -v ping >/dev/null 2>&1; then
    log "Pinging gateway via ${iface} (1 probe)..."
    if ping -I "$iface" -c 1 -W 1 "$gw" >/dev/null 2>&1; then
      log "✅ Gateway reachable over ${iface}. LAN bypass should be working."
    else
      err "Gateway ping failed via ${iface}. Check Wi-Fi/LAN reachability and org policy (Local Network Access)."
    fi
  fi
}

main "$@"
