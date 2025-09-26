# fix-nordlayer-local-lan.sh

Re-route your local LAN outside a NordLayer full-tunnel on Ubuntu 24.04. The script sets up a dedicated policy routing table (`lan`, id 100) and a high-priority rule so traffic destined for your LAN subnet uses your local interface instead of the VPN. Your NordLayer organization must allow Local Network Access for this to work.

## Requirements
- Ubuntu 24.04 (or similar) with `iproute2` and `sudo`.
- Optional: `iw` (interface detection) and `ping`.
- NordLayer installed and connected in full-tunnel mode.

## Install
- Run in place: `chmod +x ./fix-nordlayer-local-lan.sh`
- Optional install: `sudo cp ./fix-nordlayer-local-lan.sh /usr/local/bin/` and use `/usr/local/bin/fix-nordlayer-local-lan.sh`.

## Usage
- Auto-detect interface: `sudo ./fix-nordlayer-local-lan.sh`
- Specify interface: `sudo ./fix-nordlayer-local-lan.sh wlp4s0`
- Debug trace: `sudo bash -x ./fix-nordlayer-local-lan.sh [iface]`

What it does
- Ensures `100 lan` exists in `/etc/iproute2/rt_tables`.
- Adds/updates a route to your detected LAN CIDR in table `lan` and a policy rule with pref 50.
- Verifies reachability by probing your default gateway on the chosen interface.

## Verify
- `ip rule list | grep 'lookup lan'`
- `ip route show table lan`
- `ip -4 route get <gateway>`
- `ping -I <iface> -c 1 <gateway>`

## Makefile (optional)
- Lint: `make lint`
- Format: `make format`
- Run with an interface: `make run IFACE=wlp4s0`
- Install + enable systemd unit: `make enable-service`
- Inspect current rules/routes: `make check`

Note: `wlp4s0` is an example. Your system’s interface may be `wlan0`, `enp3s0`, `eth0`, etc. Replace it accordingly, or omit `IFACE` to let the script auto-detect.

## Run via systemd
Create a oneshot unit so the rule is applied at boot (and after networking is up). Adjust interface/path as needed.

```
# /etc/systemd/system/fix-nordlayer-local-lan.service
[Unit]
Description=Bypass local LAN outside NordLayer full-tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix-nordlayer-local-lan.sh wlp4s0
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```
Then: `sudo systemctl daemon-reload && sudo systemctl enable --now fix-nordlayer-local-lan.service`. If your interface changes (e.g., from Wi‑Fi to Ethernet), omit the argument and let the script auto-detect: set `ExecStart=/usr/local/bin/fix-nordlayer-local-lan.sh`.

Interface note: `wlp4s0` is provided as an example. Your environment may use a different device name; update `ExecStart` accordingly or rely on auto-detection by omitting the argument.

## Cleanup
To remove the rule and route temporarily: `sudo ip rule del pref 50 || true && sudo ip route flush table lan`. You may also remove `100 lan` from `/etc/iproute2/rt_tables` manually if you no longer want the table.

## Troubleshooting
- If gateway ping fails, ensure the interface is up and the LAN CIDR is correctly detected.
- Verify your NordLayer policy permits Local Network Access; otherwise traffic may still be forced through the tunnel.
