#Requires -RunAsAdministrator
# fix-nordlayer-local-lan.ps1
# Re-route local LAN outside NordLayer (full-tunnel) on Windows.
# Optional arg: interface alias (e.g., "Wi-Fi" or "Ethernet"). If omitted, auto-detects.

param(
    [string]$InterfaceAlias = ""
)

function Write-Log {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Green
}

function Write-Error-Log {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Red
}

function Detect-Interface {
    param([string]$ExplicitAlias)

    # 1) If explicit alias provided, use it
    if ($ExplicitAlias -ne "") {
        return $ExplicitAlias
    }

    # 2) Try to find Wi-Fi interface first
    $wifi = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and
        $_.InterfaceDescription -match "Wi-Fi|Wireless|802.11"
    } | Select-Object -First 1

    if ($wifi) {
        return $wifi.Name
    }

    # 3) Fallback: find any active non-VPN interface
    $iface = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and
        $_.InterfaceDescription -notmatch "NordLynx|WireGuard|TAP-Windows|VPN|Tunnel"
    } | Select-Object -First 1

    if ($iface) {
        return $iface.Name
    }

    throw "Could not detect a suitable LAN interface. Pass it explicitly, e.g.: .\fix-nordlayer-local-lan.ps1 'Wi-Fi'"
}

function Detect-Gateway {
    param([string]$InterfaceAlias)

    $route = Get-NetRoute -InterfaceAlias $InterfaceAlias -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($route -and $route.NextHop -ne "0.0.0.0") {
        return $route.NextHop
    }

    throw "Could not detect default gateway for interface: $InterfaceAlias"
}

function Detect-CIDR {
    param([string]$InterfaceAlias)

    $adapter = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($adapter) {
        $ip = $adapter.IPAddress
        $prefix = $adapter.PrefixLength

        # Calculate network address
        $ipBytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
        $maskBytes = [System.Net.IPAddress]::Parse("255.255.255.255").GetAddressBytes()

        # Create subnet mask from prefix length
        $mask = ([uint32]0xFFFFFFFF) -shl (32 - $prefix)
        $maskBytes = [System.BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder([int64]$mask -shr 32))

        $networkBytes = @()
        for ($i = 0; $i -lt 4; $i++) {
            $networkBytes += $ipBytes[$i] -band $maskBytes[$i]
        }

        $network = "$($networkBytes[0]).$($networkBytes[1]).$($networkBytes[2]).$($networkBytes[3])"
        return "$network/$prefix"
    }

    throw "Could not detect LAN CIDR on interface: $InterfaceAlias"
}

function Main {
    try {
        $iface = Detect-Interface -ExplicitAlias $InterfaceAlias
        Write-Log "Using interface: $iface"

        $gw = Detect-Gateway -InterfaceAlias $iface
        Write-Log "Detected gateway: $gw"

        $cidr = Detect-CIDR -InterfaceAlias $iface
        Write-Log "Detected LAN CIDR: $cidr"

        $ifaceIndex = (Get-NetAdapter -Name $iface).InterfaceIndex

        # Remove any existing routes for this CIDR with metric 5
        $existingRoutes = Get-NetRoute -DestinationPrefix $cidr -ErrorAction SilentlyContinue | Where-Object {
            $_.RouteMetric -eq 5
        }

        foreach ($route in $existingRoutes) {
            Remove-NetRoute -DestinationPrefix $route.DestinationPrefix -InterfaceIndex $route.InterfaceIndex -NextHop $route.NextHop -Confirm:$false -ErrorAction SilentlyContinue
        }

        # Add a high-priority route (low metric = 5) for LAN traffic
        # This takes precedence over VPN routes which typically have higher metrics (30+)
        $existingRoute = Get-NetRoute -DestinationPrefix $cidr -InterfaceIndex $ifaceIndex -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($existingRoute) {
            Set-NetRoute -DestinationPrefix $cidr -InterfaceIndex $ifaceIndex -NextHop $gw -RouteMetric 5 -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Updated route: $cidr via $gw (metric 5)"
        } else {
            New-NetRoute -DestinationPrefix $cidr -InterfaceIndex $ifaceIndex -NextHop $gw -RouteMetric 5 -ErrorAction Stop
            Write-Log "Added route: $cidr via $gw (metric 5)"
        }

        # Verify connectivity
        Write-Log "Testing gateway connectivity..."
        $ping = Test-Connection -ComputerName $gw -Count 1 -Quiet

        if ($ping) {
            Write-Log "✅ Gateway reachable via $iface. LAN bypass should be working."
        } else {
            Write-Error-Log "Gateway ping failed. Check network connectivity and NordLayer policy (Local Network Access)."
        }

        # Show routing decision
        Write-Log "Route for gateway $gw`:"
        Find-NetRoute -RemoteIPAddress $gw | Format-Table -Property DestinationPrefix, NextHop, RouteMetric, InterfaceAlias

    } catch {
        Write-Error-Log $_.Exception.Message
        exit 1
    }
}

Main
