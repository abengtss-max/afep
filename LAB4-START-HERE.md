# Lab 4: Azure Arc + Explicit Proxy - Complete Setup Guide

## 🎯 What You'll Build

A complete Azure Arc deployment using Explicit Proxy over Site-to-Site VPN with NO direct internet access.

```
┌─────────────────────────────────────────────────────────────────┐
│ YOUR WINDOWS 11 PRO PC (On-Premises Simulation)                │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Hyper-V VMs                                             │   │
│  │                                                         │   │
│  │  ┌──────────────┐         ┌──────────────────────┐    │   │
│  │  │ Windows      │────────▶│  Windows Server 2022 │    │   │
│  │  │ Server Router│         │  (ArcServer01)       │    │   │
│  │  │ (RRAS+NAT)   │         │                      │    │   │
│  │  │              │         │  IP: 10.0.1.10       │    │   │
│  │  │  WAN: DHCP   │         │  GW: 10.0.1.1        │    │   │
│  │  │  LAN: 10.0.1.1│        │  DNS: 10.100.0.4     │    │   │
│  │  │              │         │  (via VPN)           │    │   │
│  │  │  ❌ Internet │         │                      │    │   │
│  │  │  ✅ VPN Only │         │                      │    │   │
│  │  └──────┬───────┘         └──────────────────────┘    │   │
│  │         │                                             │   │
│  │         │ IPsec S2S VPN Tunnel (Encrypted)          │   │
│  └─────────┼─────────────────────────────────────────────┘   │
│            │                                                 │
└────────────┼─────────────────────────────────────────────────┘
             │
             │ Internet
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ AZURE (Cloud)                                                   │
│                                                                 │
│  ┌──────────────┐      ┌───────────────────┐                  │
│  │ VPN Gateway  │─────▶│ Azure Firewall    │                  │
│  │              │      │ (Premium)         │                  │
│  │ Public IP    │      │                   │                  │
│  │              │      │ Explicit Proxy:   │                  │
│  │              │      │  - HTTP: 8081     │                  │
│  │              │      │  - HTTPS: 8443    │                  │
│  │              │      │  - PAC: 8090      │                  │
│  └──────────────┘      │                   │                  │
│                        │ 18 App Rules      │                  │
│                        │ (Arc Endpoints)   │                  │
│                        └─────────┬─────────┘                  │
│                                  │                            │
│                                  ▼                            │
│                        Azure Arc Endpoints                    │
│                        (login, management,                    │
│                         monitoring, etc.)                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🖥️ Why Windows Server Router Instead of pfSense?

**ARM64 Compatibility**: pfSense (FreeBSD-based) requires Generation 1 VMs which are **NOT supported** on ARM64 processors (Snapdragon X Elite/Plus). Windows Server Router uses Generation 2 VMs and works on both ARM64 and x64.

### Windows Server Router Configuration

The Windows Server Router VM acts as your on-premises firewall/gateway with:

#### **RRAS (Routing and Remote Access Service) Features:**
- **NAT (Network Address Translation)**: Provides internet access for internal VMs
- **VPN Server**: Establishes IPsec Site-to-Site tunnel to Azure
- **Routing**: Routes traffic between internal network and Azure VNet
- **Demand Dial Interface**: Manages the Azure VPN connection

#### **Windows Firewall Configuration:**
```powershell
# Block all outbound internet traffic (default deny)
New-NetFirewallRule -DisplayName "Block-Internet-Outbound" `
    -Direction Outbound -Action Block -Protocol Any `
    -RemoteAddress "Internet"

# Allow VPN traffic to Azure Gateway
New-NetFirewallRule -DisplayName "Allow-Azure-VPN" `
    -Direction Outbound -Action Allow -Protocol Any `
    -RemoteAddress "20.240.93.34"  # Your Azure VPN Gateway IP

# Allow local network communication
New-NetFirewallRule -DisplayName "Allow-Local-Network" `
    -Direction Outbound -Action Allow -Protocol Any `
    -RemoteAddress "10.0.0.0/8,192.168.0.0/16,172.16.0.0/12"
```

#### **Network Interfaces:**
- **WAN Interface**: Connected to "External" switch → Your PC's internet
- **LAN Interface**: Connected to "Internal-Lab" switch → 10.0.1.1/24
- **VPN Interface**: Demand Dial Interface → Azure VNet (10.100.0.0/16)

#### **Security Benefits:**
- ✅ **Zero Direct Internet**: ArcServer01 cannot access internet directly
- ✅ **VPN-Only Access**: All Azure communication goes through encrypted tunnel  
- ✅ **Firewall Controlled**: Windows Firewall enforces security policies
- ✅ **Enterprise-Grade**: Same technology used in production environments

---

## 📚 Complete Setup Process (3 Phases)

**⏱️ Total Time:** 2-3 hours (first time)

### ✅ Phase 1: Deploy Azure Infrastructure (30-40 minutes)
### ✅ Phase 2: Setup On-Premises Environment (60-90 minutes)
### ✅ Phase 3: Install Azure Arc Agent (15-20 minutes)

---

## 🚀 PHASE 1: Deploy Azure Infrastructure

**📍 You Are Here:** On your **Windows 11 PC** (host computer, NOT in a VM)

**⏱️ Time Required:** 30-40 minutes (mostly automated)

**⚠️ CRITICAL:** Start with Azure deployment FIRST! The VPN Gateway takes 30-40 minutes to create, so start this and move on to other tasks while it deploys.

### Step 1.1: Verify Prerequisites

Open **PowerShell as Administrator** on your Windows 11 PC:

```powershell
# Check Azure PowerShell modules
Get-Module -ListAvailable Az.Accounts, Az.Resources, Az.Network

# If not installed:
Install-Module -Name Az -Repository PSGallery -Force -AllowClobber

# Login to Azure
Connect-AzAccount

# Verify subscription
Get-AzSubscription | Select-Object Name, Id, State
```

### Step 1.2: Get Your Public IP

You need your public IP address for the VPN configuration:

```powershell
# Get your current public IP
$myPublicIP = (Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing).Content.Trim()
Write-Host "Your Public IP: $myPublicIP" -ForegroundColor Green

# Save it for later
$myPublicIP | Out-File "C:\Temp\MyPublicIP.txt"
```

### Step 1.3: Run Azure Deployment Script

```powershell
# Navigate to scripts folder
cd C:\Users\$env:USERNAME\MyProjects\azfw\scripts

# Run Lab 4 deployment
.\Deploy-Lab4-Arc-ExplicitProxy.ps1

# This will:
# ✓ Create resource group
# ✓ Create VNet (10.100.0.0/16) with 4 subnets
# ✓ Deploy VPN Gateway (⏱️ 30-40 minutes!)
# ✓ Deploy Azure Firewall Premium with Explicit Proxy
# ✓ Create 18 application rules for Arc endpoints
# ✓ Configure Local Network Gateway
# ✓ Export deployment info to Lab4-Arc-DeploymentInfo.json
```

**☕ While Azure Deploys (30-40 minutes):**

You can start Phase 2 (Hyper-V setup) while waiting! The VPN Gateway deployment is the longest part.

### Step 1.4: Verify Deployment Completed

After 30-40 minutes, verify the deployment:

```powershell
# Check deployment info file was created
Get-Content ".\Lab4-Arc-DeploymentInfo.json" | ConvertFrom-Json | Format-List

# Should show:
# - ResourceGroupName
# - Location
# - VNetName
# - VPNGateway.PublicIP
# - VPNGateway.SharedKey
# - AzureFirewall.PrivateIP
# - ProxyConfig (HTTP: 8081, HTTPS: 8443, PAC: 8090)
```

**✅ Checkpoint:** You should have `Lab4-Arc-DeploymentInfo.json` file with VPN details.

---

## 🏢 PHASE 2: Setup On-Premises Environment

**📍 You Are Here:** Still on your **Windows 11 PC** (preparing Hyper-V environment)

**⏱️ Time Required:** 60-90 minutes

**📖 Full Guide:** [GUIDE-OnPremises-HyperV-Setup.md](./GUIDE-OnPremises-HyperV-Setup.md)

### Quick Overview of Steps:

#### Step 2.0: Prerequisites Validation (5 minutes)
- ✓ Verify Windows 11 Pro edition
- ✓ Verify Azure deployment completed
- ✓ Check hardware requirements (CPU, RAM, disk)
- ✓ Download Windows Server 2022 ISO (2 copies needed: Router + Arc Server)

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Prerequisites](./GUIDE-OnPremises-HyperV-Setup.md#%EF%B8%8F-prerequisites)

#### Step 2.1: Enable Hyper-V (10 minutes + restart)
- ✓ Enable virtualization in BIOS
- ✓ Install Hyper-V feature (PowerShell or GUI)
- ✓ Restart computer

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Step 1](./GUIDE-OnPremises-HyperV-Setup.md#-step-1-enable-hyper-v-on-your-pc)

#### Step 2.2: Create Virtual Switches (5 minutes)
- ✓ Create External switch (for internet/VPN)
- ✓ Create Internal-Lab switch (isolated network)

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Step 2](./GUIDE-OnPremises-HyperV-Setup.md#-step-2-create-hyper-v-virtual-switches)

#### Step 2.3: Create Windows Server Router VM (30-40 minutes)
- ✓ Create VM (Generation 2 for ARM64 compatibility)
- ✓ Install Windows Server 2022 with Desktop Experience
- ✓ Configure dual NICs (WAN: External, LAN: Internal-Lab)
- ✓ Install RRAS role (NAT + Routing + VPN)
- ✓ Set LAN IP to 10.0.1.1/24
- ✓ Configure Windows Firewall (block internet, allow VPN)

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Step 3](./GUIDE-OnPremises-HyperV-Setup.md#-step-3-create-windows-server-router-vm)

#### Step 2.4: Create Windows Server VM (20-30 minutes)
- ✓ Create VM (PowerShell or GUI method)
- ✓ Install Windows Server 2022 (Desktop Experience)
- ✓ Configure static IP: 10.0.1.10/24
- ✓ Set gateway to Router: 10.0.1.1
- ✓ Rename computer to ArcServer01

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Step 4](./GUIDE-OnPremises-HyperV-Setup.md#-step-4-create-windows-server-2022-vm)

#### Step 2.5: Configure Windows Server Router Security (15 minutes)
- ✓ Configure Windows Firewall with Advanced Security
- ✓ Create rules to block all outbound internet traffic
- ✓ Allow only VPN traffic and local network communication
- ✓ Verify internet is blocked from ArcServer01

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Step 5](./GUIDE-OnPremises-HyperV-Setup.md#-step-5-configure-windows-server-router-security)

#### Step 2.6: Configure Site-to-Site VPN (15 minutes)
- ✓ Get Azure VPN info from `Lab4-Arc-DeploymentInfo.json`
- ✓ Configure IPsec VPN on Windows Server Router using RRAS
- ✓ Update Azure Local Network Gateway with your public IP
- ✓ Create VPN connection in Azure

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Step 6](./GUIDE-OnPremises-HyperV-Setup.md#-step-6-configure-site-to-site-vpn)

#### Step 2.7: Verify VPN Connectivity (5 minutes)
- ✓ Run 6-point VPN validation script
- ✓ Test Windows Server Router gateway
- ✓ Test Azure Firewall via VPN
- ✓ Test proxy ports (8081, 8443)
- ✓ Verify internet is blocked
- ✓ Test DNS resolution

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Step 7](./GUIDE-OnPremises-HyperV-Setup.md#-step-7-verify-vpn-connectivity-critical-validation)

#### Step 2.8: Update DNS to Azure Firewall (5 minutes)
- ✓ Set DNS server to Azure Firewall (10.100.0.4)
- ✓ Verify DNS resolution works through VPN

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Step 8](./GUIDE-OnPremises-HyperV-Setup.md#-step-8-configure-dns-to-use-azure-firewall)

#### Step 2.9: FINAL VALIDATION (5 minutes)
- ✓ Run 10-point comprehensive validation
- ✓ ALL checks must pass before Phase 3

**📖 Detailed Steps:** [GUIDE-OnPremises-HyperV-Setup.md - Final Validation](./GUIDE-OnPremises-HyperV-Setup.md#-final-validation---run-before-moving-to-next-guide)

**✅ Checkpoint:** All 10 validation checks pass. VPN is working. Internet is blocked. Ready for Arc agent!

---

## 🔵 PHASE 3: Install Azure Arc Agent

**📍 You Are Here:** Inside **ArcServer01 VM** (Windows Server 2022)

**⏱️ Time Required:** 15-20 minutes

**📖 Full Guide:** [GUIDE-Arc-Agent-Proxy-Config.md](./GUIDE-Arc-Agent-Proxy-Config.md)

### Quick Overview of Steps:

#### Step 3.0: Prerequisites Validation (5 minutes)
- ✓ Verify hostname is ArcServer01
- ✓ Verify deployment info file exists
- ✓ Test Windows Server Router connectivityr connectivity
- ✓ Test Azure Firewall via VPN
- ✓ Test proxy ports (8081, 8443)
- ✓ Verify internet is BLOCKED
- ✓ Verify DNS resolution

**📖 Detailed Steps:** [GUIDE-Arc-Agent-Proxy-Config.md - Step 0](./GUIDE-Arc-Agent-Proxy-Config.md#%EF%B8%8F-prerequisites-validation)

#### Step 3.1: Set Proxy Environment Variables (2 minutes)
- ✓ Set HTTP_PROXY and HTTPS_PROXY variables
- ✓ Configure NO_PROXY exclusions

**📖 Detailed Steps:** [GUIDE-Arc-Agent-Proxy-Config.md - Step 1](./GUIDE-Arc-Agent-Proxy-Config.md#-step-1-configure-proxy-environment-variables)

#### Step 3.2: Download Arc Agent via Proxy (3 minutes)
- ✓ Download azcmagent installer through Azure Firewall proxy
- ✓ Verify download succeeded

**📖 Detailed Steps:** [GUIDE-Arc-Agent-Proxy-Config.md - Step 2](./GUIDE-Arc-Agent-Proxy-Config.md#-step-2-download-azure-arc-agent-via-proxy)

#### Step 3.3: Install Arc Agent (2 minutes)
- ✓ Install azcmagent MSI
- ✓ Verify installation

**📖 Detailed Steps:** [GUIDE-Arc-Agent-Proxy-Config.md - Step 3](./GUIDE-Arc-Agent-Proxy-Config.md#-step-3-install-azure-arc-agent)

#### Step 3.4: Configure Arc Agent Proxy (2 minutes)
- ✓ Configure agent to use Azure Firewall proxy
- ✓ Set both HTTP and HTTPS proxy

**📖 Detailed Steps:** [GUIDE-Arc-Agent-Proxy-Config.md - Step 4](./GUIDE-Arc-Agent-Proxy-Config.md#-step-4-configure-arc-agent-proxy-settings)

#### Step 3.5: Connect to Azure Arc (5 minutes)
- ✓ Get service principal or use device code auth
- ✓ Register server with Azure Arc
- ✓ Verify connection

**📖 Detailed Steps:** [GUIDE-Arc-Agent-Proxy-Config.md - Step 5](./GUIDE-Arc-Agent-Proxy-Config.md#-step-5-connect-server-to-azure-arc)

#### Step 3.6: Verify Arc Agent Status (2 minutes)
- ✓ Check agent status
- ✓ Verify heartbeat
- ✓ Test endpoint connectivity

**📖 Detailed Steps:** [GUIDE-Arc-Agent-Proxy-Config.md - Step 6](./GUIDE-Arc-Agent-Proxy-Config.md#-step-6-verify-arc-agent-status)

**✅ Checkpoint:** Arc agent shows "Connected" status in Azure Portal!

---

## 🧪 PHASE 4: Comprehensive Validation (Optional but Recommended)

**📍 You Are Here:** Inside **ArcServer01 VM** and **Azure Portal**

**⏱️ Time Required:** 15-20 minutes

**📖 Full Guide:** [VALIDATION-Arc-Connectivity.md](./VALIDATION-Arc-Connectivity.md)

### Validation Test Suites:

1. **Network Connectivity** - VPN, proxy ports, DNS
2. **Proxy Configuration** - Environment variables, agent settings
3. **Arc Agent Status** - Registration, heartbeat, version
4. **Endpoint Reachability** - All 18 Arc endpoints via proxy
5. **Security Validation** - Internet blocked, proxy works
6. **Azure Firewall Logs** - Traffic verification in Azure
7. **Extension Management** - Install test extension

**📖 Detailed Steps:** [VALIDATION-Arc-Connectivity.md](./VALIDATION-Arc-Connectivity.md)

---

## 📊 What You've Accomplished

### ✅ Azure Infrastructure
- VPN Gateway with S2S connection
- Azure Firewall Premium with Explicit Proxy (8081/8443/8090)
- 18 application rules for Arc endpoints
- Secure networking (10.100.0.0/16)

### ✅ On-Premises Environment
- Hyper-V virtualization on Windows 11 Pro
- Windows Server 2022 Router with RRAS and VPN tunnel
- Windows Server 2022 (ArcServer01)
- NO direct internet access (security enforced)

### ✅ Azure Arc Integration
- Arc agent installed via proxy
- All traffic routed through Azure Firewall
- Zero direct internet connectivity
- Full Azure management capabilities

---

## 🎯 Customer Demonstration Proof Points

Use this lab to demonstrate:

1. **✅ Azure Arc WORKS with Explicit Proxy** (customer claims it doesn't)
2. **✅ S2S VPN + Explicit Proxy is supported** (hybrid connectivity)
3. **✅ Zero direct internet required** (strict security policy)
4. **✅ All 18+ Arc endpoints reachable via proxy** (Microsoft docs validated)
5. **✅ Extensions install and work correctly** (full functionality)

---

## 📞 Troubleshooting & Support

### Quick Links:
- **Hyper-V Issues:** [GUIDE-OnPremises-HyperV-Setup.md - Troubleshooting](./GUIDE-OnPremises-HyperV-Setup.md#-vpn-troubleshooting-if-tests-failed)
- **Arc Agent Issues:** [GUIDE-Arc-Agent-Proxy-Config.md - Troubleshooting](./GUIDE-Arc-Agent-Proxy-Config.md#-troubleshooting)
- **Validation Failures:** [VALIDATION-Arc-Connectivity.md - Remediation](./VALIDATION-Arc-Connectivity.md)

### Common Issues:

**VPN Won't Connect:**
- Check Windows Server Router RRAS status: Server Manager → RRAS Console
- Verify Azure connection: Portal → VPN Gateway → Connections
- Confirm public IP updated in Local Network Gateway
- Check Windows Firewall rules on Router

**Can't Reach Azure Firewall:**
- Verify VPN shows "Connected" in RRAS Console
- Test: `Test-NetConnection 10.100.0.4`
- Check Windows Server Router firewall rules allow 10.100.0.0/16

**Arc Agent Connection Fails:**
- Verify proxy environment variables set
- Check: `azcmagent show`
- Test endpoints: `azcmagent check`
- Review Azure Firewall logs for blocked requests

---

## 🗂️ File Structure

```
azfw/
├── LAB4-START-HERE.md  ← YOU ARE HERE (master guide)
│
├── scripts/
│   ├── Deploy-Lab4-Arc-ExplicitProxy.ps1  ← Phase 1 (Azure)
│   └── Lab4-Arc-DeploymentInfo.json        ← Generated by script
│
├── GUIDE-OnPremises-HyperV-Setup.md        ← Phase 2 (Hyper-V)
├── GUIDE-Arc-Agent-Proxy-Config.md         ← Phase 3 (Arc Agent)
└── VALIDATION-Arc-Connectivity.md          ← Phase 4 (Testing)
```

---

## 🚀 Ready to Start?

### Next Steps:

1. **📖 Read this entire document first** (you're doing great!)
2. **☁️ Open Phase 1:** Run Azure deployment script (30-40 min wait)
3. **💻 Open Phase 2:** Setup Hyper-V while Azure deploys
4. **🔵 Open Phase 3:** Install Arc agent after VPN works
5. **🧪 Open Phase 4:** Validate everything works perfectly

**Good luck with your customer demonstration! 🎯**

---

**Document Version:** 1.0  
**Last Updated:** November 10, 2025  
**Estimated Total Time:** 2-3 hours (first time), 60-90 minutes (subsequent)
