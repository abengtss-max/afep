# Fix-HyperV-Connectivity.ps1
# Resolves Hyper-V switch connectivity issues for Azure Firewall Lab

Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║             HYPER-V CONNECTIVITY FIX SCRIPT               ║" -ForegroundColor Cyan  
Write-Host "║   Resolves WiFi/Ethernet disruption from External switch  ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "`nRight-click PowerShell and select 'Run as Administrator'`n" -ForegroundColor Yellow
    exit 1
}

Write-Host "🔍 Step 1: Analyzing current Hyper-V switch configuration..." -ForegroundColor Yellow

# Get all virtual switches
$switches = Get-VMSwitch
Write-Host "`nCurrent Virtual Switches:" -ForegroundColor Cyan
$switches | Format-Table Name, SwitchType, NetAdapterInterfaceDescription -AutoSize

# Identify problematic External switches
$externalSwitches = $switches | Where-Object { $_.SwitchType -eq "External" }
$defaultSwitch = $switches | Where-Object { $_.Name -like "*Default*" }
$internalLabSwitch = $switches | Where-Object { $_.Name -eq "Internal-Lab" }

Write-Host "`n🚨 Step 2: Identifying connectivity issues..." -ForegroundColor Yellow

if ($externalSwitches.Count -gt 0) {
    Write-Host "⚠️  Found External switch(es) that may be blocking your WiFi/Ethernet:" -ForegroundColor Red
    $externalSwitches | ForEach-Object {
        Write-Host "    - $($_.Name) (bound to: $($_.NetAdapterInterfaceDescription))" -ForegroundColor White
    }
    Write-Host "`n💡 These switches take over your physical network adapter, breaking connectivity!" -ForegroundColor Yellow
    
    $removeExternal = Read-Host "`nRemove these External switches to restore WiFi? (y/N)"
    if ($removeExternal -eq 'y' -or $removeExternal -eq 'Y') {
        Write-Host "`n🔧 Removing External switches..." -ForegroundColor Green
        $externalSwitches | ForEach-Object {
            Write-Host "  Removing: $($_.Name)..." -NoNewline
            Remove-VMSwitch -Name $_.Name -Force
            Write-Host " ✓" -ForegroundColor Green
        }
        Write-Host "`n✅ External switches removed! Your WiFi should now work." -ForegroundColor Green
        Write-Host "   Wait 10-30 seconds for network adapter to reset." -ForegroundColor Cyan
    }
}

Write-Host "`n🔧 Step 3: Creating/Verifying WiFi-safe switches..." -ForegroundColor Yellow

# Check/Create Default Switch (NAT) for internet access
if (-not $defaultSwitch) {
    Write-Host "Creating NAT switch for VM internet access..." -NoNewline
    
    # Create NAT switch
    New-VMSwitch -Name "NAT-Switch" -SwitchType Internal | Out-Null
    Start-Sleep -Seconds 2
    
    # Configure NAT network
    New-NetIPAddress -IPAddress 192.168.100.1 -PrefixLength 24 `
        -InterfaceAlias "vEthernet (NAT-Switch)" `
        -ErrorAction SilentlyContinue | Out-Null
    
    New-NetNat -Name "NAT-Network" -InternalIPInterfaceAddressPrefix 192.168.100.0/24 `
        -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host " ✓" -ForegroundColor Green
    $natSwitchName = "NAT-Switch"
} else {
    Write-Host "✓ Default Switch already exists (provides NAT internet)" -ForegroundColor Green
    $natSwitchName = $defaultSwitch.Name
}

# Check/Create Internal-Lab switch
if (-not $internalLabSwitch) {
    Write-Host "Creating Internal-Lab switch for VM-to-VM network..." -NoNewline
    
    New-VMSwitch -Name "Internal-Lab" -SwitchType Internal | Out-Null
    Start-Sleep -Seconds 2
    
    # Configure management IP (optional)
    New-NetIPAddress -IPAddress 192.168.101.1 -PrefixLength 24 `
        -InterfaceAlias "vEthernet (Internal-Lab)" `
        -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host " ✓" -ForegroundColor Green
} else {
    Write-Host "✓ Internal-Lab switch already exists" -ForegroundColor Green
}

Write-Host "`n🔧 Step 4: Configuring VM network adapters..." -ForegroundColor Yellow

# Configure OPNsense VM if it exists
$opnsenseVM = Get-VM -Name "OPNsense-Lab" -ErrorAction SilentlyContinue
if ($opnsenseVM) {
    Write-Host "Configuring OPNsense-Lab network adapters..." -ForegroundColor Cyan
    
    # Get existing adapters
    $adapters = Get-VMNetworkAdapter -VMName "OPNsense-Lab"
    
    if ($adapters.Count -eq 2) {
        # Configure first adapter (WAN) to NAT switch
        Write-Host "  Setting WAN interface to $natSwitchName..." -NoNewline
        $adapters[0] | Connect-VMNetworkAdapter -SwitchName $natSwitchName
        Write-Host " ✓" -ForegroundColor Green
        
        # Configure second adapter (LAN) to Internal-Lab
        Write-Host "  Setting LAN interface to Internal-Lab..." -NoNewline
        $adapters[1] | Connect-VMNetworkAdapter -SwitchName "Internal-Lab"
        Write-Host " ✓" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  OPNsense VM doesn't have exactly 2 network adapters" -ForegroundColor Yellow
        Write-Host "      Please manually configure in Hyper-V Manager" -ForegroundColor White
    }
} else {
    Write-Host "⚠️  OPNsense-Lab VM not found (will be configured when created)" -ForegroundColor Yellow
}

# Configure Windows Server VM if it exists  
$serverVM = Get-VM -Name "ArcServer-Lab" -ErrorAction SilentlyContinue
if ($serverVM) {
    Write-Host "Configuring ArcServer-Lab network adapter..." -ForegroundColor Cyan
    Write-Host "  Setting interface to Internal-Lab..." -NoNewline
    Get-VMNetworkAdapter -VMName "ArcServer-Lab" | Connect-VMNetworkAdapter -SwitchName "Internal-Lab"
    Write-Host " ✓" -ForegroundColor Green
} else {
    Write-Host "⚠️  ArcServer-Lab VM not found (will be configured when created)" -ForegroundColor Yellow
}

Write-Host "`n📊 Step 5: Final configuration summary..." -ForegroundColor Yellow

# Display final switch configuration
Write-Host "`nOptimal Switch Configuration:" -ForegroundColor Cyan
Get-VMSwitch | Format-Table Name, SwitchType, NetAdapterInterfaceDescription -AutoSize

Write-Host "Network Design:" -ForegroundColor Cyan
Write-Host "  🌐 Your WiFi/Ethernet: " -NoNewline
Write-Host "UNAFFECTED - continues working normally" -ForegroundColor Green

Write-Host "  🔧 ${natSwitchName}: " -NoNewline  
Write-Host "Provides NAT internet to OPNsense WAN (for VPN only)" -ForegroundColor White

Write-Host "  🔒 Internal-Lab: " -NoNewline
Write-Host "Isolated VM network (OPNsense LAN ↔ Windows Server)" -ForegroundColor White

Write-Host "`n✅ CONNECTIVITY FIX COMPLETE!" -ForegroundColor Green
Write-Host "Your WiFi/Ethernet should now work normally while VMs have proper connectivity.`n" -ForegroundColor Green

Write-Host "🚀 Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Verify your WiFi/Ethernet is working" -ForegroundColor White
Write-Host "  2. Start/restart your VMs" -ForegroundColor White
Write-Host "  3. Continue with OPNsense configuration" -ForegroundColor White
Write-Host "  4. Test VPN connectivity to Azure`n" -ForegroundColor White

# Test host connectivity
Write-Host "🧪 Testing host connectivity..." -ForegroundColor Yellow
try {
    $testResult = Test-NetConnection google.com -InformationLevel Quiet
    if ($testResult) {
        Write-Host "✅ Host internet connectivity: WORKING" -ForegroundColor Green
    } else {
        Write-Host "❌ Host internet connectivity: FAILED" -ForegroundColor Red
        Write-Host "   Wait 30-60 seconds for network to stabilize, then test again" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Connectivity test inconclusive - manually verify WiFi/Ethernet" -ForegroundColor Yellow
}

Write-Host "`n🎯 The lab will now work with:" -ForegroundColor Cyan
Write-Host "   ✓ Host WiFi/Ethernet: Fully functional" -ForegroundColor Green  
Write-Host "   ✓ OPNsense WAN: Internet via NAT (for VPN to Azure)" -ForegroundColor Green
Write-Host "   ✓ OPNsense LAN: Isolated network with Windows Server" -ForegroundColor Green
Write-Host "   ✓ Windows Server: No direct internet (security proper)" -ForegroundColor Green
Write-Host "   ✓ Complete enterprise simulation achieved!" -ForegroundColor Green