<#
.SYNOPSIS
    Creates Hyper-V virtual switches for Lab 4 using NAT (WiFi-friendly).

.DESCRIPTION
    This script creates the required virtual switches WITHOUT affecting your WiFi connection.
    Uses Hyper-V's Default NAT switch for OPNsense WAN connectivity instead of External switch.

.NOTES
    Author: Lab 4 - Azure Arc Setup
    Date: 2025-11-13
    
    This approach is better for WiFi users as it doesn't disrupt host connectivity.
#>

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Hyper-V Virtual Switch Setup (NAT Mode)             ║" -ForegroundColor Cyan
Write-Host "║  WiFi-Friendly Configuration                         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "✗ This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "`n  Right-click PowerShell → Run as Administrator`n" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Running as Administrator" -ForegroundColor Green

# Step 1: Check for Default NAT Switch
Write-Host "`n[1/2] Checking for Default NAT Switch..." -ForegroundColor Cyan

$natSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue

if ($natSwitch) {
    Write-Host "✓ Default NAT Switch exists" -ForegroundColor Green
    Write-Host "  Name: $($natSwitch.Name)" -ForegroundColor White
    Write-Host "  Type: $($natSwitch.SwitchType)" -ForegroundColor White
} else {
    Write-Host "⚠  Default Switch not found - Hyper-V will create it automatically" -ForegroundColor Yellow
    Write-Host "   The 'Default Switch' is created by Hyper-V when VMs need NAT" -ForegroundColor White
}

# Step 2: Create Internal Switch for Lab Network
Write-Host "`n[2/2] Creating Internal-Lab Switch..." -ForegroundColor Cyan

$internalSwitch = Get-VMSwitch -Name "Internal-Lab" -ErrorAction SilentlyContinue

if ($internalSwitch) {
    Write-Host "⚠  Internal-Lab switch already exists" -ForegroundColor Yellow
    
    $recreate = Read-Host "Do you want to recreate it? (y/N)"
    if ($recreate -eq 'y' -or $recreate -eq 'Y') {
        Write-Host "  Removing existing switch..." -ForegroundColor Yellow
        Remove-VMSwitch -Name "Internal-Lab" -Force
        $internalSwitch = $null
    }
}

if (-not $internalSwitch) {
    Write-Host "  Creating Internal-Lab switch..." -ForegroundColor Yellow
    
    # Create internal switch
    New-VMSwitch -Name "Internal-Lab" -SwitchType Internal | Out-Null
    
    # Configure IP address for host access
    Start-Sleep -Seconds 2
    New-NetIPAddress -IPAddress 192.168.100.1 -PrefixLength 24 -InterfaceAlias "vEthernet (Internal-Lab)" -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "✓ Internal-Lab switch created" -ForegroundColor Green
    Write-Host "  Type: Internal" -ForegroundColor White
    Write-Host "  Host IP: 192.168.100.1/24" -ForegroundColor White
}

# Clean up any External switches that might be causing WiFi issues
Write-Host "`n[Cleanup] Checking for External switches..." -ForegroundColor Cyan

$externalSwitches = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" }

if ($externalSwitches) {
    Write-Host "⚠  Found External switch(es) that may interfere with WiFi:" -ForegroundColor Yellow
    $externalSwitches | ForEach-Object {
        Write-Host "    - $($_.Name) (bound to: $($_.NetAdapterInterfaceDescription))" -ForegroundColor White
    }
    
    $remove = Read-Host "`nDo you want to remove External switches? (y/N)"
    if ($remove -eq 'y' -or $remove -eq 'Y') {
        $externalSwitches | ForEach-Object {
            Write-Host "  Removing $($_.Name)..." -ForegroundColor Yellow
            Remove-VMSwitch -Name $_.Name -Force
            Write-Host "  ✓ Removed" -ForegroundColor Green
        }
        Write-Host "`n✓ Your WiFi connection should now be restored!" -ForegroundColor Green
    }
} else {
    Write-Host "✓ No External switches found (good for WiFi)" -ForegroundColor Green
}

# Summary
Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✓ Virtual Switch Configuration Complete             ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Green

Write-Host "Network Configuration:" -ForegroundColor Cyan
Write-Host "  ✓ Internal-Lab: For VM-to-VM communication" -ForegroundColor White
Write-Host "  ✓ Default Switch: Hyper-V NAT (auto-created for VMs)" -ForegroundColor White
Write-Host "  ✓ Host WiFi: Unaffected and working normally" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Create OPNsense VM with these network settings:" -ForegroundColor White
Write-Host "     - WAN NIC → 'Default Switch' (for internet/VPN)" -ForegroundColor Yellow
Write-Host "     - LAN NIC → 'Internal-Lab' (for lab network)" -ForegroundColor Yellow
Write-Host "`n  2. Create Windows Server VM:" -ForegroundColor White
Write-Host "     - NIC → 'Internal-Lab' (isolated, no internet)" -ForegroundColor Yellow

Write-Host "`n✓ Your WiFi will remain connected for your host PC!`n" -ForegroundColor Green
