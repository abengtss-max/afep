# ============================================================================
# Nested VM Configuration Script
# Run this script INSIDE the nested Hyper-V VM via RDP
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Configuring Nested Hyper-V for Arc Onboarding              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Configuration
$azureFirewallProxy = "http://10.100.0.4:8443"
$vpnGatewayIp = "4.223.154.191"
$vpnSharedKey = "AzureArc2025!Lab5-mmuklyjjfwml4"
$subscriptionId = "b67d7073-183c-499f-aaa9-bbb4986dedf1"
$resourceGroupName = "rg-arc-nested-lab"
$location = "swedencentral"

# Step 1: Create Internal Virtual Switch
Write-Host "`n[1/5] Creating Internal Virtual Switch..." -ForegroundColor Yellow
New-VMSwitch -Name "Internal-Lab" -SwitchType Internal -ErrorAction SilentlyContinue
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*Internal-Lab*" }
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 10.0.1.254 -PrefixLength 24 -ErrorAction SilentlyContinue
Write-Host "  ✓ Internal-Lab switch created (10.0.1.254/24)" -ForegroundColor Green

# Step 2: Download ISO Files
Write-Host "\n[2/7] Downloading ISO files..." -ForegroundColor Yellow
$isoPath = "C:\ISOs"
New-Item -ItemType Directory -Path $isoPath -Force | Out-Null

# Download OPNsense ISO
Write-Host "  Downloading OPNsense firewall ISO..." -ForegroundColor Gray
$opnsenseIsoUrl = "https://mirror.ams1.nl.leaseweb.net/opnsense/releases/24.7/OPNsense-24.7-dvd-amd64.iso"
$opnsenseIsoPath = "$isoPath\OPNsense-24.7-amd64.iso"

if (-not (Test-Path $opnsenseIsoPath)) {
    Invoke-WebRequest -Uri $opnsenseIsoUrl -OutFile $opnsenseIsoPath -UseBasicParsing
    Write-Host "  ✓ OPNsense ISO downloaded" -ForegroundColor Green
} else {
    Write-Host "  ✓ OPNsense ISO already exists" -ForegroundColor Green
}

# Download Windows Server 2022 Evaluation ISO
Write-Host "  Downloading Windows Server 2022 ISO..." -ForegroundColor Gray
$wsIsoUrl = "https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
$wsIsoPath = "$isoPath\WS2022.iso"

if (-not (Test-Path $wsIsoPath)) {
    Invoke-WebRequest -Uri $wsIsoUrl -OutFile $wsIsoPath -UseBasicParsing
    Write-Host "  ✓ Windows Server ISO downloaded" -ForegroundColor Green
} else {
    Write-Host "  ✓ Windows Server ISO already exists" -ForegroundColor Green
}

# Step 3: Create OPNsense Firewall VM
Write-Host "`n[3/7] Creating OPNsense Firewall VM..." -ForegroundColor Yellow

$fwVmName = "OPNsense-FW"
$fwVhdPath = "C:\Hyper-V\$fwVmName\$fwVmName.vhdx"

New-Item -ItemType Directory -Path "C:\Hyper-V\$fwVmName" -Force | Out-Null
New-VHD -Path $fwVhdPath -SizeBytes 8GB -Dynamic | Out-Null

New-VM -Name $fwVmName `
       -MemoryStartupBytes 2GB `
       -Generation 2 `
       -VHDPath $fwVhdPath `
       -SwitchName "Internal-Lab"

Set-VM -Name $fwVmName -ProcessorCount 2
Add-VMDvdDrive -VMName $fwVmName -Path $opnsenseIsoPath
Set-VMFirmware -VMName $fwVmName -FirstBootDevice (Get-VMDvdDrive -VMName $fwVmName)

Write-Host "  ✓ OPNsense VM created: $fwVmName" -ForegroundColor Green
Write-Host "    IMPORTANT: Configure OPNsense before proceeding:" -ForegroundColor Yellow
Write-Host "      1. Start VM: Start-VM -Name '$fwVmName'" -ForegroundColor White
Write-Host "      2. Connect: vmconnect.exe localhost '$fwVmName'" -ForegroundColor White
Write-Host "      3. Install OPNsense with LAN interface: 10.0.1.1/24" -ForegroundColor White
Write-Host "      4. Configure explicit proxy on port 3128" -ForegroundColor White
Write-Host "      5. Configure NAT and forwarding rules for Arc endpoints" -ForegroundColor White
Write-Host "      6. Set upstream proxy to: $azureFirewallProxy" -ForegroundColor White
Write-Host "\n  Press Enter when OPNsense is configured and running..." -ForegroundColor Yellow
Read-Host

# Step 4: Create Arc-enabled Windows Server VM
Write-Host "`n[4/7] Creating Arc-enabled Windows Server VM..." -ForegroundColor Yellow

$vmName = "ARC-Server-01"
$vhdPath = "C:\Hyper-V\$vmName\$vmName.vhdx"

New-Item -ItemType Directory -Path "C:\Hyper-V\$vmName" -Force | Out-Null
New-VHD -Path $vhdPath -SizeBytes 60GB -Dynamic | Out-Null

New-VM -Name $vmName `
       -MemoryStartupBytes 4GB `
       -Generation 2 `
       -VHDPath $vhdPath `
       -SwitchName "Internal-Lab"

Set-VM -Name $vmName -ProcessorCount 2 -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes 4GB
Add-VMDvdDrive -VMName $vmName -Path $wsIsoPath
Set-VMFirmware -VMName $vmName -FirstBootDevice (Get-VMDvdDrive -VMName $vmName)

Write-Host "  ✓ VM created: $vmName" -ForegroundColor Green
Write-Host "    Network: Internal-Lab (10.0.1.0/24)" -ForegroundColor Gray
Write-Host "    Gateway: 10.0.1.1 (OPNsense Firewall)" -ForegroundColor Gray
Write-Host "    Next: Install Windows Server and configure networking" -ForegroundColor Yellow

# Step 5: Generate OPNsense Configuration Guide
Write-Host "`n[5/7] Generating OPNsense configuration guide..." -ForegroundColor Yellow

$opnsenseConfigGuide = @"
# OPNsense Firewall Configuration Guide

## 1. Initial Setup
- Username: root
- Password: opnsense (default)
- LAN Interface: 10.0.1.1/24
- WAN Interface: Not configured (we use upstream proxy only)

## 2. Configure Web Proxy (Squid)
Services > Web Proxy > Administration
- Enable proxy: ✓
- Proxy interfaces: LAN
- Proxy port: 3128
- Transparent proxy: ✗ (use explicit)
- Parent proxy: 10.100.0.4:8443 (Azure Firewall)
- Enable access log: ✓

## 3. Configure Firewall Rules
Firewall > Rules > LAN
- Add rule: Allow TCP from 10.0.1.10 to any port 3128 (proxy access)
- Add rule: Allow UDP from 10.0.1.10 to 168.63.129.16 port 53 (DNS)
- Default rule: Block all (validate that Arc only works through proxy)

## 4. Required Arc Endpoints (whitelist in proxy ACLs)
Add to Services > Web Proxy > Access Control Lists:
- aka.ms
- *.his.arc.azure.com
- *.guestconfiguration.azure.com
- management.azure.com
- login.microsoftonline.com
- *.blob.core.windows.net
- *.servicebus.windows.net

## 5. Validation
- From Arc VM (10.0.1.10), test: Test-NetConnection 10.0.1.1 -Port 3128
- Check OPNsense logs: System > Log Files > Web Proxy
- Verify traffic goes: Arc VM -> OPNsense (3128) -> Azure Firewall (8443) -> Internet

"@

$opnsenseConfigGuide | Out-File -FilePath "C:\OPNsense-Config-Guide.txt" -Encoding UTF8 -Force
Write-Host "  ✓ OPNsense configuration guide saved to: C:\OPNsense-Config-Guide.txt" -ForegroundColor Green

# Step 6: Generate Arc Onboarding Script
Write-Host "`n[6/7] Generating Arc onboarding script..." -ForegroundColor Yellow

$arcOnboardScript = @"
# Arc Onboarding Script (run INSIDE Arc-Server-01 after Windows installation)

# Configure networking - Gateway is OPNsense firewall
New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress 10.0.1.10 -PrefixLength 24 -DefaultGateway 10.0.1.1
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 168.63.129.16

# Test connectivity to OPNsense proxy
Test-NetConnection 10.0.1.1 -Port 3128

# Configure proxy for Arc agent (through OPNsense)
[Environment]::SetEnvironmentVariable('HTTPS_PROXY', 'http://10.0.1.1:3128', 'Machine')
[Environment]::SetEnvironmentVariable('HTTP_PROXY', 'http://10.0.1.1:3128', 'Machine')

# Download Arc agent (through OPNsense proxy)
Invoke-WebRequest -Uri 'https://aka.ms/AzureConnectedMachineAgent' -OutFile 'C:\AzureConnectedMachineAgent.msi' -Proxy 'http://10.0.1.1:3128'

# Install Arc agent
msiexec /i C:\AzureConnectedMachineAgent.msi /qn /norestart

# Onboard to Azure Arc (traffic will flow: Arc VM -> OPNsense -> Azure Firewall -> Azure)
& 'C:\Program Files\AzureConnectedMachineAgent\azcmagent.exe' connect --subscription-id 'b67d7073-183c-499f-aaa9-bbb4986dedf1' --resource-group 'rg-arc-nested-lab' --location 'swedencentral' --proxy-url 'http://10.0.1.1:3128'
"@

$arcOnboardScript | Out-File -FilePath "C:\Arc-Onboard.ps1" -Encoding UTF8 -Force
Write-Host "  ✓ Arc onboarding script saved to: C:\Arc-Onboard.ps1" -ForegroundColor Green

# Step 7: Summary
Write-Host "`n[7/7] Configuration Complete!" -ForegroundColor Green
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Network Topology Summary                                    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "`nTraffic Flow:" -ForegroundColor Yellow
Write-Host "  Arc-Server-01 (10.0.1.10)" -ForegroundColor White
Write-Host "    ↓ port 3128" -ForegroundColor Gray
Write-Host "  OPNsense Firewall (10.0.1.1)" -ForegroundColor White
Write-Host "    ↓ port 8443" -ForegroundColor Gray
Write-Host "  Azure Firewall (10.100.0.4)" -ForegroundColor White
Write-Host "    ↓" -ForegroundColor Gray
Write-Host "  Azure Arc Endpoints" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Configure OPNsense (see C:\OPNsense-Config-Guide.txt)" -ForegroundColor White
Write-Host "  2. Start Arc VM: Start-VM -Name 'ARC-Server-01'" -ForegroundColor White
Write-Host "  3. Connect to VM: vmconnect.exe localhost 'ARC-Server-01'" -ForegroundColor White
Write-Host "  4. Install Windows Server 2022" -ForegroundColor White
Write-Host "  5. Inside Arc VM, run: C:\Arc-Onboard.ps1" -ForegroundColor White
Write-Host "  6. Validate in OPNsense logs: System > Log Files > Web Proxy" -ForegroundColor White
Write-Host "  7. Validate in Azure Firewall logs: Query for SourceIp == '10.0.1.10'" -ForegroundColor White

Write-Host "`nKey Information:" -ForegroundColor Cyan
Write-Host "  OPNsense Proxy: http://10.0.1.1:3128" -ForegroundColor White
Write-Host "  Azure Firewall Proxy: http://10.100.0.4:8443" -ForegroundColor White
Write-Host "  VPN Shared Key: AzureArc2025!Lab5-mmuklyjjfwml4" -ForegroundColor White
