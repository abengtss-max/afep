# Lab 4: On-Premises Setup Guide - Hyper-V + OPNsense Firewall + S2S VPN

## 📋 Overview

This guide walks you through setting up the **on-premises environment** on your **Windows 11 PC** to simulate a real datacenter with:
- ✅ Hyper-V virtualization
- ✅ OPNsense Enterprise Firewall (URL filtering + VPN)
- ✅ Windows Server 2022 (Arc-enabled server)
- ✅ Site-to-Site VPN to Azure

**Operating System:** Windows 11 Pro/Enterprise (x64 or ARM64)  
**Time required:** 2-3 hours (first time)

**✅ Platform Compatibility:**
- **Intel/AMD x64:** Full support - Uses Generation 1 VMs (best compatibility)
- **ARM64 (Snapdragon):** Limited support - Generation 2 only, UEFI boot issues with Linux/BSD ISOs

**⚠️ RECOMMENDED:** Use **Intel/AMD x64 hardware** for this lab. ARM64 has significant VM boot compatibility issues.

**⚠️ CRITICAL:** This guide assumes you have **NOT** completed any previous steps. We'll validate everything as we go.

---

## 🎯 What You'll Build

```
Your Windows PC (Physical - ARM64 or x64)
├── WiFi/Ethernet → Internet (stays connected, completely unaffected!)
│
└── Hyper-V Host
    ├── Default Switch (NAT) → Provides internet to VMs via NAT
    │   └── OPNsense WAN gets internet (for VPN only)
    │
    ├── Internal-Lab Switch → Isolated VM network (10.0.1.0/24)
    │
    ├── VM1: OPNsense Firewall
    │   ├── WAN NIC → Default Switch (NAT internet)
    │   ├── LAN NIC → Internal-Lab (10.0.1.1/24)
    │   ├── Enterprise Firewall → URL/FQDN filtering  
    │   ├── VPN Tunnel → Azure VPN Gateway (IPsec over NAT)
    │   ├── Azure Arc Rules → 18+ endpoint filters
    │   └── Security Policies → Block all except allowed URLs
    │
    └── VM2: Windows Server 2022 (Arc Server)
        ├── NIC → Internal-Lab (10.0.1.10/24)
        ├── Gateway → OPNsense (10.0.1.1)
        ├── DNS → Azure Firewall via VPN (10.100.0.4)
        ├── NO direct internet access
        └── Azure Arc Agent → Uses proxy via VPN tunnel
```

**Network Flow:**
- OPNsense WAN uses Hyper-V NAT to reach internet (for VPN)
- Windows Server is completely isolated on Internal-Lab network
- All Arc traffic: Windows Server → OPNsense → VPN Tunnel → Azure Firewall Proxy
- **Your host PC's WiFi/Ethernet remains fully functional - NO DISRUPTION!**

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

### Step 0.3: Configure Azure Firewall Application Rules

**⚠️ CRITICAL:** These rules must be configured **BEFORE** attempting Arc onboarding!

Azure Firewall Explicit Proxy requires **Application Rules** (Network Rules will NOT work) to allow Arc endpoints.

```powershell
# Load deployment info
$deploymentFile = "C:\Users\$env:USERNAME\MyProjects\azfw\scripts\Lab4-Arc-DeploymentInfo.json"
$azureInfo = Get-Content $deploymentFile | ConvertFrom-Json

Write-Host "`n╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Configure Azure Firewall Application Rules  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Resource Group: $($azureInfo.ResourceGroup)" -ForegroundColor Yellow
Write-Host "Firewall: $($azureInfo.AzureFirewall.Name)" -ForegroundColor Yellow
Write-Host "`nYou must create Application Rules in Azure Portal...`n" -ForegroundColor White
```

**Steps to Configure in Azure Portal:**

1. **Open Azure Portal:** https://portal.azure.com

2. **Navigate to Firewall Policy:**
   - Search for "Firewall Policies"
   - Select your policy (should match deployment)

3. **Add Application Rule Collection:**
   - Left menu → **Application Rules**
   - Click **+ Add a rule collection**

4. **Rule Collection Settings:**
   - **Name:** `Arc-Required-Endpoints`
   - **Priority:** `100`
   - **Rule collection action:** `Allow`

5. **Add Rules - Critical Arc Endpoints:**

   **Rule 1: Arc Agent Download**
   - Name: `Allow-Arc-Download`
   - Source type: `IP Address`
   - Source: `*` (or your on-premises subnet, e.g., `10.0.1.0/24`)
   - Protocol: `http:80,https:443`
   - Destination type: `FQDN`
   - Destination:
     ```
     aka.ms
     download.microsoft.com
     *.download.microsoft.com
     packages.microsoft.com
     ```

   **Rule 2: Arc Core Services**
   - Name: `Allow-Arc-Core`
   - Source type: `IP Address`
   - Source: `*`
   - Protocol: `http:80,https:443`
   - Destination type: `FQDN`
   - Destination:
     ```
     *.his.arc.azure.com
     *.guestconfiguration.azure.com
     agentserviceapi.guestconfiguration.azure.com
     ```

   **Rule 3: Azure Management**
   - Name: `Allow-Azure-Management`
   - Source type: `IP Address`
   - Source: `*`
   - Protocol: `http:80,https:443`
   - Destination type: `FQDN`
   - Destination:
     ```
     management.azure.com
     login.microsoftonline.com
     login.windows.net
     pas.windows.net
     ```

   **Rule 4: Extension Services**
   - Name: `Allow-Arc-Extensions`
   - Source type: `IP Address`
   - Source: `*`
   - Protocol: `http:80,https:443`
   - Destination type: `FQDN`
   - Destination:
     ```
     guestnotificationservice.azure.com
     *.guestnotificationservice.azure.com
     *.servicebus.windows.net
     *.blob.core.windows.net
     ```

6. **Click "Add"** to save the rule collection

7. **Verify Rules:**
   - Ensure all 4 rules show under `Arc-Required-Endpoints` collection
   - Priority should be `100`
   - Action should be `Allow`

**⚠️ IMPORTANT:** Wait 2-3 minutes for rules to propagate before proceeding!

**Verification Command:**
```powershell
# Test if proxy can reach Arc endpoints (run AFTER creating rules)
curl -x http://10.100.0.4:8443 https://aka.ms -UseBasicParsing
curl -x http://10.100.0.4:8443 https://management.azure.com -UseBasicParsing
```

✅ **Rules configured? Continue to Step 0.4**

---

### Step 0.4: Check Hardware Requirements

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

# Check virtualization support and processor architecture
$processorArch = (Get-CimInstance Win32_Processor).Architecture
$isARM64 = $processorArch -eq 12  # 12 = ARM64

if ($isARM64) {
    Write-Host "Processor Architecture: ARM64 (Snapdragon/Qualcomm)" -ForegroundColor Yellow
    Write-Host "⚠️  WARNING: ARM64 has limited VM compatibility" -ForegroundColor Yellow
    Write-Host "   - Generation 1 VMs NOT supported" -ForegroundColor White
    Write-Host "   - Generation 2 VMs have UEFI boot issues with Linux/BSD" -ForegroundColor White
    Write-Host "   - OPNsense/pfSense may not boot" -ForegroundColor White
    Write-Host ""
    Write-Host "  ℹ️  Virtualization Check: Open Task Manager" -ForegroundColor Cyan
    Write-Host "     (Ctrl+Shift+Esc) → Performance → CPU" -ForegroundColor White
    Write-Host "     Look for 'Virtualization: Enabled' at the bottom" -ForegroundColor White
    Write-Host ""
    Write-Host "  💡 RECOMMENDATION: Use Intel/AMD x64 hardware instead" -ForegroundColor Yellow
} else {
    Write-Host "Processor Architecture: x64 (Intel/AMD)" -ForegroundColor Green
    Write-Host "✅ Full VM compatibility (Generation 1 and 2 supported)" -ForegroundColor Green
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
}
```

### Step 0.4: Download Windows Server 2022 ISO

**Create download directory:**

```powershell
# Create directory for ISOs
New-Item -ItemType Directory -Path "C:\ISOs" -Force
```

**Download Windows Server 2022 (for Arc Server)**

1. Go to: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
2. Fill in registration form (required by Microsoft)
3. Select: **64-bit edition ISO**
4. Language: **English (United States)**
5. Click "Download"
6. Downloaded filename: `SERVER_EVAL_x64FRE_en-us.iso`
7. Move/copy to: `C:\ISOs\SERVER_EVAL_x64FRE_en-us.iso`
8. Size: ~5 GB
9. Wait for download (may take 10-30 minutes depending on connection)

> **Note:** You'll use the same ISO to install both VMs (Router and Arc Server)

**Verify download:**

```powershell
# Check ISO file exists
$ws2022Iso = "C:\ISOs\SERVER_EVAL_x64FRE_en-us.iso"

if (Test-Path $ws2022Iso) {
    $size = [math]::Round((Get-Item $ws2022Iso).Length / 1MB, 2)
    Write-Host "✓ Windows Server 2022 ISO found ($size MB)" -ForegroundColor Green
} else {
    Write-Host "✗ Windows Server 2022 ISO NOT found at: $ws2022Iso" -ForegroundColor Red
    Write-Host "  Please download from: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022" -ForegroundColor Yellow
}
```

**⚠️ Do NOT proceed until ISO is downloaded!**

### Step 0.5: Download OPNsense Firewall

**Download OPNsense 25.7 (Latest Stable):**

**⚠️ IMPORTANT:** Use **DVD ISO** for Intel/AMD x64 systems (best compatibility)!

1. **Download DVD ISO (Recommended for x64):**
   - **Direct Link:** https://pkg.opnsense.org/releases/25.7/OPNsense-25.7-dvd-amd64.iso.bz2
   - **Size:** ~580 MB compressed (~2 GB extracted)
   - **Works with:** Intel/AMD x64 (Generation 1 VMs)
   - **Boots reliably** on standard PC hardware

2. **Alternative: VGA Image (for reference only):**
   - **Link:** https://pkg.opnsense.org/releases/25.7/OPNsense-25.7-vga-amd64.img.bz2
   - **Size:** ~450 MB compressed
   - **Note:** Requires conversion to VHDX (more complex)

3. **Download and Extract:**

```powershell
# Download DVD ISO to ISOs folder
$downloadUrl = "https://pkg.opnsense.org/releases/25.7/OPNsense-25.7-dvd-amd64.iso.bz2"
$downloadPath = "C:\ISOs\OPNsense-25.7-dvd-amd64.iso.bz2"

# Download using PowerShell (if needed)
if (-not (Test-Path $downloadPath)) {
    Write-Host "Downloading OPNsense..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
    Write-Host "Download complete!" -ForegroundColor Green
}

# Extract compressed image (requires 7-Zip or similar)
# Download 7-Zip if not installed: https://www.7-zip.org/download.html

# Extract using 7-Zip command line
$sevenZipPath = "${env:ProgramFiles}\7-Zip\7z.exe"
if (Test-Path $sevenZipPath) {
    Write-Host "Extracting OPNsense image..." -ForegroundColor Yellow
    & $sevenZipPath x $downloadPath -o"C:\ISOs\" -y
    Write-Host "Extraction complete!" -ForegroundColor Green
} else {
    Write-Host "⚠️ 7-Zip not found. Please:" -ForegroundColor Yellow
    Write-Host "  1. Download 7-Zip from: https://www.7-zip.org/download.html" -ForegroundColor White
    Write-Host "  2. Install 7-Zip" -ForegroundColor White
    Write-Host "  3. Extract OPNsense-25.7-vga-amd64.img.bz2 to C:\ISOs\" -ForegroundColor White
}
```

**Verify Downloads:**

```powershell
# Check both ISOs are ready
$ws2022Iso = "C:\ISOs\SERVER_EVAL_x64FRE_en-us.iso"
$opnsenseIso = "C:\ISOs\OPNsense-25.7-dvd-amd64.iso"

Write-Host "`n=== ISO Verification ===" -ForegroundColor Cyan

if (Test-Path $ws2022Iso) {
    $size = [math]::Round((Get-Item $ws2022Iso).Length / 1GB, 2)
    Write-Host "✓ Windows Server 2022 ISO: $size GB" -ForegroundColor Green
} else {
    Write-Host "✗ Windows Server 2022 ISO missing" -ForegroundColor Red
}

if (Test-Path $opnsenseIso) {
    $size = [math]::Round((Get-Item $opnsenseIso).Length / 1GB, 2)
    Write-Host "✓ OPNsense DVD ISO: $size GB" -ForegroundColor Green
} else {
    Write-Host "✗ OPNsense DVD ISO missing" -ForegroundColor Red
    Write-Host "  Download from: https://opnsense.org/download/" -ForegroundColor Yellow
}
```

```powershell
Write-Host "`n✅ Both ISOs ready! Proceed to Step 1" -ForegroundColor Green
```

**⚠️ Do NOT proceed until BOTH ISOs are downloaded and verified!**

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

**PowerShell Method:**

```powershell
# Open PowerShell as Administrator

# Enable Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Restart required
Restart-Computer
```

### Verify Installation

After restart, open PowerShell and run:

```powershell
# Verify Hyper-V is enabled
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
```

Should show: **State : Enabled**

```powershell
# Launch Hyper-V Manager to confirm GUI works
virtmgmt.msc
```

Hyper-V Manager window should open. You'll use this GUI frequently.

---

## 📝 Step 2: ✅ Virtual Switches Already Created

> **✅ CONNECTIVITY FIX APPLIED**: Your Hyper-V switches are already configured correctly!
> 
> **Current Configuration:**
> - ✅ **Default Switch**: Hyper-V's built-in NAT (internet for VMs)
> - ✅ **Internal-Lab**: VM-to-VM communication (10.0.1.0/24)
> - ✅ **No External switches**: Your WiFi/Ethernet is safe!

> **✅ WiFi-Safe Design**: Uses Hyper-V **Default Switch (NAT)** + **Internal Switch** - Your host WiFi/Ethernet will **NOT** be affected!

### ✅ Verify Your Current Switch Configuration

Your connectivity fix has already created the optimal switch configuration. Let's verify:

```powershell
# Verify current switches
Get-VMSwitch | Format-Table Name, SwitchType, NetAdapterInterfaceDescription -AutoSize

# Expected output:
# Name           SwitchType NetAdapterInterfaceDescription
# ----           ---------- ------------------------------
# Default Switch   Internal
# Internal-Lab     Internal  
# (possibly NAT-Switch Internal if created during fix)

Write-Host "✅ Switch Configuration Verified:" -ForegroundColor Green
Write-Host "  • Default Switch: Provides NAT internet to VMs" -ForegroundColor White
Write-Host "  • Internal-Lab: VM-to-VM communication (10.0.1.0/24)" -ForegroundColor White
Write-Host "  • Your WiFi/Ethernet: Unaffected and working normally" -ForegroundColor Cyan
```

### Create Internal-Lab Switch (If Not Already Created)

Check if the Internal-Lab switch exists, and create it if needed:

```powershell
# Check if Internal-Lab switch exists
$internalSwitch = Get-VMSwitch -Name "Internal-Lab" -ErrorAction SilentlyContinue

if ($internalSwitch) {
    Write-Host "✓ Internal-Lab switch already exists" -ForegroundColor Green
    Write-Host "  This switch provides isolated VM-to-VM communication" -ForegroundColor White
} else {
    Write-Host "Creating Internal-Lab switch..." -ForegroundColor Yellow
    
    # Create Internal-Lab switch for VM-to-VM communication
    New-VMSwitch -Name "Internal-Lab" -SwitchType Internal
    
    # Configure IP address for the Internal-Lab switch on host
    $adapter = Get-NetAdapter | Where-Object { $_.Name -like "*Internal-Lab*" }
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 10.0.1.254 -PrefixLength 24 -ErrorAction SilentlyContinue
    
    Write-Host "✓ Internal-Lab switch created!" -ForegroundColor Green
    Write-Host "  - Type: Internal (VM-to-VM isolation)" -ForegroundColor White
    Write-Host "  - Subnet: 10.0.1.0/24" -ForegroundColor White
    Write-Host "  - Host IP: 10.0.1.254" -ForegroundColor White
}
```

### Verify Switch Configuration

```powershell
Write-Host "`n=== Virtual Switch Summary ===" -ForegroundColor Cyan
Get-VMSwitch | Format-Table Name, SwitchType -AutoSize

Write-Host "`nExpected switches:" -ForegroundColor Yellow
Write-Host "  1. Default Switch (or NAT-Switch) - Provides NAT internet to VMs" -ForegroundColor White
Write-Host "  2. Internal-Lab - Isolated VM-to-VM network (10.0.1.0/24)" -ForegroundColor White
Write-Host "`n✅ Your host WiFi/Ethernet: Unaffected and fully functional!" -ForegroundColor Green
```

### Clean Up External Switches (If Any Exist)

If you previously created an External switch that broke your WiFi, remove it now:

```powershell
Write-Host "`n=== Checking for problematic External switches ===" -ForegroundColor Cyan

# Check for and remove any External switches
$externalSwitches = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" }

if ($externalSwitches) {
    Write-Host "⚠️  Found External switch(es) that may be blocking your WiFi:" -ForegroundColor Yellow
    $externalSwitches | ForEach-Object {
        Write-Host "    - $($_.Name)" -ForegroundColor White
    }
    
    Write-Host "`nRemoving External switches to restore WiFi..." -ForegroundColor Yellow
    $externalSwitches | ForEach-Object {
        Remove-VMSwitch -Name $_.Name -Force
        Write-Host "  ✓ Removed: $($_.Name)" -ForegroundColor Green
    }
    Write-Host "`n✅ WiFi should now be restored!" -ForegroundColor Green
    Write-Host "   Wait 10-30 seconds for your WiFi to reconnect" -ForegroundColor Cyan
} else {
    Write-Host "✓ No External switches found (good!)" -ForegroundColor Green
}
```

**Network Design:**
- **Default Switch / NAT-Switch**: OPNsense WAN gets internet via Hyper-V NAT
- **Internal-Lab**: OPNsense LAN ↔ Windows Server (10.0.1.0/24)
- **Your WiFi/Ethernet**: Completely unaffected - continues working normally!

---

## 📝 Step 3: Create OPNsense Firewall VM

> **✅ If you already created the OPNsense-Lab VM manually**, skip to **Step 3.3: Install OPNsense from ISO** below.

**🛡️ OPNsense Enterprise Firewall Setup**

OPNsense provides **enterprise-grade firewall functionality** with:
- ✅ **URL/FQDN filtering** (essential for Azure Arc endpoints)
- ✅ **VPN capabilities** (IPsec Site-to-Site)
- ✅ **Professional Web GUI** (like commercial firewalls)
- ✅ **Advanced logging and monitoring**

**Platform Notes:**
- **Intel/AMD x64:** Use Generation 1 VMs (best compatibility, boots reliably)
- **ARM64 (Snapdragon):** Generation 2 only, may have UEFI boot issues

### Step 3.1: Create VM with PowerShell (If Not Already Created)

```powershell
# Open PowerShell as Administrator

# Verify OPNsense image exists
$opnsenseImg = "C:\ISOs\OPNsense-25.7-vga-amd64.img"
if (-not (Test-Path $opnsenseImg)) {
    Write-Host "✗ OPNsense image not found!" -ForegroundColor Red
    Write-Host "  Please complete Step 0.5 first" -ForegroundColor Yellow
    exit 1
}

# Detect processor architecture to determine VM generation
$processorArch = (Get-CimInstance Win32_Processor).Architecture
$isARM64 = $processorArch -eq 12
$vmGeneration = if ($isARM64) { 2 } else { 1 }  # Gen 1 for x64, Gen 2 for ARM64

Write-Host "Detected Architecture: $(if($isARM64){'ARM64'}else{'x64 (Intel/AMD)'})" -ForegroundColor Cyan
Write-Host "Using VM Generation: $vmGeneration" -ForegroundColor Yellow
if ($vmGeneration -eq 1) {
    Write-Host "  ✅ Generation 1 = Best compatibility for Linux/BSD" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Generation 2 = Required for ARM64 but may have boot issues" -ForegroundColor Yellow
}

# Create VM folder
New-Item -Path "C:\Hyper-V\OPNsense-Lab" -ItemType Directory -Force

# Create virtual hard disk (32GB minimum for OPNsense ZFS installation)
New-VHD -Path "C:\Hyper-V\OPNsense-Lab\OPNsense-Lab.vhdx" -SizeBytes 32GB -Dynamic

# Create VM with appropriate generation for platform
New-VM -Name "OPNsense-Lab" `
       -MemoryStartupBytes 4GB `
       -Generation $vmGeneration `
       -VHDPath "C:\Hyper-V\OPNsense-Lab\OPNsense-Lab.vhdx" `
       -Path "C:\Hyper-V"

# Configure VM settings for OPNsense (minimum 3GB RAM required for installation)
Set-VM -Name "OPNsense-Lab" -ProcessorCount 2 -DynamicMemory -MemoryStartupBytes 4GB -MemoryMinimumBytes 2GB -MemoryMaximumBytes 8GB

# Use Default Switch for NAT internet access (created during connectivity fix)
$natSwitch = Get-VMSwitch | Where-Object { $_.Name -eq "Default Switch" } | Select-Object -First 1

if (-not $natSwitch) {
    Write-Host "✗ Default Switch not found! This should exist automatically in Hyper-V." -ForegroundColor Red
    Write-Host "  Try restarting Hyper-V service or reboot your PC" -ForegroundColor Yellow
    exit 1
}

Write-Host "Using Default Switch for OPNsense WAN (internet access)" -ForegroundColor Cyan

# Add second network adapter for LAN (VM has 1 by default for WAN)
Add-VMNetworkAdapter -VMName "OPNsense-Lab" -SwitchName "Internal-Lab"

# Connect first adapter to Default Switch (WAN interface)  
Get-VMNetworkAdapter -VMName "OPNsense-Lab" | Select-Object -First 1 | Connect-VMNetworkAdapter -SwitchName "Default Switch"

Write-Host "✓ Network adapters configured:" -ForegroundColor Green
Write-Host "  - Adapter 1 (WAN): $($natSwitch.Name) - Internet via NAT (no impact on host WiFi)" -ForegroundColor White
Write-Host "  - Adapter 2 (LAN): Internal-Lab - VM network (10.0.1.0/24)" -ForegroundColor White

# Configure boot settings based on VM generation
if ($vmGeneration -eq 2) {
    # Generation 2: Configure UEFI firmware and disable Secure Boot for FreeBSD
    Set-VMFirmware -VMName "OPNsense-Lab" -EnableSecureBoot Off
    
    # Set boot order for Gen 2
    $dvd = Get-VMDvdDrive -VMName "OPNsense-Lab"
    $hd = Get-VMHardDiskDrive -VMName "OPNsense-Lab"
    Set-VMFirmware -VMName "OPNsense-Lab" -BootOrder $dvd,$hd
    
    Write-Host "✓ Generation 2: UEFI boot configured (Secure Boot disabled)" -ForegroundColor Green
} else {
    # Generation 1: Uses legacy BIOS (no firmware configuration needed)
    Write-Host "✓ Generation 1: Legacy BIOS boot (best compatibility)" -ForegroundColor Green
}

# Note: Nested virtualization disabled - not needed for OPNsense and may cause boot issues on some platforms

# Disable checkpoints (saves disk space)
Set-VM -Name "OPNsense-Lab" -CheckpointType Disabled

Write-Host "✓ OPNsense VM created successfully!" -ForegroundColor Green
Write-Host "`nNext: Install OPNsense from image..." -ForegroundColor Yellow
```

### Step 3.2: Verify VM is Ready

```powershell
# Verify OPNsense VM configuration
Get-VM -Name "OPNsense-Lab" | Format-List Name, State, CPUUsage, MemoryAssigned, MemoryDemand

# Check network adapters
Get-VMNetworkAdapter -VMName "OPNsense-Lab" | Format-Table Name, SwitchName, MacAddress -AutoSize

# Expected output:
# - 2 network adapters
# - Adapter 1: Default Switch (WAN)
# - Adapter 2: Internal-Lab (LAN)
```

### Step 3.3: Install OPNsense from ISO

> **📍 YOU ARE HERE** if you manually created the VM following my instructions.

**Download OPNsense DVD ISO:**

```powershell
# Download OPNsense DVD ISO (easier than .img method)
$downloadUrl = "https://pkg.opnsense.org/releases/25.7/OPNsense-25.7-dvd-amd64.iso.bz2"
$downloadPath = "C:\ISOs\OPNsense-25.7-dvd-amd64.iso.bz2"

Write-Host "Downloading OPNsense DVD ISO (~580 MB compressed)..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing

Write-Host "✓ Download complete!" -ForegroundColor Green
Write-Host "Extracting ISO..." -ForegroundColor Yellow

# Extract with 7-Zip
$sevenZip = "${env:ProgramFiles}\7-Zip\7z.exe"
if (Test-Path $sevenZip) {
    & $sevenZip x $downloadPath -o"C:\ISOs\" -y
    Write-Host "✓ ISO ready: C:\ISOs\OPNsense-25.7-dvd-amd64.iso" -ForegroundColor Green
} else {
    Write-Host "⚠️ Install 7-Zip first: https://www.7-zip.org/download.html" -ForegroundColor Yellow
    Write-Host "Then manually extract the .bz2 file to C:\ISOs\" -ForegroundColor White
}
```

**Mount ISO and Start VM:**

```powershell
# Verify ISO exists
if (-not (Test-Path "C:\ISOs\OPNsense-25.7-dvd-amd64.iso")) {
    Write-Host "✗ ISO not found! Extract the .bz2 file first" -ForegroundColor Red
    exit 1
}

# Mount ISO to VM
Set-VMDvdDrive -VMName "OPNsense-Lab" -Path "C:\ISOs\OPNsense-25.7-dvd-amd64.iso"

# Disable nested virtualization if your platform doesn't support it
Set-VMProcessor -VMName "OPNsense-Lab" -ExposeVirtualizationExtensions $false

# Start VM
Start-VM -Name "OPNsense-Lab"

# Open console
vmconnect localhost "OPNsense-Lab"

Write-Host "`n✓ VM started with OPNsense ISO mounted" -ForegroundColor Green
Write-Host "Follow the installation wizard in the VM console window" -ForegroundColor Yellow
```

### Step 3.4: OPNsense Installation Wizard

The VM console will show the OPNsense installer automatically. Follow these steps carefully:

**1. Network Interface Assignment (First Screen):**
   
   OPNsense will immediately show detected interfaces:
   ```
   Valid interfaces are:
   hn0    00:15:5d:44:6e:01 Hyper-V Network Interface
   hn1    00:15:5d:44:6e:02 Hyper-V Network Interface
   
   If you do not know the names of your interfaces, you may choose to use
   auto-detection. In that case, disconnect all interfaces now before
   hitting 'a' to initiate auto detection.
   
   Enter the WAN interface name or 'a' for auto-detection:
   ```
   
   - Type: **`hn0`** (WAN = Default Switch for internet)
   - Press **Enter**
   - You'll see: "Note: this enables full firewalling/nat mode."
   - Press **Enter** to continue
   
   ```
   Enter the LAN interface name or 'a' for auto-detection:
   ```
   
   - Type: **`hn1`** (LAN = Internal-Lab for VMs)
   - Press **Enter**
   
   ```
   Enter the Optional interface name or 'a' for auto-detection
   (or nothing if finished):
   ```
   
   - Press **Enter** (leave empty, no optional interfaces)
   
   **Wait 10-30 seconds** for "No link-up detected" messages to clear (this is normal)

**2. Keymap Selection:**
   ```
   The system console driver for FreeBSD defaults to standard "US"
   keyboard map. Other keymaps can be chosen below.
   
   >>> Continue with default keymap
       Test default keymap
       ( ) Armenian phonetic layout
       ( ) Belarusian
       ...
   ```
   - Press **Enter** to accept default US keymap
   - Or use arrow keys to select your keyboard layout

**3. Installation Menu:**
   ```
   OPNsense 25.7
   
   Choose one of the following tasks to perform.
   
   Install (ZFS)     ZFS GPT/UEFI Hybrid
   Install (UFS)     UFS GPT/UEFI Hybrid
   Other Modes >>    Extended Installation
   Import Config     Load Configuration
   Password Reset    Recover Installation
   Force Reboot      Reboot System
   Force Halt        Power Down System
   ```
   - Select **Install (ZFS)** (should be highlighted by default)
   - Press **Enter**

**4. ZFS Pool Type:**
   ```
   >>> stripe - No redundancy, no parity, fast
       mirror - N-Way mirroring
       raid10 - Striped mirror pairs
       raidz1 - Single parity RAID
       raidz2 - Double parity RAID
       raidz3 - Triple parity RAID
   ```
   - Select **stripe** (single disk, no redundancy needed)
   - Press **Enter**

**5. Select Disk:**
   ```
   [ ] ada0    32.0 GB    MSFT Virtual HD
   ```
   - Press **Spacebar** to select the disk (checkbox shows [X])
   - Press **Enter**

**6. Last Chance Confirmation:**
   ```
   !!! WARNING !!!
   
   Destruction of data on the target device is imminent!
   A BACKUP is advised.
   
   <<< Cancel    Destroy >>>
   ```
   - Use arrow keys or Tab to select **Destroy**
   - Press **Enter**

**7. Installation Progress (5-10 minutes):**
   
   The installer will:
   - Create ZFS pool and filesystems
   - Extract base system (~600 MB)
   - Install packages
   - Configure bootloader
   
   You'll see progress:
   ```
   Fetching distribution files...
   Extracting FreeBSD base system...
   Installing OPNsense packages...
   Configuring system...
   ```
   
   **Wait patiently** - this takes 5-10 minutes depending on ISO speed

**8. Root Password:**
   ```
   Please select a password for the root user:
   
   New Password: 
   ```
   - Type a strong password (e.g., `OPNsense2024!`)
   - Press **Enter**
   
   ```
   Retype New Password:
   ```
   - Retype the same password
   - Press **Enter**
   - **IMPORTANT:** Write down this password! You'll need it after ejecting the ISO.

**9. Installation Complete:**
   ```
   Installation Complete!
   
   Would you like to enter the shell to perform manual configuration?
   
   No / Yes
   ```
   - Select **No** (we'll configure via console menu)
   - Press **Enter**

**10. Reboot:**
   ```
   The system will now reboot...
   ```
   - VM will restart automatically
   - **Wait for boot** - you'll see OPNsense loading

**11. ⚠️ CRITICAL: You'll Boot into Live Mode First!**
   
   After reboot, you'll see this message:
   ```
   OPNsense is running in live mode from install media. Please
   login as 'root' to continue in live mode, or as 'installer' to start the
   installation. Use the default or previously-imported root password for
   both accounts.
   ```
   
   **This is expected!** The ISO is still mounted, so it boots from the DVD in live mode.
   
   **DO NOT try to login here.** The password you set during installation doesn't work in live mode.
   
   **Eject the ISO immediately:**
   
   In PowerShell (Administrator):
   ```powershell
   # Stop VM
   Stop-VM -Name "OPNsense-Lab" -Force
   
   # Eject ISO (critical step!)
   Set-VMDvdDrive -VMName "OPNsense-Lab" -Path $null
   
   # Verify ISO is ejected
   Get-VMDvdDrive -VMName "OPNsense-Lab"
   # Should show: Path = (empty)
   
   # Restart VM (will boot from installed system on hard disk now)
   Start-VM -Name "OPNsense-Lab"
   
   # Reconnect to console
   vmconnect localhost "OPNsense-Lab"
   ```
   
   **Wait 30-60 seconds for OPNsense to boot from the hard disk.**

### Step 3.5: Initial OPNsense Configuration

After the VM reboots from hard disk (takes 30-60 seconds), you'll see the OPNsense login prompt:

```
OPNsense 25.7 (amd64)
opnsense.localdomain

login:
```

**✅ Now you can login with YOUR password:**
- Username: **`root`**
- Password: **[the password you set during installation in Step 8]**
- Press **Enter**

**⚠️ If you still see "live mode" message:** Go back to Step 11 and eject the ISO!

**Main Console Menu:**

After login, you'll see the console menu:

```
*** OPNsense.localdomain: OPNsense 25.7 (amd64/OpenSSL) ***

  0) Logout                              7) Ping host
  1) Assign interfaces                   8) Shell
  2) Set interface(s) IP address         9) pfTop
  3) Reset the root password            10) Firewall log
  4) Reset to factory defaults          11) Reload all services
  5) Power off system                   12) Update from console
  6) Reboot system                      13) Restore configuration

Enter an option:
```

**Configure LAN IP Address:**

```
*** Welcome to OPNsense ***
WAN (wan)   -> hn0 -> [getting IP via DHCP...]
LAN (lan)   -> hn1 -> 192.168.1.1

0) Logout
1) Assign Interfaces
2) Set interface(s) IP address
...
Enter an option:
```

**1. Set LAN IP:**
   - Type: `2` (Set interface(s) IP address)
   - Press **Enter**

**2. Select LAN:**
   ```
   Available interfaces:
   1 - WAN
   2 - LAN
   
   Enter the number of the interface:
   ```
   - Type: `2`
   - Press **Enter**

**3. Configure IPv4 Address:**
   ```
   Enter the new LAN IPv4 address:
   ```
   - Type: `10.0.1.1`
   - Press **Enter**

**4. Subnet Mask:**
   ```
   Enter the new LAN IPv4 subnet bit count (1-32):
   ```
   - Type: `24`
   - Press **Enter**

**5. Upstream Gateway:**
   ```
   For a LAN, press <ENTER> for none:
   ```
   - Just press **Enter** (no gateway for LAN)

**6. IPv6 Configuration:**
   ```
   Configure IPv6 address LAN interface via DHCP6? [y/n]:
   ```
   - Type: `n`
   - Press **Enter**

**7. DHCP Server:**
   ```
   Do you want to enable the DHCP server on LAN? [y/n]:
   ```
   - Type: `y` (enable DHCP)
   - Press **Enter**

**8. DHCP Start Address:**
   ```
   Enter the start address of the range:
   ```
   - Type: `10.0.1.100`
   - Press **Enter**

**9. DHCP End Address:**
   ```
   Enter the end address of the range:
   ```
   - Type: `10.0.1.200`
   - Press **Enter**

**10. HTTP Protocol:**
   ```
   Do you want to revert to HTTP as the webConfigurator protocol? [y/n]:
   ```
   - Type: `y` (use HTTP for easier access)
   - Press **Enter**

**Success Message:**

```
The IPv4 LAN address has been set to 10.0.1.1/24
You can now access the webConfigurator by opening http://10.0.1.1/
```

**Write down:**
- **URL:** http://10.0.1.1
- **Username:** root
- **Password:** (your password from installation)

Press **Enter** to return to main menu.

**✅ OPNsense Installation Complete!**

Your OPNsense firewall is now:
- ✅ Installed and running
- ✅ WAN interface on Default Switch (will get NAT internet)
- ✅ LAN interface on 10.0.1.1/24
- ✅ DHCP server enabled (10.0.1.100-200)
- ✅ Web interface accessible at http://10.0.1.1

**Next:** Access the web interface from your host PC to configure VPN and firewall rules.

---

## 📝 Step 4: Create Windows Server 2022 VM

### PowerShell Method

```powershell
# Open PowerShell as Administrator

# Create VM folder
New-Item -Path "C:\Hyper-V\ArcServer-Lab" -ItemType Directory -Force

# Create virtual hard disk (40 GB)
New-VHD -Path "C:\Hyper-V\ArcServer-Lab\ArcServer-Lab.vhdx" -SizeBytes 40GB -Dynamic

# Create VM (Generation 2 for Windows Server 2022)
New-VM -Name "ArcServer-Lab" `
       -MemoryStartupBytes 4GB `
       -Generation 2 `
       -BootDevice VHD `
       -VHDPath "C:\Hyper-V\ArcServer-Lab\ArcServer-Lab.vhdx" `
       -Path "C:\Hyper-V"

# Configure processor (2 vCPUs)
Set-VMProcessor -VMName "ArcServer-Lab" -Count 2

# Connect network adapter to Internal-Lab (OPNsense LAN)
Get-VMNetworkAdapter -VMName "ArcServer-Lab" | Connect-VMNetworkAdapter -SwitchName "Internal-Lab"

# Add DVD drive and mount Windows Server ISO
Add-VMDvdDrive -VMName "ArcServer-Lab" -Path "C:\ISOs\SERVER_EVAL_x64FRE_en-us.iso"

# Set boot order (DVD first for installation)
$dvd = Get-VMDvdDrive -VMName "ArcServer-Lab"
Set-VMFirmware -VMName "ArcServer-Lab" -FirstBootDevice $dvd

# Disable Secure Boot (optional, but sometimes helps with installation)
Set-VMFirmware -VMName "ArcServer-Lab" -EnableSecureBoot Off

# Disable checkpoints (saves disk space)
Set-VM -Name "ArcServer-Lab" -CheckpointType Disabled

# Start VM
Start-VM -Name "ArcServer-Lab"

# Connect to VM console
vmconnect localhost "ArcServer-Lab"
```

**⚠️ Important:** Windows Server installation will begin automatically in the console window.

### Install Windows Server 2022 (In VM Console)

The VM console will show Windows Setup. Follow these steps:

1. **Windows Setup - Language:**
   - Language to install: `English (United States)`
   - Time and currency format: `English (United States)`
   - Keyboard or input method: `US`
   - Click **Next**

2. **Install Now:**
   - Click **Install now** (center of screen)
   - Wait 10-20 seconds for setup to load

3. **Activate Windows:**
   ```
   Enter the product key to activate Windows
   ```
   - Click **I don't have a product key** (bottom)
   - We'll use evaluation version (180 days free)

4. **Select Operating System:**
   ```
   Select the operating system you want to install:
   
   [ ] Windows Server 2022 Standard
   [ ] Windows Server 2022 Standard (Desktop Experience)
   [ ] Windows Server 2022 Datacenter
   [ ] Windows Server 2022 Datacenter (Desktop Experience)
   ```
   - Select: **Windows Server 2022 Standard (Desktop Experience)**
   - **Important:** Choose "Desktop Experience" to get GUI!
   - Click **Next**

5. **License Terms:**
   - Check: **I accept the Microsoft Software License Terms**
   - Click **Next**

6. **Installation Type:**
   ```
   Which type of installation do you want?
   
   Upgrade: Install Windows and keep files, settings, and applications
   Custom: Install Windows only (advanced)
   ```
   - Select: **Custom: Install Windows only (advanced)**
   - Click

7. **Where do you want to install Windows?**
   ```
   Drive 0 Unallocated Space    40.0 GB
   ```
   - Select the unallocated space (should be only option)
   - Click **Next**

8. **Installing Windows:**
   - Installation will begin (takes 10-15 minutes)
   - Progress stages:
     * Copying Windows files (0-10%)
     * Getting files ready for installation (10-30%)
     * Installing features (30-60%)
     * Installing updates (60-90%)
     * Finishing up (90-100%)
   - **VM will reboot automatically** during installation (normal)

9. **Customize Settings (After Reboot):**
   ```
   Customize settings
   
   Administrator
   
   Enter a password for the built-in administrator account.
   ```
   - **Password:** Type a strong password (e.g., `P@ssw0rd123!`)
   - **Reenter password:** Type same password
   - Click **Finish**

10. **First Login:**
    - Press **Ctrl+Alt+End** (in Hyper-V, this sends Ctrl+Alt+Del)
    - Or: Click Action → Ctrl+Alt+Delete (menu bar)
    - Enter your administrator password
    - Press **Enter**

**Windows Server will load (30-60 seconds). Server Manager opens automatically.**

### Initial Server Configuration

**Configure Static IP Address:**

1. **Open Network Settings:**
   - In **Server Manager**, click **Local Server** (left panel)
   - Find **Ethernet** (should show "IPv4 address assigned by DHCP")
   - Click on **Ethernet** (the blue text)

2. **Network Connections Window Opens:**
   - Right-click **Ethernet** → **Properties**

3. **Configure IPv4:**
   - Scroll down and select **Internet Protocol Version 4 (TCP/IPv4)**
   - Click **Properties**

4. **Set Static IP:**
   - Select: **Use the following IP address:**
   - Fill in:
     ```
     IP address:         10.0.1.10
     Subnet mask:        255.255.255.0
     Default gateway:    10.0.1.1
     ```
   - Select: **Use the following DNS server addresses:**
     ```
     Preferred DNS server:  10.0.1.1
     Alternate DNS server:  (leave empty)
     ```
   - Click **OK**
   - Click **Close**

5. **Verify Network:**
   - Open **PowerShell** (search in Start menu)
   - Run:
   ```powershell
   # Check IP configuration
   Get-NetIPAddress -InterfaceAlias Ethernet -AddressFamily IPv4
   
   # Test OPNsense connectivity
   Test-NetConnection 10.0.1.1
   ```
   - Should show: **PingSucceeded : True**

**Change Computer Name:**

1. **In Server Manager:**
   - Click **Local Server** (if not already there)
   - Find **Computer name:** (shows something like "WIN-ABCD1234")
   - Click on the computer name (blue text)

2. **System Properties Window:**
   - Click **Change...** button

3. **Computer Name/Domain Changes:**
   - Computer name: Type `ArcServer01`
   - Leave "Member of: Workgroup" selected
   - Click **OK**

4. **Restart Required:**
   ```
   You must restart your computer to apply these changes.
   ```
   - Click **OK**
   - Click **Close**
   - Click **Restart Now**

5. **After Restart:**
   - Login again (Ctrl+Alt+End, then password)
   - Verify computer name in PowerShell:
   ```powershell
   $env:COMPUTERNAME
   # Should show: ArcServer01
   ```

**✓ Windows Server VM is now ready!**

---

## 📝 Step 5: Configure OPNsense Azure Arc Firewall Rules

**🛡️ Enterprise Firewall Configuration for Azure Arc**

This section configures OPNsense with **enterprise-grade security policies** that allow only specific Azure Arc endpoints while blocking all other internet access.

### Access OPNsense Web Interface

From your **Windows 11 PC** (host computer):

1. **Open Web Browser:** Chrome/Edge
2. **Navigate to:** `http://10.0.1.1`
3. **Login:**
   - **Username:** `root`
   - **Password:** (password you set during installation)

### 🔒 Configure Security Policies

**Security Objective:** Block all internet access except Azure Arc endpoints (realistic customer environment)

#### Step 5.1: Create Alias for Azure Arc Endpoints

1. **Navigate:** Firewall → Aliases → Hosts

2. **Create "AzureArc_Endpoints" Alias:**
   - Click **"+"** (Add new alias)
   - **Name:** `AzureArc_Endpoints`
   - **Type:** `Host(s)`
   - **Description:** `Azure Arc Required Endpoints`

3. **Add All Azure Arc URLs:**

   **Core Azure AD Endpoints:**
   ```
   login.microsoftonline.com
   login.microsoft.com
   login.windows.net
   pas.windows.net
   ```

   **Azure Resource Manager:**
   ```
   management.azure.com
   ```

   **Azure Arc Services:**
   ```
   *.his.arc.azure.com
   *.guestconfiguration.azure.com
   guestnotificationservice.azure.com
   *.guestnotificationservice.azure.com
   ```

   **Service Bus & Storage:**
   ```
   *.servicebus.windows.net
   *.blob.core.windows.net
   ```

   **Download & Package Management:**
   ```
   download.microsoft.com
   *.download.microsoft.com
   packages.microsoft.com
   ```

   **Regional Endpoints (replace 'eastus2' with your region):**
   ```
   *.eastus2.arcdataservices.com
   ```

   **Additional Services:**
   ```
   dc.services.visualstudio.com
   www.microsoft.com
   dls.microsoft.com
   ```

4. **Save Alias:** Click **Save**

#### Step 5.2: Create DNS Resolver Configuration

1. **Navigate:** Services → Unbound DNS → General

2. **Enable DNS over HTTPS (DoH):**
   - **Enable:** Check
   - **Listen Port:** `53`

3. **Configure Upstream DNS:**
   - **DNS over TLS:** Enable
   - **DNS Servers:** 
     ```
     1.1.1.1@853
     8.8.8.8@853
     ```

4. **Advanced Options:**
   - **Register DHCP leases:** Check
   - **Register DHCP static mappings:** Check

5. **Apply Changes**

#### Step 5.3: Configure Firewall Rules for Azure Arc

**Navigation:** Firewall → Rules → LAN

**Delete Default Allow Rule:**
1. Find "Default allow LAN to any rule"
2. Click **🗑️** (delete)
3. **Apply Changes**

**Create Azure Arc Allow Rules:**

**Rule 1: Allow LAN to OPNsense**
- **Action:** Pass ✅
- **Interface:** LAN
- **Direction:** in
- **TCP/IP Version:** IPv4
- **Protocol:** Any
- **Source:** LAN net
- **Destination:** This firewall (self)
- **Description:** `Allow LAN to OPNsense management`
- **Save**

**Rule 2: Allow Azure Arc HTTPS Traffic**
- **Action:** Pass ✅
- **Interface:** LAN  
- **Direction:** in
- **TCP/IP Version:** IPv4
- **Protocol:** TCP
- **Source:** LAN net
- **Destination:** AzureArc_Endpoints (alias)
- **Destination Port:** HTTPS (443)
- **Description:** `Allow Azure Arc HTTPS endpoints`
- **Save**

**Rule 3: Allow Azure Arc HTTP Traffic**
- **Action:** Pass ✅
- **Interface:** LAN
- **Direction:** in  
- **TCP/IP Version:** IPv4
- **Protocol:** TCP
- **Source:** LAN net
- **Destination:** AzureArc_Endpoints (alias)
- **Destination Port:** HTTP (80)
- **Description:** `Allow Azure Arc HTTP endpoints (redirects to HTTPS)`
- **Save**

**Rule 4: Allow DNS**
- **Action:** Pass ✅
- **Interface:** LAN
- **Direction:** in
- **TCP/IP Version:** IPv4
- **Protocol:** TCP/UDP
- **Source:** LAN net
- **Destination:** This firewall (self)
- **Destination Port:** DNS (53)
- **Description:** `Allow DNS queries to OPNsense`
- **Save**

**Rule 5: Allow VPN Traffic (Azure Network)**
- **Action:** Pass ✅
- **Interface:** LAN
- **Direction:** in
- **TCP/IP Version:** IPv4
- **Protocol:** Any
- **Source:** LAN net
- **Destination:** 10.100.0.0/16
- **Description:** `Allow traffic to Azure VNet via VPN`
- **Save**

**Rule 6: Block Everything Else (Explicit Deny)**
- **Action:** Block 🚫
- **Interface:** LAN
- **Direction:** in
- **TCP/IP Version:** IPv4
- **Protocol:** Any
- **Source:** LAN net
- **Destination:** Any
- **Description:** `Block all other internet traffic`
- **Log:** Check (to monitor blocked attempts)
- **Save**

6. **Apply Changes** - Click **Apply Changes**

#### Step 5.4: Advanced URL Filtering (Optional but Recommended)

**For even more precise control:**

1. **Navigate:** Services → Web Proxy → Administration

2. **Enable Proxy:**
   - **Enable proxy:** Check
   - **Proxy port:** `3128`
   - **Visible hostname:** `opnsense-proxy`

3. **Configure Transparent Proxy:**
   - **Transparent proxy:** Check
   - **Transparent proxy HTTPS:** Check

4. **URL Filter Categories:**
   - **Enable access logging:** Check
   - **Enable URL filter:** Check

5. **Create Custom Category:**
   - **Name:** `AzureArc_Allowed`
   - **URLs:** (paste all Azure Arc URLs)
   - **Action:** Allow

6. **Default Policy:** Block All

**Apply Configuration**

### 🧪 Test Firewall Configuration

From **ArcServer01** (after it's created and configured):

**Test 1: Verify Internet is Blocked**
```cmd
# This should FAIL (blocked by firewall)
ping google.com
curl http://google.com
```

**Test 2: Verify Azure Arc Endpoints Work**
```powershell
# These should SUCCESS (allowed by firewall rules)
Test-NetConnection login.microsoftonline.com -Port 443
Test-NetConnection management.azure.com -Port 443
```

**Test 3: Verify VPN Network Access**
```powershell
# After VPN is configured, this should work
Test-NetConnection 10.100.0.4 -Port 443
```

### 📊 Monitor Firewall Activity

**Real-time Monitoring:**
1. **Navigate:** Firewall → Log Files → Live View
2. **Filter:** Interface = LAN
3. **Watch:** Blocked attempts and allowed traffic
4. **Verify:** Only Azure Arc URLs are allowed

**Analytics Dashboard:**
1. **Navigate:** Reporting → Firewall
2. **View:** Top blocked destinations
3. **Confirm:** Non-Arc URLs are being blocked

**✅ Security Validation:**
- ✅ Internet access blocked (except Arc endpoints)
- ✅ Azure Arc URLs allowed and working
- ✅ VPN traffic permitted
- ✅ Logging enabled for audit trail

This configuration **mimics real enterprise firewall policies** where internet access is restricted and only business-critical services are permitted.
   - **Source:** LAN net
   - **Destination:** This firewall (self)
   - **Description:** "Allow access to OPNsense WebGUI and DNS"
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
   # Should SUCCEED - OPNsense is reachable
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

### Configure IPsec VPN on OPNsense

1. **Navigate:** VPN → IPsec → Tunnels

2. **Add P1 (Phase 1):**
   - Click "↑ Add P1"
   - **General Information:**
     - Disabled: ☐ (unchecked)
     - Key Exchange version: `IKEv2`
     - Internet Protocol: `IPv4`
     - Interface: `WAN` (connected to Default Switch/NAT)
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

# Test 1: OPNsense local gateway
Write-Host "[1/6] Testing OPNsense local gateway (10.0.1.1)..." -NoNewline
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
        Write-Host "  1. Check OPNsense VPN status: Status → IPsec → Overview" -ForegroundColor White
        Write-Host "  2. Verify Azure VPN connection: Azure Portal → VPN Gateway → Connections" -ForegroundColor White
        Write-Host "  3. Check firewall rules on OPNsense: Firewall → Rules → LAN" -ForegroundColor White
        Write-Host "  4. Review troubleshooting section below`n" -ForegroundColor White
    }
}
```

### Additional Manual Verification

**From OPNsense WebGUI:**

1. **Check VPN Status:**
   - Navigate: **Status → IPsec → Overview**
   - Look for your tunnel entry
   - Status should show: **ESTABLISHED** (green)
   - If shows "CONNECTING" or red, VPN is NOT working

2. **Test Ping from OPNsense:**
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

## � Setup Summary - What You've Built

By completing this guide, you've created a complete on-premises simulation:

### ✅ Infrastructure Components

**Hyper-V Environment:**
- ✓ 2 Virtual Switches (External + Internal-Lab)
- ✓ 2 Virtual Machines (OPNsense + Windows Server)
- ✓ Isolated network topology simulating real datacenter

**OPNsense Firewall:**
- ✓ Configured with WAN (internet) + LAN (10.0.1.0/24)
- ✓ DHCP server for LAN network
- ✓ Firewall rules blocking all direct internet access
- ✓ IPsec S2S VPN tunnel to Azure (IKEv2)
- ✓ Phase 1 + Phase 2 VPN configuration

**Windows Server 2022 (ArcServer01):**
- ✓ Static IP: 10.0.1.10/24
- ✓ Gateway: OPNsense (10.0.1.1)
- ✓ DNS: Azure Firewall via VPN (10.100.0.4)
- ✓ NO direct internet access (security validated)
- ✓ Can reach Azure resources via VPN only

**Azure Side (Created by Deploy-Lab4 Script):**
- ✓ VPN Gateway with public IP
- ✓ Local Network Gateway (your public IP)
- ✓ S2S VPN connection (Connected status)
- ✓ Azure Firewall with Explicit Proxy enabled
- ✓ 18 application rules for Arc endpoints

### 🔒 Security Validation

Your setup now enforces:
- ✗ Direct internet access **BLOCKED**
- ✓ VPN tunnel to Azure **WORKING**
- ✓ Proxy access (8081/8443) **WORKING**
- ✓ All traffic must go through Azure Firewall

### 📈 Network Flow

```
ArcServer01 (10.0.1.10)
    ↓
OPNsense LAN (10.0.1.1)
    ↓
VPN Tunnel (encrypted IPsec)
    ↓
Azure VPN Gateway (Public IP)
    ↓
Azure Firewall (10.100.0.4)
    ↓
Azure Arc Endpoints (via proxy 8081/8443)
```

### ⏱️ Time Spent

| Component | Setup Time |
|-----------|------------|
| Hyper-V + Switches | 10-15 min |
| OPNsense VM Install | 20-30 min |
| Windows Server Install | 20-30 min |
| OPNsense Configuration | 15-20 min |
| VPN Setup | 15-20 min |
| **Total** | **80-115 min** |

---

## �🚨 VPN Troubleshooting (If Tests Failed)

### Troubleshooting if VPN Doesn't Connect

1. **Check OPNsense IPsec logs:**
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

# Check 3: OPNsense gateway
Write-Host "[3/10] Testing OPNsense gateway (10.0.1.1)..." -NoNewline
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
    Write-Host "  • OPNsense unreachable → Check Hyper-V network, OPNsense VM running" -ForegroundColor White
    Write-Host "  • Azure Firewall unreachable → Check VPN status (Step 7 troubleshooting)" -ForegroundColor White
    Write-Host "  • Proxy ports fail → Verify Azure Firewall Explicit Proxy enabled" -ForegroundColor White
    Write-Host "  • Internet NOT blocked → Check OPNsense firewall rules (Step 5)" -ForegroundColor White
    Write-Host "  • DNS fails → Check DNS server setting (Step 8)" -ForegroundColor White
    Write-Host "`n" -ForegroundColor White
    exit 1
}
```

**What This Validation Checks:**

✓ **Hostname:** Confirms you're on ArcServer01 (not host PC)
✓ **Deployment File:** Azure deployment info is available
✓ **OPNsense Gateway:** Local gateway is reachable
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
# On OPNsense, check routing table
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
