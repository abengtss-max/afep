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

# Step 2: Download Windows Server ISO
Write-Host "\n[2/5] Downloading Windows Server ISO for Arc VM..." -ForegroundColor Yellow
$isoPath = "C:\ISOs"
New-Item -ItemType Directory -Path $isoPath -Force | Out-Null

# Download Windows Server 2022 Evaluation ISO
$wsIsoUrl = "https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
$wsIsoPath = "$isoPath\WS2022.iso"

if (-not (Test-Path $wsIsoPath)) {
    Write-Host "  Downloading Windows Server 2022 ISO..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $wsIsoUrl -OutFile $wsIsoPath -UseBasicParsing
    Write-Host "  ✓ ISO downloaded" -ForegroundColor Green
} else {
    Write-Host "  ✓ ISO already exists" -ForegroundColor Green
}

# Step 3: Create Arc-enabled Windows Server VM
Write-Host "`n[3/5] Creating Arc-enabled Windows Server VM..." -ForegroundColor Yellow

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
Write-Host "    Next: Install Windows Server and configure networking" -ForegroundColor Yellow

# Step 4: Generate Arc Onboarding Script
Write-Host "`n[4/5] Generating Arc onboarding script..." -ForegroundColor Yellow

$arcOnboardScript = @"
# Arc Onboarding Script (run INSIDE Arc-Server-01 after Windows installation)

# Configure networking
New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress 10.0.1.10 -PrefixLength 24 -DefaultGateway 10.0.1.254
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 168.63.129.16

# Configure proxy for Arc agent
[Environment]::SetEnvironmentVariable('HTTPS_PROXY', 'http://10.100.0.4:8443', 'Machine')
[Environment]::SetEnvironmentVariable('HTTP_PROXY', 'http://10.100.0.4:8443', 'Machine')

# Download Arc agent
Invoke-WebRequest -Uri 'https://aka.ms/AzureConnectedMachineAgent' -OutFile 'C:\AzureConnectedMachineAgent.msi' -Proxy 'http://10.100.0.4:8443'

# Install Arc agent
msiexec /i C:\AzureConnectedMachineAgent.msi /qn /norestart

# Onboard to Azure Arc
& 'C:\Program Files\AzureConnectedMachineAgent\azcmagent.exe' connect --subscription-id 'b67d7073-183c-499f-aaa9-bbb4986dedf1' --resource-group 'rg-arc-nested-lab' --location 'swedencentral' --proxy-url 'http://10.100.0.4:8443'
"@

$arcOnboardScript | Out-File -FilePath "C:\Arc-Onboard.ps1" -Encoding UTF8 -Force
Write-Host "  * Arc onboarding script saved to: C:\Arc-Onboard.ps1" -ForegroundColor Green

# Step 5: Summary
Write-Host "`n[5/5] Configuration Complete!" -ForegroundColor Green
Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Start VM: Start-VM -Name 'ARC-Server-01'" -ForegroundColor White
Write-Host "  2. Connect to VM: vmconnect.exe localhost 'ARC-Server-01'" -ForegroundColor White
Write-Host "  3. Install Windows Server 2022" -ForegroundColor White
Write-Host "  4. Inside VM, run: C:\Arc-Onboard.ps1" -ForegroundColor White
Write-Host "`nProxy URL: http://10.100.0.4:8443" -ForegroundColor Cyan
Write-Host "VPN Shared Key: AzureArc2025!Lab5-mmuklyjjfwml4" -ForegroundColor Cyan
