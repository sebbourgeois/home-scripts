#!/usr/bin/env bash
# fix-nordlayer-lan.sh (v3 - pretty output)
# Re-route local LAN outside NordLayer (full-tunnel) on Ubuntu 24.04.

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
    | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1)} }' \
    | grep -vE '^(tun|wg|nord|nlx|nordlynx)' \
    | head -n1)"
  [[ -n "${iface}" ]] && echo "${iface}" || return 1
}

# --- Detect gateway for that interface ---
detect_gw(){
  local iface="$1"
  ip -4 route show default dev "$iface" 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1
}

# --- Detect LAN subnet/CIDR on that interface ---
detect_cidr(){
  local iface="$1"
  ip -4 route show dev "$iface" | awk '/proto kernel/ && /scope link/ {print $1; exit}'
}

# --- Detect highest-priority VPN rule ---
detect_vpn_pref(){
  ip rule | awk '/nord|nordlynx|nlx|vpn|tun|wg|table [0-9]+/ {gsub(":","",$1); if(!m||$1<m)m=$1} END{if(m)print m}'
}

main(){
  local iface gw cidr

  iface="$(detect_iface)" || { err "Could not detect a suitable LAN interface. Pass it explicitly, e.g.: sudo bash $0 wlp4s0"; exit 1; }
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

  # Remove any existing lan rules
  while read -r pref; do
    [[ -n "$pref" ]] && ip rule del pref "$pref" || true
  done < <(ip rule list | awk '/lookup lan/ {print $1}' | tr -d ':')

  # Add routes to table lan (CIDR + GW)
  ip route replace "$cidr"  dev "$iface" table lan
  ip route replace "$gw"/32 dev "$iface" table lan
  log "Installed route: table lan -> $cidr dev $iface"
  log "Installed route: table lan -> $gw/32 dev $iface"

  # Find NordLayer’s smallest pref and add ours just before
  local nlpref pref gwpref
  nlpref="$(detect_vpn_pref || true)"
  if [[ -n "${nlpref:-}" && "$nlpref" -gt 2 ]]; then
    pref=$((nlpref-1))
    gwpref=$((pref-1))
  else
    pref=3; gwpref=2
  fi
  log "Calculated rule priorities: LAN=$pref, GW=$gwpref"

  # Add our rules
  ip rule add to "$gw"/32 lookup lan pref "$gwpref" 2>/dev/null || true
  ip rule add to "$cidr"  lookup lan pref "$pref"   2>/dev/null || true
  log "Added policy rule: pref $pref to $cidr lookup lan"

  # Flush route cache (important)
  ip route flush cache

  # Verify routing
  log "Routing decision for router:"
  ip -4 route get "$gw" || true

  # Bound ping test
  if command -v ping >/dev/null 2>&1; then
    log "Pinging gateway via ${iface} (1 probe)..."
    if ping -I "$iface" -c 1 -W 1 "$gw" >/dev/null 2>&1; then
      log "✅ Gateway reachable over ${iface}. LAN bypass should be working."
    else
      err "Gateway ping failed via ${iface}. Check Wi-Fi/LAN reachability or VPN policy."
    fi
  fi
}

main "$@"
