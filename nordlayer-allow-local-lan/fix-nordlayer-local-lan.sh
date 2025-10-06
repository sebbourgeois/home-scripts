#!/usr/bin/env bash
# fix-nordlayer-lan.sh (v2)
set -euo pipefail
log(){ echo "[*] $*"; }
err(){ echo "[!] $*" >&2; }

need_root(){ if [[ $EUID -ne 0 ]]; then exec sudo -E bash "$0" "${IFACE_ARG:-}"; fi; }
IFACE_ARG="${1:-}"

detect_iface(){
  [[ -n "${IFACE_ARG}" ]] && { echo "$IFACE_ARG"; return; }
  local i
  i="$(ip -4 route show default | awk '{for(j=1;j<=NF;j++) if($j=="dev") print $(j+1)}' | grep -vE '^(tun|wg|nord)' | head -n1)"
  [[ -n "$i" ]] && { echo "$i"; return; }
  i="$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}')"
  [[ -n "$i" ]] && echo "$i" || return 1
}

detect_gw(){ ip -4 route show default dev "$1" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1; }
detect_cidr(){ ip -4 route show dev "$1" | awk '/proto kernel/ && /scope link/ {print $1; exit}'; }

min_vpn_pref(){
  ip rule | awk '
    /nord|nordlynx|vpn|tun|wg|table [0-9]+/ {
      gsub(":","",$1); if(!m || $1<m) m=$1
    }
    END{if(m) print m}'
}

main(){
  local iface gw cidr
  iface="$(detect_iface)" || { err "Could not detect LAN interface; pass it explicitly (e.g. wlp4s0)."; exit 1; }
  gw="$(detect_gw "$iface")" || { err "No default gateway on $iface"; exit 1; }
  cidr="$(detect_cidr "$iface")" || { err "No kernel-connected CIDR on $iface"; exit 1; }
  log "IFACE=$iface  CIDR=$cidr  GW=$gw"

  need_root

  grep -qE '^[[:space:]]*100[[:space:]]+lan([[:space:]]+|$)' /etc/iproute2/rt_tables || { echo '100 lan' >> /etc/iproute2/rt_tables; log "Added rt_table 'lan'"; }

  # Clean any previous 'lan' rules for our CIDR/GW
  ip rule | awk -v c="$cidr" '$0 ~ c && /lookup lan/ {gsub(":","",$1); print $1}' | while read -r p; do ip rule del pref "$p"; done || true
  ip rule | awk -v g="$gw"   '$0 ~ g && /lookup lan/ {gsub(":","",$1); print $1}' | while read -r p; do ip rule del pref "$p"; done || true

  # Install dynamic routes in 'lan' table (no src pinning)
  ip route replace "$cidr" dev "$iface" table lan
  ip route replace "$gw"/32 dev "$iface" table lan

  local nlpref pref
  nlpref="$(min_vpn_pref || true)"
  if [[ -n "${nlpref:-}" && "$nlpref" -gt 1 ]]; then
    pref=$((nlpref-1))
  else
    pref=5
  fi
  log "Using rule priority pref=$pref (smaller = higher priority than VPN)"

  ip rule add to "$cidr" lookup lan pref "$pref"        2>/dev/null || true
  ip rule add to "$gw"/32 lookup lan pref $((pref-1))   2>/dev/null || true

  echo "---- STATUS ----"
  ip rule | nl | sed -n '1,25p'
  echo "route get GW:"; ip -4 route get "$gw" || true
  test_ip="$(echo "$cidr" | awk -F'[./]' '{print $1"."$2"."$3".1"}')"
  echo "route get $test_ip:"; ip -4 route get "$test_ip" || true
  if command -v ping >/dev/null; then
    echo "ping -I $iface $gw:"; ping -I "$iface" -c 2 -W 1 "$gw" || true
  fi
}
main "$@"
