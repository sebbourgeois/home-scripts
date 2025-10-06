#!/usr/bin/env bash
# fix-nordlayer-local-lan-macos.sh
# Re-route local LAN outside NordLayer (full-tunnel) on macOS.
# Optional arg: interface name (e.g., en0). If omitted, auto-detects.

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

# --- Detect active network interface ---
detect_iface(){
  local iface="$IFACE_ARG"

  # 1) If arg provided, trust it
  if [[ -n "${iface}" ]]; then
    echo "${iface}"
    return
  fi

  # 2) Try to find Wi-Fi interface (usually en0 or en1 on macOS)
  if command -v networksetup >/dev/null 2>&1; then
    # Get list of Wi-Fi interfaces
    local wifi_iface
    wifi_iface="$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{getline; print $NF; exit}')"
    if [[ -n "${wifi_iface}" ]] && ifconfig "${wifi_iface}" 2>/dev/null | grep -q 'status: active'; then
      echo "${wifi_iface}"
      return
    fi
  fi

  # 3) Fallback: pick default route interface that's NOT utun/ipsec/nordlynx
  iface="$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')"
  if [[ -n "${iface}" ]] && [[ ! "${iface}" =~ ^(utun|ipsec|ppp|gif|stf) ]]; then
    echo "${iface}"
    return
  fi

  return 1
}

# --- Detect gateway for that interface ---
detect_gw(){
  local iface="$1"
  local gw

  # Get default gateway
  gw="$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2; exit}')"

  if [[ -z "${gw}" ]]; then
    # Try interface-specific route
    gw="$(netstat -rn -f inet 2>/dev/null | awk -v i="$iface" '$1=="default" && $NF==i {print $2; exit}')"
  fi

  [[ -n "${gw}" ]] && echo "${gw}" || return 1
}

# --- Detect LAN subnet/CIDR on that interface ---
detect_cidr(){
  local iface="$1"
  local ip mask

  # Get IP and netmask from ifconfig
  local ifconfig_out
  ifconfig_out="$(ifconfig "${iface}" 2>/dev/null | grep 'inet ')"

  ip="$(echo "${ifconfig_out}" | awk '{print $2}')"
  mask="$(echo "${ifconfig_out}" | awk '{print $4}')"

  if [[ -z "${ip}" ]] || [[ -z "${mask}" ]]; then
    return 1
  fi

  # Convert hex netmask (0xffffff00) to CIDR prefix
  local prefix
  # Remove 0x prefix if present
  mask="${mask#0x}"
  # Convert to decimal and count bits
  prefix="$(python3 -c "
mask = int('${mask}', 16)
print(bin(mask).count('1'))
" 2>/dev/null || echo "")"

  if [[ -z "${prefix}" ]]; then
    # Fallback: common /24 network
    prefix=24
  fi

  # Calculate network address
  local network
  network="$(python3 -c "
import ipaddress
ip = ipaddress.IPv4Interface('${ip}/${prefix}')
print(ip.network)
" 2>/dev/null || echo "")"

  if [[ -n "${network}" ]]; then
    echo "${network}"
  else
    # Fallback: assume /24 and calculate manually
    local net_base
    net_base="$(echo "${ip}" | awk -F. '{print $1"."$2"."$3".0"}')"
    echo "${net_base}/24"
  fi
}

main(){
  local iface gw cidr

  iface="$(detect_iface)" || { err "Could not detect a suitable LAN interface. Pass it explicitly, e.g.:  sudo bash $0 en0"; exit 1; }
  log "Using interface: ${iface}"

  gw="$(detect_gw "$iface")" || { err "Could not detect default gateway for ${iface}."; exit 1; }
  log "Detected gateway: ${gw}"

  cidr="$(detect_cidr "$iface")" || { err "Could not detect LAN CIDR on ${iface}."; exit 1; }
  log "Detected LAN CIDR: ${cidr}"

  need_root

  # On macOS, we add a high-priority static route for the LAN subnet
  # The -ifscope flag ensures the route is tied to the specific interface
  # This takes precedence over VPN routes

  # Remove any existing route for this CIDR
  route -n delete -net "${cidr}" 2>/dev/null || true

  # Add the route with interface scope
  if route -n add -net "${cidr}" -interface "${iface}" -ifscope "${iface}" 2>/dev/null; then
    log "Added route: ${cidr} via ${iface} (interface-scoped)"
  else
    # Fallback without -ifscope if not supported
    route -n add -net "${cidr}" "${gw}" 2>/dev/null || true
    log "Added route: ${cidr} via ${gw}"
  fi

  # Quick verification
  log "Routing decision for gateway:"
  route -n get "${gw}" || true

  # Try ping
  if command -v ping >/dev/null 2>&1; then
    log "Pinging gateway (1 probe)..."
    if ping -c 1 -W 1000 -b "${iface}" "${gw}" >/dev/null 2>&1 || ping -c 1 -t 1 "${gw}" >/dev/null 2>&1; then
      log "✅ Gateway reachable. LAN bypass should be working."
    else
      err "Gateway ping failed. Check network reachability and NordLayer policy (Local Network Access)."
    fi
  fi

  log ""
  log "Note: This route is temporary and will be lost on reboot or network changes."
  log "To make it persistent, consider creating a LaunchDaemon or using a network location script."
}

main "$@"
