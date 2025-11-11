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

# Check virtualization support (works on both x64 and ARM64)
$processorArch = (Get-CimInstance Win32_Processor).Architecture
$isARM64 = $processorArch -eq 12  # 12 = ARM64

if ($isARM64) {
    Write-Host "Processor Architecture: ARM64 (Snapdragon/Qualcomm)" -ForegroundColor Cyan
    Write-Host "Virtualization Check: ✓ Verify manually in Task Manager" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ℹ️  ARM64 Note: PowerShell check doesn't work on ARM processors" -ForegroundColor Yellow
    Write-Host "     Open Task Manager (Ctrl+Shift+Esc) → Performance → CPU" -ForegroundColor White
    Write-Host "     Look for 'Virtualization: Enabled' at the bottom" -ForegroundColor White
    Write-Host ""
    Write-Host "  ✓ If Task Manager shows 'Enabled', you're good to proceed!" -ForegroundColor Green
} else {
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

### Step 0.4: Download Required ISOs

**Create download directory:**

```powershell
# Create directory for ISOs
New-Item -ItemType Directory -Path "C:\ISOs" -Force
```

**Download 1: pfSense**

> **IMPORTANT**: pfSense downloads as `.iso.gz` (compressed), you must **extract** it first!

1. Open browser and go to: https://www.pfsense.org/download/
2. Configuration:
   - **Architecture:** AMD64 (64-bit)
   - **Installer:** DVD Image (ISO)
   - **Mirror:** Choose closest location
3. Click "Download"
4. You'll get: `netgate-installer-amd64.iso.gz` (compressed file ~320 MB)
   > **Note**: The downloaded file may have a generic name like `netgate-installer-amd64.iso.gz`
5. **Extract the ISO**:
   - **Option A (7-Zip - Recommended)**: 
     - Download 7-Zip from https://www.7-zip.org/ if not installed
     - Right-click the `.iso.gz` file → "7-Zip" → "Extract Here"
     - Move extracted ISO to `C:\ISOs\pfSense-CE-2.7.2-RELEASE-amd64.iso`
   
   - **Option B (PowerShell)**:
     ```powershell
     # Find the downloaded .gz file (may have different name)
     $gzFile = "$env:USERPROFILE\Downloads\netgate-installer-amd64.iso.gz"
     $isoFile = "C:\ISOs\pfSense-CE-2.7.2-RELEASE-amd64.iso"
     
     # Create ISOs directory
     New-Item -ItemType Directory -Path "C:\ISOs" -Force | Out-Null
     
     # Extract (using proper variable names to avoid $input conflict)
     $inputStream = [System.IO.File]::OpenRead($gzFile)
     $gzipStream = New-Object System.IO.Compression.GzipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
     $outputStream = [System.IO.File]::Create($isoFile)
     $gzipStream.CopyTo($outputStream)
     $outputStream.Close()
     $gzipStream.Close()
     $inputStream.Close()
     
     $sizeMB = [math]::Round((Get-Item $isoFile).Length / 1MB, 2)
     Write-Host "✓ Extracted to: $isoFile ($sizeMB MB)" -ForegroundColor Green
     ```
6. Final file: `C:\ISOs\pfSense-CE-2.7.2-RELEASE-amd64.iso` (~995 MB)
7. Wait for extraction to complete

**Download 2: Windows Server 2022**

1. Go to: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
2. Fill in registration form (required by Microsoft)
3. Select: **64-bit edition ISO**
4. Language: **English (United States)**
5. Click "Download"
6. Downloaded filename: `SERVER_EVAL_x64FRE_en-us.iso`
7. Move/copy to: `C:\ISOs\SERVER_EVAL_x64FRE_en-us.iso`
   > **Note**: You can keep the original filename or rename to `WS2022-Eval.iso`
8. Size: ~5 GB
9. Wait for download (may take 10-30 minutes depending on connection)

**Verify downloads:**

```powershell
# Check ISO files exist (using actual filenames)
$pfSenseIso = "C:\ISOs\pfSense-CE-2.7.2-RELEASE-amd64.iso"
$ws2022Iso = "C:\ISOs\SERVER_EVAL_x64FRE_en-us.iso"

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

### Install Hyper-V Feature (Choose ONE Method)

**Method 1: PowerShell (Recommended)**

```powershell
# Open PowerShell as Administrator

# Enable Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Restart required
Restart-Computer
```

**Method 2: GUI (Settings)**

1. Press `Windows + R`
2. Type: `optionalfeatures` and press Enter
3. Scroll down and check **Hyper-V**
4. Expand Hyper-V and ensure these are checked:
   - ✅ Hyper-V Management Tools
   - ✅ Hyper-V Platform
5. Click "OK"
6. Restart when prompted

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

## 📝 Step 2: Create Hyper-V Virtual Switches

> **⚠️ CRITICAL**: All commands in this section **MUST** be run in **PowerShell as Administrator**!
> 
> **How to open Admin PowerShell:**
> 1. Press `Windows key`
> 2. Type: `PowerShell`
> 3. Right-click "Windows PowerShell" → **Run as administrator**
> 4. Click "Yes" on UAC prompt

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

You can use **PowerShell** (faster) or **Hyper-V Manager GUI** (more visual). Choose one method.

### Method 1: PowerShell (Recommended - Faster)

```powershell
# Open PowerShell as Administrator

# Create VM folder
New-Item -Path "C:\Hyper-V\pfSense-Lab" -ItemType Directory -Force

# Create virtual hard disk first
New-VHD -Path "C:\Hyper-V\pfSense-Lab\pfSense-Lab.vhdx" -SizeBytes 8GB -Dynamic

# Create VM (Generation 1 for FreeBSD compatibility)
New-VM -Name "pfSense-Lab" `
       -MemoryStartupBytes 1GB `
       -Generation 1 `
       -BootDevice CD `
       -VHDPath "C:\Hyper-V\pfSense-Lab\pfSense-Lab.vhdx" `
       -Path "C:\Hyper-V"

# Add second network adapter (VM has 1 by default, we need 2 total)
Add-VMNetworkAdapter -VMName "pfSense-Lab" -SwitchName "Internal-Lab"

# Connect first adapter to External (WAN)
Get-VMNetworkAdapter -VMName "pfSense-Lab" | Select-Object -First 1 | Connect-VMNetworkAdapter -SwitchName "External"

# Mount pfSense ISO
Set-VMDvdDrive -VMName "pfSense-Lab" -Path "C:\ISOs\pfSense-CE-2.7.2-RELEASE-amd64.iso"

# Disable Secure Boot (required for pfSense)
Set-VMFirmware -VMName "pfSense-Lab" -EnableSecureBoot Off -ErrorAction SilentlyContinue

# Disable checkpoints (saves disk space)
Set-VM -Name "pfSense-Lab" -CheckpointType Disabled

# Start VM
Start-VM -Name "pfSense-Lab"

# Connect to VM console
vmconnect localhost "pfSense-Lab"
```

### Method 2: Hyper-V Manager GUI (Step-by-Step)

1. **Open Hyper-V Manager:**
   - Press `Windows + R`
   - Type: `virtmgmt.msc` and press Enter

2. **New Virtual Machine Wizard:**
   - Right-click your computer name → **New** → **Virtual Machine**
   - Click "Next"

3. **Specify Name and Location:**
   - Name: `pfSense-Lab`
   - Location: `C:\Hyper-V` (or leave default)
   - Click "Next"

4. **Specify Generation:**
   - Select: **Generation 1** (pfSense requires this)
   - Click "Next"

5. **Assign Memory:**
   - Startup memory: `1024` MB
   - Uncheck "Use Dynamic Memory"
   - Click "Next"

6. **Configure Networking:**
   - Connection: Select **External** (this will be WAN)
   - Click "Next"

7. **Connect Virtual Hard Disk:**
   - Select: "Create a virtual hard disk"
   - Name: `pfSense-Lab.vhdx`
   - Location: `C:\Hyper-V\pfSense-Lab\`
   - Size: `8` GB
   - Click "Next"

8. **Installation Options:**
   - Select: "Install an operating system from a bootable image file"
   - Click "Browse" → Navigate to `C:\ISOs\pfSense-CE-2.7.2-RELEASE-amd64.iso`
   - Click "Next"

9. **Completing Wizard:**
   - Review settings
   - Click "Finish"

10. **Add Second Network Adapter (LAN):**
    - Right-click "pfSense-Lab" → **Settings**
    - Click "Add Hardware" → Select **Network Adapter** → Click "Add"
    - Virtual Switch: Select **Internal-Lab**
    - Click "OK"

11. **Disable Checkpoints (Optional but Recommended):**
    - Right-click "pfSense-Lab" → **Settings**
    - Select "Checkpoints" (left menu)
    - Uncheck "Enable checkpoints"
    - Click "OK"

12. **Start VM:**
    - Right-click "pfSense-Lab" → **Connect**
    - In console window, click **Start**

### Install pfSense (In VM Console)

The VM console should now show pfSense boot menu. Follow these steps:

1. **Boot Menu:**
   - Wait for boot menu (or press Enter)
   - pfSense will start loading (takes 30-60 seconds)

2. **Copyright Notice:**
   - You'll see a copyright and distribution notice
   - Press **Enter** to accept

3. **Welcome Screen:**
   ```
   Welcome to pfSense!
   
   Install pfSense
   Rescue Shell
   Recover config.xml
   ```
   - Use arrow keys to select **Install pfSense**
   - Press **Enter**

4. **Keymap Selection:**
   ```
   Select a Keymap
   >>> Continue with default keymap
       Test keymap
       Select keymap from list
   ```
   - Press **Enter** to use default (US keymap)
   - Or select your keyboard layout if different

5. **Partitioning:**
   ```
   Partitioning
   >>> Auto (ZFS)
       Shell
       Auto (UFS) BIOS
       Auto (UFS) UEFI
       Manual
   ```
   - Select **Auto (ZFS)**
   - Press **Enter**

6. **ZFS Configuration - Installation Type:**
   ```
   >>> Install - Proceed with installation
       Shell - Open a shell for manual setup
   ```
   - Select **Install**
   - Press **Enter**

7. **ZFS Configuration - Pool Type:**
   ```
   >>> stripe - No redundancy
       mirror - N-Way mirroring
       raid10 - Striped mirror
   ```
   - Select **stripe** (we only have 1 disk)
   - Press **Space** to select
   - Press **Enter**

8. **Select Disk:**
   ```
   [ ] ada0    8.0 GB
   ```
   - Press **Space** to select the disk (shows [X])
   - Press **Enter**

9. **Confirmation:**
   ```
   !!! WARNING - THIS WILL ERASE THE DISK !!!
   
   Are you sure?
   No / Yes
   ```
   - Select **Yes**
   - Press **Enter**

10. **Installation Progress:**
    - Installation will begin (takes 2-3 minutes)
    - You'll see progress: Extracting files, configuring system
    - Wait for completion message

11. **Installation Complete:**
    ```
    Installation Complete!
    
    Manual Configuration
    Reboot
    ```
    - Select **Reboot**
    - Press **Enter**

12. **Eject ISO (Important!):**
    - **In Hyper-V Manager:** Right-click "pfSense-Lab" → Settings
    - Select "DVD Drive" → Select "None"
    - Click "OK"
    - This ensures VM boots from hard disk, not ISO

### Initial Configuration (After Reboot)

After reboot (takes 30-60 seconds), you'll see the pfSense console menu.

**Interface Assignment:**

pfSense will detect your 2 network adapters and show something like:

```
Valid interfaces are:
hn0  XX:XX:XX:XX:XX:XX (up)
hn1  YY:YY:YY:YY:YY:YY (up)

Do you want to set up VLANs now? [y/n]:
```

1. **VLANs:**
   - Type: `n` (no VLANs)
   - Press **Enter**

2. **WAN Interface:**
   ```
   Enter the WAN interface name: 
   ```
   - Type: `hn0` (first adapter = External switch)
   - Press **Enter**

3. **LAN Interface:**
   ```
   Enter the LAN interface name:
   ```
   - Type: `hn1` (second adapter = Internal-Lab switch)
   - Press **Enter**

4. **Optional Interface:**
   ```
   Enter the Optional 1 interface name:
   ```
   - Just press **Enter** (leave empty)

5. **Confirmation:**
   ```
   WAN  -> hn0
   LAN  -> hn1
   
   Do you want to proceed? [y/n]:
   ```
   - Type: `y`
   - Press **Enter**

**Console Menu:**

You'll now see the pfSense main menu:

```
*** Welcome to pfSense ***
WAN (wan)   -> hn0 -> [IP from DHCP, e.g., 192.168.1.x]
LAN (lan)   -> hn1 -> 192.168.1.1

0) Logout
1) Assign Interfaces
2) Set interface(s) IP address
3) Reset webConfigurator password
...
Enter an option:
```

**Configure LAN IP Address:**

1. Type: `2` (Set interface(s) IP address)
2. Press **Enter**

3. **Select Interface:**
   ```
   Available interfaces:
   1 - WAN
   2 - LAN
   
   Enter the number of the interface:
   ```
   - Type: `2` (LAN)
   - Press **Enter**

4. **Configure LAN IPv4 Address:**
   ```
   Enter the new LAN IPv4 address: 
   ```
   - Type: `10.0.1.1`
   - Press **Enter**

5. **Subnet Mask:**
   ```
   Enter the new LAN IPv4 subnet bit count:
   ```
   - Type: `24`
   - Press **Enter**

6. **Upstream Gateway:**
   ```
   For a LAN, press <ENTER> for none:
   ```
   - Just press **Enter** (no gateway for LAN)

7. **IPv6 Configuration:**
   ```
   Do you want to enable the DHCP server on LAN? [y/n]:
   ```
   - Type: `n` (skip IPv6)
   - Press **Enter**

8. **DHCP Server:**
   ```
   Do you want to enable the DHCP server on LAN? [y/n]:
   ```
   - Type: `y` (enable DHCP)
   - Press **Enter**

9. **DHCP Start Address:**
   ```
   Enter the start address of the range:
   ```
   - Type: `10.0.1.100`
   - Press **Enter**

10. **DHCP End Address:**
    ```
    Enter the end address of the range:
    ```
    - Type: `10.0.1.200`
    - Press **Enter**

11. **HTTP Revert:**
    ```
    Do you want to revert to HTTP as the webConfigurator protocol? [y/n]:
    ```
    - Type: `n` (keep HTTPS)
    - Press **Enter**

**Success!**

You should see:

```
The IPv4 LAN address has been set to 10.0.1.1/24
You can now access the webConfigurator by opening https://10.0.1.1/
```

**Write down these credentials:**
- **URL:** https://10.0.1.1
- **Username:** admin
- **Password:** pfsense

Press **Enter** to return to main menu.

---

## 📝 Step 4: Create Windows Server 2022 VM

You can use **PowerShell** (faster) or **Hyper-V Manager GUI** (more visual). Choose one method.

### Method 1: PowerShell (Recommended - Faster)

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

# Connect network adapter to Internal-Lab (pfSense LAN)
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

### Method 2: Hyper-V Manager GUI (Step-by-Step)

1. **Open Hyper-V Manager:**
   - Press `Windows + R`
   - Type: `virtmgmt.msc` and press Enter

2. **New Virtual Machine Wizard:**
   - Right-click your computer name → **New** → **Virtual Machine**
   - Click "Next"

3. **Specify Name and Location:**
   - Name: `ArcServer-Lab`
   - Location: `C:\Hyper-V` (or leave default)
   - Click "Next"

4. **Specify Generation:**
   - Select: **Generation 2** (modern Windows Server)
   - Click "Next"

5. **Assign Memory:**
   - Startup memory: `4096` MB (4 GB)
   - Check "Use Dynamic Memory" (optional, saves RAM)
   - Click "Next"

6. **Configure Networking:**
   - Connection: Select **Internal-Lab** (pfSense LAN)
   - Click "Next"

7. **Connect Virtual Hard Disk:**
   - Select: "Create a virtual hard disk"
   - Name: `ArcServer-Lab.vhdx`
   - Location: `C:\Hyper-V\ArcServer-Lab\`
   - Size: `40` GB
   - Click "Next"

8. **Installation Options:**
   - Select: "Install an operating system from a bootable image file"
   - Click "Browse" → Navigate to `C:\ISOs\SERVER_EVAL_x64FRE_en-us.iso`
   - Click "Next"

9. **Completing Wizard:**
   - Review settings
   - Click "Finish"

10. **Configure VM Settings (Before First Boot):**
    - Right-click "ArcServer-Lab" → **Settings**
    
    **Processor:**
    - Click "Processor" (left menu)
    - Number of virtual processors: `2`
    
    **Security (Optional):**
    - Click "Security" (left menu)
    - Uncheck "Enable Secure Boot" (helps avoid boot issues)
    
    **Checkpoints (Optional):**
    - Click "Checkpoints" (left menu)
    - Uncheck "Enable checkpoints" (saves disk space)
    
    - Click "OK"

11. **Start VM:**
    - Right-click "ArcServer-Lab" → **Connect**
    - In console window, click **Start**
    - Windows Server installation will begin automatically

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
   
   # Test pfSense connectivity
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

## � Setup Summary - What You've Built

By completing this guide, you've created a complete on-premises simulation:

### ✅ Infrastructure Components

**Hyper-V Environment:**
- ✓ 2 Virtual Switches (External + Internal-Lab)
- ✓ 2 Virtual Machines (pfSense + Windows Server)
- ✓ Isolated network topology simulating real datacenter

**pfSense Firewall:**
- ✓ Configured with WAN (internet) + LAN (10.0.1.0/24)
- ✓ DHCP server for LAN network
- ✓ Firewall rules blocking all direct internet access
- ✓ IPsec S2S VPN tunnel to Azure (IKEv2)
- ✓ Phase 1 + Phase 2 VPN configuration

**Windows Server 2022 (ArcServer01):**
- ✓ Static IP: 10.0.1.10/24
- ✓ Gateway: pfSense (10.0.1.1)
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
pfSense LAN (10.0.1.1)
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
| pfSense VM Install | 20-30 min |
| Windows Server Install | 20-30 min |
| pfSense Configuration | 15-20 min |
| VPN Setup | 15-20 min |
| **Total** | **80-115 min** |

---

## �🚨 VPN Troubleshooting (If Tests Failed)

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
