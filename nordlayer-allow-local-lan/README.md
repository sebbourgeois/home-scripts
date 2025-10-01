# fix-nordlayer-local-lan

Re-route your local LAN outside a NordLayer full-tunnel on Linux, Windows, and macOS. The scripts ensure traffic destined for your LAN subnet uses your local interface instead of the VPN. Your NordLayer organization must allow Local Network Access for this to work.

## Platform-Specific Scripts

- **Linux** (Ubuntu 24.04+): `fix-nordlayer-local-lan.sh` - Uses policy routing with custom routing tables
- **Windows** (10/11): `fix-nordlayer-local-lan.ps1` - Uses route metrics to prioritize LAN routes
- **macOS**: `fix-nordlayer-local-lan-macos.sh` - Uses interface-scoped routes

## Requirements

### Linux
- Ubuntu 24.04 (or similar) with `iproute2` and `sudo`.
- Optional: `iw` (interface detection) and `ping`.
- NordLayer installed and connected in full-tunnel mode.

### Windows
- Windows 10/11 with PowerShell 5.1 or later
- Administrator privileges
- NordLayer installed and connected in full-tunnel mode

### macOS
- macOS 10.15 or later
- Python 3 (usually pre-installed)
- NordLayer installed and connected in full-tunnel mode

## Install & Usage

### Linux

**Install:**
```bash
chmod +x ./fix-nordlayer-local-lan.sh
# Optional: sudo cp ./fix-nordlayer-local-lan.sh /usr/local/bin/
```

**Usage:**
```bash
sudo ./fix-nordlayer-local-lan.sh              # Auto-detect interface
sudo ./fix-nordlayer-local-lan.sh wlp4s0       # Specify interface
sudo bash -x ./fix-nordlayer-local-lan.sh      # Debug mode
```

**What it does:**
- Ensures `100 lan` exists in `/etc/iproute2/rt_tables`
- Adds/updates a route to your detected LAN CIDR in table `lan` and a policy rule with pref 50
- Verifies reachability by probing your default gateway on the chosen interface

### Windows

**Usage:**
```powershell
# Run PowerShell as Administrator
.\fix-nordlayer-local-lan.ps1                  # Auto-detect interface
.\fix-nordlayer-local-lan.ps1 "Wi-Fi"         # Specify interface
.\fix-nordlayer-local-lan.ps1 "Ethernet"      # For wired connection
```

**What it does:**
- Detects your active network interface (Wi-Fi or Ethernet)
- Adds a high-priority route (metric 5) for your LAN subnet
- Low metric ensures LAN traffic bypasses VPN routes (which typically have metrics 30+)

### macOS

**Install:**
```bash
chmod +x ./fix-nordlayer-local-lan-macos.sh
```

**Usage:**
```bash
sudo ./fix-nordlayer-local-lan-macos.sh        # Auto-detect interface
sudo ./fix-nordlayer-local-lan-macos.sh en0    # Specify interface (usually en0 for Wi-Fi)
```

**What it does:**
- Detects your active network interface (typically en0 for Wi-Fi, en1 for Ethernet)
- Adds an interface-scoped route for your LAN subnet
- Route persists until reboot or network change

**Note:** macOS routes are temporary. For persistence, you'll need to create a LaunchDaemon or network location script.

## Verify

### Linux
```bash
ip rule list | grep 'lookup lan'
ip route show table lan
ip -4 route get <gateway>
ping -I <iface> -c 1 <gateway>
```

### Windows
```powershell
Get-NetRoute | Where-Object {$_.RouteMetric -eq 5}
Find-NetRoute -RemoteIPAddress <gateway>
Test-Connection -ComputerName <gateway> -Count 1
```

### macOS
```bash
route -n get <gateway>
netstat -rn | grep <lan-subnet>
ping -c 1 <gateway>
```

## Makefile (Linux only)
- Lint: `make lint`
- Format: `make format`
- Run with an interface: `make run IFACE=wlp4s0`
- Install + enable systemd unit: `make enable-service`
- Inspect current rules/routes: `make check`

**Note:** `wlp4s0` is an example. Your system's interface may be `wlan0`, `enp3s0`, `eth0`, etc. Replace it accordingly, or omit `IFACE` to let the script auto-detect.

## Persistence

### Linux (systemd)
Create a oneshot unit so the rule is applied at boot (and after networking is up). Adjust interface/path as needed.

```ini
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

Then: `sudo systemctl daemon-reload && sudo systemctl enable --now fix-nordlayer-local-lan.service`

**Note:** Omit the interface argument in `ExecStart` to use auto-detection.

### Windows (Task Scheduler)
Create a scheduled task that runs at logon:

```powershell
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Scripts\fix-nordlayer-local-lan.ps1"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "NordLayer-LAN-Bypass" -Action $action -Trigger $trigger -Principal $principal
```

### macOS (LaunchDaemon)
Create `/Library/LaunchDaemons/com.user.nordlayer-lan-fix.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.nordlayer-lan-fix</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/fix-nordlayer-local-lan-macos.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/nordlayer-lan-fix.err</string>
    <key>StandardOutPath</key>
    <string>/tmp/nordlayer-lan-fix.out</string>
</dict>
</plist>
```

Then:
```bash
sudo cp fix-nordlayer-local-lan-macos.sh /usr/local/bin/
sudo chmod 644 /Library/LaunchDaemons/com.user.nordlayer-lan-fix.plist
sudo launchctl load /Library/LaunchDaemons/com.user.nordlayer-lan-fix.plist
```

## Cleanup

### Linux
```bash
# Remove rule and route
sudo ip rule del pref 50 || true
sudo ip route flush table lan

# Optional: remove table definition
sudo sed -i '/^100[[:space:]]*lan/d' /etc/iproute2/rt_tables
```

### Windows
```powershell
# Remove high-priority routes (metric 5)
Get-NetRoute | Where-Object {$_.RouteMetric -eq 5} | Remove-NetRoute -Confirm:$false
```

### macOS
```bash
# Remove route (replace with your LAN subnet)
sudo route -n delete -net 192.168.1.0/24
```

## Troubleshooting

### All Platforms
- If gateway ping fails, ensure the interface is up and the LAN CIDR is correctly detected
- Verify your NordLayer policy permits Local Network Access; otherwise traffic may still be forced through the tunnel
- Check that NordLayer is running in full-tunnel mode (not split-tunnel)

### Windows-Specific
- If the script fails to detect interfaces, list them with: `Get-NetAdapter | Where-Object {$_.Status -eq "Up"}`
- Run PowerShell as Administrator
- Check execution policy: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

### macOS-Specific
- If Python commands fail, ensure Python 3 is installed: `python3 --version`
- Routes are temporary and lost on network changes - use LaunchDaemon for persistence
- Check interface name with: `ifconfig` or `networksetup -listallhardwareports`
