# Lab 4: On-Premises Setup Guide - Hyper-V + pfSense + S2S VPN

## 📋 Overview

This guide walks you through setting up the **on-premises environment** on your **Windows 11 Pro PC** to simulate a real datacenter with:
- ✅ Hyper-V virtualization
- ✅ pfSense firewall (blocking all internet traffic)
- ✅ Windows Server 2022 (Arc-enabled server)
- ✅ Site-to-Site VPN to Azure

**Operating System:** Windows 11 Pro (or Windows 10 Pro)  
**Time required:** 2-3 hours (first time)

**⚠️ CRITICAL:** This guide assumes you have **NOT** completed any previous steps. We'll validate everything as we go.

---

## 🎯 What You'll Build

```
Your Windows PC (Physical)
├── Hyper-V Host
│   ├── VM1: pfSense Firewall
│   │   ├── WAN NIC → Your PC's internet (for VPN only)
│   │   ├── LAN NIC → Internal network (10.0.1.0/24)
│   │   ├── VPN Tunnel → Azure VPN Gateway
│   │   └── Firewall Rules → Block all except VPN
│   │
│   └── VM2: Windows Server 2022
│       ├── NIC → pfSense LAN (10.0.1.10/24)
│       ├── Gateway → pfSense (10.0.1.1)
│       ├── DNS → Azure Firewall via VPN (10.100.0.4)
│       ├── NO direct internet access
│       └── Azure Arc Agent → Uses proxy via VPN
│
└── Virtual Switches
    ├── "External" → Physical NIC (internet)
    └── "Internal-Lab" → Isolated network
```

---

## ⚙️ Prerequisites

### Step 0.1: Verify Windows 11 Pro Edition

Open PowerShell and run:

```powershell
# Check Windows edition
Get-WindowsEdition -Online | Select-Object Edition

# Should show: Professional or Enterprise
# If shows "Core" or "Home", you CANNOT use Hyper-V
```

**If you have Home edition:**
- ❌ Hyper-V is NOT available
- ✅ Alternative: Use Oracle VirtualBox (free) instead
- 📚 See: `GUIDE-VirtualBox-Alternative.md` (if you need this, let me know)

### Step 0.2: Verify Azure Deployment Completed

```powershell
# Check if deployment script has been run
$deploymentFile = "C:\Users\$env:USERNAME\MyProjects\azfw\scripts\Lab4-Arc-DeploymentInfo.json"

if (Test-Path $deploymentFile) {
    Write-Host "✓ Azure deployment completed" -ForegroundColor Green
    
    # Load deployment info
    $azureInfo = Get-Content $deploymentFile | ConvertFrom-Json
    Write-Host "  VPN Gateway IP: $($azureInfo.VPNGateway.PublicIP)" -ForegroundColor Yellow
    Write-Host "  Shared Key: $($azureInfo.VPNGateway.SharedKey)" -ForegroundColor Yellow
} else {
    Write-Host "✗ Azure deployment NOT found" -ForegroundColor Red
    Write-Host "`n  YOU MUST DEPLOY AZURE INFRASTRUCTURE FIRST!" -ForegroundColor Red
    Write-Host "`n  Steps:" -ForegroundColor Yellow
    Write-Host "  1. Open PowerShell as Administrator" -ForegroundColor White
    Write-Host "  2. cd C:\Users\$env:USERNAME\MyProjects\azfw\scripts" -ForegroundColor White
    Write-Host "  3. .\Deploy-Lab4-Arc-ExplicitProxy.ps1" -ForegroundColor White
    Write-Host "  4. Wait 35-45 minutes" -ForegroundColor White
    Write-Host "  5. Return to this guide`n" -ForegroundColor White
    
    exit 1
}
```

**⚠️ If deployment file is missing, STOP HERE and deploy Azure first!**

### Step 0.3: Check Hardware Requirements

```powershell
Write-Host "`n=== HARDWARE CHECK ===" -ForegroundColor Cyan

# Check CPU cores
$cores = (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors
Write-Host "CPU Cores: $cores" -ForegroundColor $(if($cores -ge 4){'Green'}else{'Red'})
if ($cores -lt 4) {
    Write-Host "  ⚠  Minimum 4 cores recommended" -ForegroundColor Yellow
}

# Check RAM
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
Write-Host "Total RAM: $ram GB" -ForegroundColor $(if($ram -ge 8){'Green'}else{'Red'})
if ($ram -lt 8) {
    Write-Host "  ⚠  Minimum 8 GB recommended" -ForegroundColor Yellow
}

# Check free disk space
$disk = Get-PSDrive C | Select-Object @{N='FreeGB';E={[math]::Round($_.Free/1GB,2)}}
Write-Host "Free Disk Space (C:): $($disk.FreeGB) GB" -ForegroundColor $(if($disk.FreeGB -ge 60){'Green'}else{'Red'})
if ($disk.FreeGB -lt 60) {
    Write-Host "  ⚠  Minimum 60 GB recommended" -ForegroundColor Yellow
}

# Check virtualization support
$virt = (Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled
Write-Host "Virtualization Enabled: $virt" -ForegroundColor $(if($virt){'Green'}else{'Red'})
if (-not $virt) {
    Write-Host "  ✗ CRITICAL: Enable virtualization in BIOS!" -ForegroundColor Red
    Write-Host "    1. Restart PC" -ForegroundColor White
    Write-Host "    2. Enter BIOS (usually F2, Del, F10, or Esc)" -ForegroundColor White
    Write-Host "    3. Find 'Virtualization Technology' or 'Intel VT-x' / 'AMD-V'" -ForegroundColor White
    Write-Host "    4. Enable it" -ForegroundColor White
    Write-Host "    5. Save and exit" -ForegroundColor White
}
```

### Step 0.4: Download Required ISOs

**Create download directory:**

```powershell
# Create directory for ISOs
New-Item -ItemType Directory -Path "C:\ISOs" -Force
```

**Download 1: pfSense**

1. Open browser and go to: https://www.pfsense.org/download/
2. Configuration:
   - **Architecture:** AMD64 (64-bit)
   - **Installer:** DVD Image (ISO)
   - **Mirror:** Choose closest location
3. Click "Download"
4. Save to: `C:\ISOs\pfSense-CE-2.7.2-RELEASE-amd64.iso`
5. Size: ~800 MB
6. Wait for download to complete

**Download 2: Windows Server 2022**

1. Go to: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
2. Fill in registration form (required by Microsoft)
3. Select: **64-bit edition ISO**
4. Language: **English (United States)**
5. Click "Download"
6. Save to: `C:\ISOs\WS2022-Eval.iso`
7. Size: ~5 GB
8. Wait for download (may take 10-30 minutes depending on connection)

**Verify downloads:**

```powershell
# Check ISO files exist
$pfSenseIso = "C:\ISOs\pfSense-CE-2.7.2-RELEASE-amd64.iso"
$ws2022Iso = "C:\ISOs\WS2022-Eval.iso"

if (Test-Path $pfSenseIso) {
    $size = [math]::Round((Get-Item $pfSenseIso).Length / 1MB, 2)
    Write-Host "✓ pfSense ISO found ($size MB)" -ForegroundColor Green
} else {
    Write-Host "✗ pfSense ISO NOT found at: $pfSenseIso" -ForegroundColor Red
}

if (Test-Path $ws2022Iso) {
    $size = [math]::Round((Get-Item $ws2022Iso).Length / 1MB, 2)
    Write-Host "✓ Windows Server 2022 ISO found ($size MB)" -ForegroundColor Green
} else {
    Write-Host "✗ Windows Server 2022 ISO NOT found at: $ws2022Iso" -ForegroundColor Red
}
```

**⚠️ Do NOT proceed until both ISOs are downloaded!**

---

## 📝 Step 1: Enable Hyper-V on Your PC

### Check if Virtualization is Enabled

Open PowerShell **as Administrator** and run:

```powershell
# Check if virtualization is enabled in BIOS
Get-ComputerInfo | Select-Object CsProcessors | Format-List

# Look for: "VirtualizationFirmwareEnabled : True"
```

If **False**, you need to enable it in BIOS:
1. Restart PC
2. Press `F2`, `Del`, `F10`, or `Esc` (depends on manufacturer)
3. Find "Virtualization Technology" or "Intel VT-x" / "AMD-V"
4. Enable it
5. Save and exit

### Install Hyper-V Feature

```powershell
# Open PowerShell as Administrator

# Enable Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Restart required
Restart-Computer
```

After restart, verify installation:

```powershell
# Open PowerShell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
```

Should show: **State : Enabled**

---

## 📝 Step 2: Create Hyper-V Virtual Switches

### Create External Switch (for internet/VPN)

```powershell
# List your physical network adapters
Get-NetAdapter | Select-Object Name, Status, LinkSpeed

# Create external switch (replace "Ethernet" with your adapter name)
New-VMSwitch -Name "External" -NetAdapterName "Ethernet" -AllowManagementOS $true
```

**⚠️ Warning:** Your internet may disconnect briefly (5-10 seconds) during this step.

### Create Internal Switch (for lab network)

```powershell
# Create internal switch for isolated lab network
New-VMSwitch -Name "Internal-Lab" -SwitchType Internal

# Create a new network adapter for the internal switch
New-NetIPAddress -IPAddress 192.168.100.1 -PrefixLength 24 -InterfaceAlias "vEthernet (Internal-Lab)"
```

### Verify Switches

```powershell
Get-VMSwitch | Format-Table Name, SwitchType, NetAdapterInterfaceDescription
```

Should see:
- `External` (SwitchType: External)
- `Internal-Lab` (SwitchType: Internal)

---

## 📝 Step 3: Create pfSense Firewall VM

### Create VM

```powershell
# Create VM
New-VM -Name "pfSense-Lab" -MemoryStartupBytes 1GB -Generation 1 -Path "C:\Hyper-V"

# Add network adapters (2 NICs)
Add-VMNetworkAdapter -VMName "pfSense-Lab" -SwitchName "External"  # WAN
Add-VMNetworkAdapter -VMName "pfSense-Lab" -SwitchName "Internal-Lab"  # LAN

# Add DVD drive and mount pfSense ISO
Set-VMDvdDrive -VMName "pfSense-Lab" -Path "C:\ISOs\pfSense-CE-2.7.2-RELEASE-amd64.iso"

# Create virtual hard disk
New-VHD -Path "C:\Hyper-V\pfSense-Lab\pfSense-Lab.vhdx" -SizeBytes 8GB -Dynamic
Add-VMHardDiskDrive -VMName "pfSense-Lab" -Path "C:\Hyper-V\pfSense-Lab\pfSense-Lab.vhdx"

# Disable Secure Boot (required for pfSense)
Set-VMFirmware -VMName "pfSense-Lab" -EnableSecureBoot Off

# Start VM
Start-VM -Name "pfSense-Lab"

# Connect to VM console
vmconnect localhost "pfSense-Lab"
```

### Install pfSense

1. **Boot from ISO** - Should start automatically
2. **Accept:** Copyright and distribution notice (Enter)
3. **Install:** Choose "Install pfSense" (Enter)
4. **Keymap:** Select "US" or your keyboard layout
5. **Partitioning:** Choose "Auto (ZFS)" → Proceed with installation
6. **ZFS Configuration:**
   - Select "Install" (Stripe - no redundancy)
   - Select your virtual hard disk
   - Confirm: "YES" (will erase disk)
7. **Wait:** Installation takes 2-3 minutes
8. **Reboot:** Choose "Reboot" when prompted
9. **Remove ISO:** In Hyper-V Manager, eject the DVD

### Initial Configuration

After reboot, pfSense will detect interfaces:

```
WAN interface: hn0 (MAC: XX:XX:XX:XX:XX:XX) [External switch]
LAN interface: hn1 (MAC: YY:YY:YY:YY:YY:YY) [Internal switch]
```

1. **Assign Interfaces:**
   - VLANs: `n` (no)
   - WAN: `hn0` (first MAC address)
   - LAN: `hn1` (second MAC address)
   - Optional: (leave empty, press Enter)
   - Proceed: `y`

2. **Set LAN IP Address:**
   - Option: `2` (Set interface IP address)
   - Interface: `2` (LAN)
   - IP Address: `10.0.1.1`
   - Subnet: `24`
   - Upstream gateway: (leave empty, press Enter)
   - IPv6: `n`
   - DHCP Server: `y`
   - Start address: `10.0.1.100`
   - End address: `10.0.1.200`
   - HTTP WebGUI: `n` (we'll use HTTPS)

3. **Note the WebGUI URL:**
   ```
   https://10.0.1.1
   Username: admin
   Password: pfsense
   ```

---

## 📝 Step 4: Create Windows Server 2022 VM

### Create VM

```powershell
# Create VM with 4 GB RAM
New-VM -Name "ArcServer-Lab" -MemoryStartupBytes 4GB -Generation 2 -Path "C:\Hyper-V"

# Configure processor (2 vCPUs)
Set-VMProcessor -VMName "ArcServer-Lab" -Count 2

# Add network adapter (connected to pfSense LAN)
Add-VMNetworkAdapter -VMName "ArcServer-Lab" -SwitchName "Internal-Lab"

# Create virtual hard disk (40 GB)
New-VHD -Path "C:\Hyper-V\ArcServer-Lab\ArcServer-Lab.vhdx" -SizeBytes 40GB -Dynamic
Add-VMHardDiskDrive -VMName "ArcServer-Lab" -Path "C:\Hyper-V\ArcServer-Lab\ArcServer-Lab.vhdx"

# Mount Windows Server ISO
Add-VMDvdDrive -VMName "ArcServer-Lab" -Path "C:\ISOs\WS2022-Eval.iso"

# Set boot order (DVD first)
$dvd = Get-VMDvdDrive -VMName "ArcServer-Lab"
Set-VMFirmware -VMName "ArcServer-Lab" -FirstBootDevice $dvd

# Start VM
Start-VM -Name "ArcServer-Lab"

# Connect to VM console
vmconnect localhost "ArcServer-Lab"
```

### Install Windows Server 2022

1. **Language/Time:** Select and click "Next"
2. **Install:** Click "Install now"
3. **Edition:** Select "Windows Server 2022 Standard (Desktop Experience)"
4. **License:** Accept terms
5. **Installation Type:** "Custom: Install Windows only"
6. **Disk:** Select unallocated space, click "Next"
7. **Wait:** Installation takes 10-15 minutes
8. **Administrator Password:** Set a strong password (e.g., `P@ssw0rd123!`)

### Initial Server Configuration

After installation, server will reboot into Windows:

1. **Server Manager** will open automatically
2. **Configure Network:**
   - Click "Local Server"
   - Click "Ethernet" (should show "DHCP enabled")
   - Right-click network connection → Properties
   - Select "Internet Protocol Version 4 (TCP/IPv4)"
   - Click "Properties"
   - Configure:
     ```
     IP address:     10.0.1.10
     Subnet mask:    255.255.255.0
     Default gateway: 10.0.1.1 (pfSense)
     Preferred DNS:  10.0.1.1 (pfSense, temporary)
     ```
   - Click "OK"

3. **Set Computer Name:**
   - In Server Manager, click "Computer name: WIN-XXXXXX"
   - Click "Change"
   - Computer name: `ArcServer01`
   - Click "OK" → Restart

4. **Verify Connectivity to pfSense:**
   ```powershell
   # Open PowerShell
   Test-NetConnection 10.0.1.1
   ```

   Should show: **PingSucceeded : True**

---

## 📝 Step 5: Configure pfSense Firewall Rules

### Access pfSense WebGUI

From **ArcServer01** (Windows Server VM):

1. Open Microsoft Edge
2. Navigate to: `https://10.0.1.1`
3. Accept certificate warning (self-signed)
4. Login:
   - Username: `admin`
   - Password: `pfsense`

### Initial Setup Wizard

1. **Welcome:** Click "Next"
2. **Netgate Global Support:** Skip (click "Next")
3. **General Information:**
   - Hostname: `pfsense`
   - Domain: `lab.local`
   - Primary DNS: `1.1.1.1` (Cloudflare)
   - Secondary DNS: `8.8.8.8` (Google)
   - Click "Next"
4. **Time Server:** Leave defaults, click "Next"
5. **WAN Interface:** Leave as DHCP, click "Next"
6. **LAN Interface:**
   - LAN IP: `10.0.1.1`
   - Subnet: `24`
   - Click "Next"
7. **Admin Password:**
   - Change from default `pfsense` to something stronger
   - **Remember this password!**
8. **Reload:** Click "Reload" → Wizard complete
9. **Finish:** Click "Finish"

### Block All Internet Traffic (Except VPN)

**Goal:** Ensure Arc server can **ONLY** reach Azure via VPN tunnel, no direct internet.

1. **Navigate:** Firewall → Rules → LAN

2. **Delete Default Rules:**
   - Find "Default allow LAN to any rule"
   - Click ✗ (delete icon)
   - Click "Apply Changes"

3. **Add Rule: Allow LAN to pfSense**
   - Click "↑ Add" (add rule to top)
   - **Action:** Pass
   - **Interface:** LAN
   - **Protocol:** Any
   - **Source:** LAN net
   - **Destination:** This firewall (self)
   - **Description:** "Allow access to pfSense WebGUI and DNS"
   - Click "Save"

4. **Add Rule: Allow VPN Traffic (placeholder)**
   - Click "↑ Add"
   - **Action:** Pass
   - **Interface:** LAN
   - **Protocol:** Any
   - **Source:** LAN net
   - **Destination:** Single host or alias: `10.100.0.0/16` (Azure VNet)
   - **Description:** "Allow traffic to Azure via VPN"
   - Click "Save"

5. **Click "Apply Changes"**

6. **Test Internet is Blocked:**
   - From ArcServer01, open PowerShell:
   ```powershell
   Test-NetConnection google.com
   # Should FAIL or timeout - this is expected!
   
   Test-NetConnection 10.0.1.1
   # Should SUCCEED - pfSense is reachable
   ```

---

## 📝 Step 6: Configure Site-to-Site VPN

### Get Azure VPN Information

On your **host PC**, open PowerShell and read the deployment info:

```powershell
# Read Azure deployment information
$azureInfo = Get-Content "C:\Users\$env:USERNAME\MyProjects\azfw\scripts\Lab4-Arc-DeploymentInfo.json" | ConvertFrom-Json

# Display VPN configuration
Write-Host "Azure VPN Gateway Public IP: $($azureInfo.VPNGateway.PublicIP)" -ForegroundColor Yellow
Write-Host "VPN Shared Key: $($azureInfo.VPNGateway.SharedKey)" -ForegroundColor Yellow
Write-Host "Azure Firewall Private IP: $($azureInfo.AzureFirewall.PrivateIP)" -ForegroundColor Yellow
```

**Write these down! You'll need them next.**

### Configure IPsec VPN on pfSense

1. **Navigate:** VPN → IPsec → Tunnels

2. **Add P1 (Phase 1):**
   - Click "↑ Add P1"
   - **General Information:**
     - Disabled: ☐ (unchecked)
     - Key Exchange version: `IKEv2`
     - Internet Protocol: `IPv4`
     - Interface: `WAN`
     - Remote Gateway: `<Azure VPN Gateway Public IP>` (from deployment info)
     - Description: `Azure VPN Gateway`
   
   - **Phase 1 Proposal (Authentication):**
     - Authentication Method: `Mutual PSK`
     - My identifier: `My IP address`
     - Peer identifier: `Peer IP address`
     - Pre-Shared Key: `<VPN Shared Key>` (from deployment info)
   
   - **Phase 1 Proposal (Algorithms):**
     - Encryption Algorithm: `AES 256 bits`
     - Hash Algorithm: `SHA256`
     - DH Group: `14 (2048 bit)`
     - Lifetime: `28800` seconds
   
   - **Advanced Options:** Leave defaults
   - Click "Save"

3. **Add P2 (Phase 2):**
   - Click "Show Phase 2 Entries" on your new tunnel
   - Click "↑ Add P2"
   - **General Information:**
     - Disabled: ☐ (unchecked)
     - Mode: `Tunnel IPv4`
     - Local Network: `LAN subnet`
     - Remote Network: `Network` → `10.100.0.0/16` (Azure VNet)
     - Description: `Azure VNet`
   
   - **Phase 2 Proposal (SA/Key Exchange):**
     - Protocol: `ESP`
     - Encryption Algorithms: `AES 256 bits`
     - Hash Algorithms: `SHA256`
     - PFS Key Group: `14 (2048 bit)`
     - Lifetime: `3600` seconds
   
   - Click "Save"

4. **Apply Changes:** Click "Apply Changes"

5. **Check Status:**
   - Navigate: Status → IPsec → Overview
   - Click "Connect VPN" button (if not connected)
   - Wait 10-30 seconds
   - Status should show: **ESTABLISHED** (green)

### Update Azure Local Network Gateway

The Azure side needs to know YOUR public IP for the VPN tunnel.

1. **Find Your Public IP:**
   - From host PC, open browser and go to: https://ifconfig.me
   - Or run: `(Invoke-WebRequest -Uri "https://ifconfig.me").Content`

2. **Update Azure:**
   ```powershell
   # On host PC
   $myPublicIP = (Invoke-WebRequest -Uri "https://ifconfig.me").Content.Trim()
   
   Set-AzLocalNetworkGateway `
       -Name "lng-onprem-lab" `
       -ResourceGroupName "rg-afep-lab04-arc-$env:USERNAME" `
       -GatewayIpAddress $myPublicIP
   
   Write-Host "Updated Azure Local Network Gateway with your IP: $myPublicIP"
   ```

3. **Create VPN Connection in Azure:**
   ```powershell
   # Get resources
   $localGw = Get-AzLocalNetworkGateway -Name "lng-onprem-lab" -ResourceGroupName "rg-afep-lab04-arc-$env:USERNAME"
   $vpnGw = Get-AzVirtualNetworkGateway -Name "vpngw-arc-lab" -ResourceGroupName "rg-afep-lab04-arc-$env:USERNAME"
   
   # Get shared key from deployment info
   $azureInfo = Get-Content "Lab4-Arc-DeploymentInfo.json" | ConvertFrom-Json
   $sharedKey = ConvertTo-SecureString -String $azureInfo.VPNGateway.SharedKey -AsPlainText -Force
   
   # Create connection
   New-AzVirtualNetworkGatewayConnection `
       -Name "S2S-OnPrem-to-Azure" `
       -ResourceGroupName "rg-afep-lab04-arc-$env:USERNAME" `
       -Location $azureInfo.Location `
       -VirtualNetworkGateway1 $vpnGw `
       -LocalNetworkGateway2 $localGw `
       -ConnectionType IPsec `
       -SharedKey $sharedKey `
       -EnableBgp $false
   
   Write-Host "VPN connection created. Checking status..."
   
   # Check connection status (may take 1-2 minutes)
   Start-Sleep -Seconds 30
   Get-AzVirtualNetworkGatewayConnection -Name "S2S-OnPrem-to-Azure" -ResourceGroupName "rg-afep-lab04-arc-$env:USERNAME" | Select-Object Name, ConnectionStatus
   ```

4. **Wait for Connection:**
   - Status should show: **Connected**
   - If **Connecting**, wait 1-2 minutes and check again

---

## 📝 Step 7: Verify VPN Connectivity (CRITICAL VALIDATION)

**⚠️ DO NOT SKIP THIS STEP!** You must verify VPN is working before proceeding to Arc agent installation.

### Validation Script - Run on ArcServer01

```powershell
Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   VPN CONNECTIVITY VALIDATION - 6 CRITICAL TESTS      ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$testsPassed = 0
$testsFailed = 0

# Test 1: pfSense local gateway
Write-Host "[1/6] Testing pfSense local gateway (10.0.1.1)..." -NoNewline
$result = Test-NetConnection -ComputerName 10.0.1.1 -WarningAction SilentlyContinue
if ($result.PingSucceeded) {
    Write-Host " ✓" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " ✗" -ForegroundColor Red
    $testsFailed++
}

# Test 2: Azure Firewall via VPN (ICMP)
Write-Host "[2/6] Testing Azure Firewall via VPN (10.100.0.4)..." -NoNewline
$result = Test-NetConnection -ComputerName 10.100.0.4 -WarningAction SilentlyContinue
if ($result.PingSucceeded) {
    Write-Host " ✓" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " ✗" -ForegroundColor Red
    Write-Host "     ERROR: VPN tunnel is NOT working!" -ForegroundColor Red
    $testsFailed++
}

# Test 3: HTTP Proxy Port (8081)
Write-Host "[3/6] Testing HTTP proxy port (10.100.0.4:8081)..." -NoNewline
$result = Test-NetConnection -ComputerName 10.100.0.4 -Port 8081 -WarningAction SilentlyContinue
if ($result.TcpTestSucceeded) {
    Write-Host " ✓" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " ✗" -ForegroundColor Red
    $testsFailed++
}

# Test 4: HTTPS Proxy Port (8443)
Write-Host "[4/6] Testing HTTPS proxy port (10.100.0.4:8443)..." -NoNewline
$result = Test-NetConnection -ComputerName 10.100.0.4 -Port 8443 -WarningAction SilentlyContinue
if ($result.TcpTestSucceeded) {
    Write-Host " ✓" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host " ✗" -ForegroundColor Red
    $testsFailed++
}

# Test 5: Internet is BLOCKED (security check)
Write-Host "[5/6] Verifying internet is blocked (google.com)..." -NoNewline
try {
    $result = Test-NetConnection -ComputerName google.com -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet -ErrorAction Stop -TimeoutSeconds 5
    if ($result) {
        Write-Host " ✗" -ForegroundColor Red
        Write-Host "     WARNING: Internet is NOT blocked!" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host " ✓" -ForegroundColor Green
    $testsPassed++
}

# Test 6: DNS resolution
Write-Host "[6/6] Testing DNS resolution (microsoft.com)..." -NoNewline
try {
    $result = Resolve-DnsName microsoft.com -ErrorAction Stop
    Write-Host " ✓" -ForegroundColor Green
    $testsPassed++
} catch {
    Write-Host " ✗" -ForegroundColor Red
    $testsFailed++
}

# Summary
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed/6" -ForegroundColor $(if($testsPassed -eq 6){'Green'}else{'Yellow'})
Write-Host "Tests Failed: $testsFailed/6" -ForegroundColor $(if($testsFailed -eq 0){'Green'}else{'Red'})
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

if ($testsPassed -eq 6) {
    Write-Host "✓✓✓ ALL TESTS PASSED - VPN IS WORKING ✓✓✓" -ForegroundColor Green
    Write-Host "You are ready to proceed to Arc agent installation!" -ForegroundColor Green
    Write-Host "`nNext: Open GUIDE-Arc-Agent-Proxy-Config.md`n" -ForegroundColor Yellow
} else {
    Write-Host "✗✗✗ TESTS FAILED - DO NOT PROCEED ✗✗✗" -ForegroundColor Red
    Write-Host "Fix the issues below before continuing:`n" -ForegroundColor Yellow
    
    if ($testsFailed -gt 0) {
        Write-Host "Troubleshooting steps:" -ForegroundColor Cyan
        Write-Host "  1. Check pfSense VPN status: Status → IPsec → Overview" -ForegroundColor White
        Write-Host "  2. Verify Azure VPN connection: Azure Portal → VPN Gateway → Connections" -ForegroundColor White
        Write-Host "  3. Check firewall rules on pfSense: Firewall → Rules → LAN" -ForegroundColor White
        Write-Host "  4. Review troubleshooting section below`n" -ForegroundColor White
    }
}
```

### Additional Manual Verification

**From pfSense WebGUI:**

1. **Check VPN Status:**
   - Navigate: **Status → IPsec → Overview**
   - Look for your tunnel entry
   - Status should show: **ESTABLISHED** (green)
   - If shows "CONNECTING" or red, VPN is NOT working

2. **Test Ping from pfSense:**
   - Navigate: **Diagnostics → Ping**
   - **Hostname:** `10.100.0.4`
   - **Click:** "Ping"
   - **Expected:** Should show replies like:
     ```
     PING 10.100.0.4 (10.100.0.4): 56 data bytes
     64 bytes from 10.100.0.4: icmp_seq=0 ttl=64 time=15.2 ms
     64 bytes from 10.100.0.4: icmp_seq=1 ttl=64 time=14.8 ms
     ```

**From Azure Portal (Host PC):**

1. Open: https://portal.azure.com
2. Search for: **VPN Gateway**
3. Click on: **vpngw-arc-lab**
4. Navigate to: **Connections** (left menu)
5. Find: **S2S-OnPrem-to-Azure**
6. Status should show: **Connected** (green)
7. If shows "Connecting" or "Failed", troubleshoot below

---

## 🚨 VPN Troubleshooting (If Tests Failed)

### Troubleshooting if VPN Doesn't Connect

1. **Check pfSense IPsec logs:**
   - Status → System Logs → IPsec
   - Look for errors

2. **Check Azure VPN Gateway:**
   ```powershell
   Get-AzVirtualNetworkGatewayConnection -Name "S2S-OnPrem-to-Azure" -ResourceGroupName "rg-afep-lab04-arc-$env:USERNAME"
   ```

3. **Common issues:**
   - ❌ Shared key mismatch
   - ❌ Wrong remote gateway IP
   - ❌ Firewall blocking UDP 500/4500 on host PC
   - ❌ Phase 1/2 settings mismatch

---

## 📝 Step 8: Configure DNS to Use Azure Firewall

Now that VPN is working, configure ArcServer01 to use Azure Firewall DNS (via VPN).

### Update Network Settings on ArcServer01

```powershell
# Open PowerShell as Administrator

# Get network adapter
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}

# Set DNS to Azure Firewall (via VPN)
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses "10.100.0.4"

# Verify
Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
```

### Test DNS Resolution

```powershell
# Test DNS resolution through Azure Firewall
Resolve-DnsName microsoft.com
Resolve-DnsName management.azure.com

# Should resolve successfully (Azure Firewall DNS Proxy)
```

---

## ✅ FINAL VALIDATION - Run Before Moving to Next Guide

**⚠️ MANDATORY CHECK - DO NOT SKIP!**

Run this complete validation script on ArcServer01 to confirm ALL prerequisites are met:

```powershell
Write-Host "`n╔═════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  FINAL ON-PREMISES SETUP VALIDATION - 10 CRITICAL CHECKS   ║" -ForegroundColor Cyan
Write-Host "╚═════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$checks = @{
    Passed = 0
    Failed = 0
}

# Check 1: Hostname
Write-Host "[1/10] Verifying hostname is ArcServer01..." -NoNewline
if ($env:COMPUTERNAME -eq "ArcServer01") {
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
} else {
    Write-Host " ✗ (Current: $env:COMPUTERNAME)" -ForegroundColor Red
    $checks.Failed++
}

# Check 2: Deployment info file exists
Write-Host "[2/10] Checking deployment info file..." -NoNewline
$deployFile = "C:\Lab4-Arc-DeploymentInfo.json"
if (Test-Path $deployFile) {
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
} else {
    Write-Host " ✗ (File not found)" -ForegroundColor Red
    $checks.Failed++
}

# Check 3: pfSense gateway
Write-Host "[3/10] Testing pfSense gateway (10.0.1.1)..." -NoNewline
$result = Test-NetConnection -ComputerName 10.0.1.1 -WarningAction SilentlyContinue
if ($result.PingSucceeded) {
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
} else {
    Write-Host " ✗" -ForegroundColor Red
    $checks.Failed++
}

# Check 4: Azure Firewall via VPN
Write-Host "[4/10] Testing Azure Firewall via VPN (10.100.0.4)..." -NoNewline
$result = Test-NetConnection -ComputerName 10.100.0.4 -WarningAction SilentlyContinue
if ($result.PingSucceeded) {
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
} else {
    Write-Host " ✗" -ForegroundColor Red
    $checks.Failed++
}

# Check 5: HTTP Proxy port
Write-Host "[5/10] Testing HTTP proxy port (8081)..." -NoNewline
$result = Test-NetConnection -ComputerName 10.100.0.4 -Port 8081 -WarningAction SilentlyContinue
if ($result.TcpTestSucceeded) {
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
} else {
    Write-Host " ✗" -ForegroundColor Red
    $checks.Failed++
}

# Check 6: HTTPS Proxy port
Write-Host "[6/10] Testing HTTPS proxy port (8443)..." -NoNewline
$result = Test-NetConnection -ComputerName 10.100.0.4 -Port 8443 -WarningAction SilentlyContinue
if ($result.TcpTestSucceeded) {
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
} else {
    Write-Host " ✗" -ForegroundColor Red
    $checks.Failed++
}

# Check 7: Internet is BLOCKED
Write-Host "[7/10] Verifying internet is blocked..." -NoNewline
try {
    $result = Test-NetConnection -ComputerName google.com -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet -ErrorAction Stop -TimeoutSeconds 5
    if ($result) {
        Write-Host " ✗ (Internet NOT blocked!)" -ForegroundColor Red
        $checks.Failed++
    }
} catch {
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
}

# Check 8: DNS resolution
Write-Host "[8/10] Testing DNS resolution..." -NoNewline
try {
    $result = Resolve-DnsName microsoft.com -ErrorAction Stop
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
} catch {
    Write-Host " ✗" -ForegroundColor Red
    $checks.Failed++
}

# Check 9: DNS server is Azure Firewall
Write-Host "[9/10] Verifying DNS server is Azure Firewall..." -NoNewline
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
$dnsServers = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses
if ($dnsServers -contains "10.100.0.4") {
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
} else {
    Write-Host " ✗ (Current: $dnsServers)" -ForegroundColor Red
    $checks.Failed++
}

# Check 10: PowerShell can reach Azure Firewall
Write-Host "[10/10] Testing PowerShell connectivity to proxy..." -NoNewline
try {
    $proxy = "http://10.100.0.4:8081"
    $webClient = New-Object System.Net.WebClient
    $webClient.Proxy = New-Object System.Net.WebProxy($proxy)
    $webClient.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    $webClient.DownloadString("http://detectportal.firefox.com") | Out-Null
    Write-Host " ✓" -ForegroundColor Green
    $checks.Passed++
} catch {
    Write-Host " ✗" -ForegroundColor Red
    $checks.Failed++
}

# Summary
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Checks Passed: $($checks.Passed)/10" -ForegroundColor $(if($checks.Passed -eq 10){'Green'}else{'Yellow'})
Write-Host "Checks Failed: $($checks.Failed)/10" -ForegroundColor $(if($checks.Failed -eq 0){'Green'}else{'Red'})
Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

if ($checks.Passed -eq 10) {
    Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  ✓✓✓ ALL CHECKS PASSED - READY FOR ARC AGENT! ✓✓✓   ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host "`nYou have successfully completed on-premises setup!" -ForegroundColor Green
    Write-Host "Next step: Install Azure Arc agent with proxy config`n" -ForegroundColor Yellow
    Write-Host "➡️  Open: GUIDE-Arc-Agent-Proxy-Config.md`n" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  ✗✗✗ CHECKS FAILED - DO NOT PROCEED! ✗✗✗            ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host "`nFix the failed checks above before moving to Arc agent installation." -ForegroundColor Yellow
    Write-Host "`nCommon fixes:" -ForegroundColor Cyan
    Write-Host "  • Wrong hostname → Rename computer to ArcServer01 and reboot" -ForegroundColor White
    Write-Host "  • Missing deployment file → Copy from host PC to C:\" -ForegroundColor White
    Write-Host "  • pfSense unreachable → Check Hyper-V network, pfSense VM running" -ForegroundColor White
    Write-Host "  • Azure Firewall unreachable → Check VPN status (Step 7 troubleshooting)" -ForegroundColor White
    Write-Host "  • Proxy ports fail → Verify Azure Firewall Explicit Proxy enabled" -ForegroundColor White
    Write-Host "  • Internet NOT blocked → Check pfSense firewall rules (Step 5)" -ForegroundColor White
    Write-Host "  • DNS fails → Check DNS server setting (Step 8)" -ForegroundColor White
    Write-Host "`n" -ForegroundColor White
    exit 1
}
```

**What This Validation Checks:**

✓ **Hostname:** Confirms you're on ArcServer01 (not host PC)
✓ **Deployment File:** Azure deployment info is available
✓ **pfSense Gateway:** Local gateway is reachable
✓ **VPN Tunnel:** Can reach Azure Firewall through VPN
✓ **Proxy Ports:** HTTP (8081) and HTTPS (8443) are accessible
✓ **Security:** Internet is properly blocked (no direct access)
✓ **DNS:** Name resolution works
✓ **DNS Server:** Using Azure Firewall DNS
✓ **Proxy Connectivity:** PowerShell can download via proxy

---

## 🚫 STOP! Do Not Proceed if ANY Check Failed

If the validation script shows failures:

1. **Review the specific failed checks** in the output
2. **Go back to the relevant step** in this guide
3. **Fix the issue** before continuing
4. **Re-run the validation script** until all 10 checks pass

**DO NOT attempt to install Arc agent until all checks pass!**

---

## 📚 Next Steps (Only After Validation Passes)

Once you see **"ALL CHECKS PASSED"** in green:

➡️ **Open:** `GUIDE-Arc-Agent-Proxy-Config.md`

➡️ **Purpose:** Install Azure Arc agent with Explicit Proxy configuration

➡️ **Estimated Time:** 15-20 minutes

---

## 🛠️ Troubleshooting Common Issues

### Issue 1: "Hyper-V feature not available"
**Cause:** Windows Home edition doesn't support Hyper-V  
**Solution:** Upgrade to Windows Pro or use VirtualBox instead

### Issue 2: "VMs are slow"
**Cause:** Insufficient RAM  
**Solution:** Close other applications or increase physical RAM

### Issue 3: "VPN won't establish"
**Cause:** NAT/firewall on host network  
**Solution:** Check if ports UDP 500/4500 are open on host firewall

### Issue 4: "Can't ping Azure Firewall"
**Cause:** VPN not fully established or routing issue  
**Solution:**
```powershell
# On pfSense, check routing table
Diagnostics → Routes → Display

# Should see route to 10.100.0.0/16 via VPN
```

### Issue 5: "DNS doesn't resolve"
**Cause:** Azure Firewall DNS proxy not configured  
**Solution:** Verify firewall policy has DNS proxy enabled (already done in deployment script)

---

**Document Version:** 1.0  
**Last Updated:** November 10, 2025  
**Next Guide:** GUIDE-Arc-Agent-Proxy-Config.md
