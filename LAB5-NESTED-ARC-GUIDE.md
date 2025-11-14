# Lab 5: Nested On-Premises Azure Arc Setup Guide

## Overview
This guide walks you through the post-deployment steps to onboard an Azure Arc-enabled server running in a nested Hyper-V environment. The architecture simulates an on-premises environment in Azure with traffic routed through Azure Firewall's explicit proxy.

## 📋 Deployment Information

| Component | Details |
|-----------|---------|
| **Resource Group** | `rg-arc-nested-lab` |
| **Location** | `swedencentral` |
| **Subscription** | `b67d7073-183c-499f-aaa9-bbb4986dedf1` |
| **Nested VM Public IP** | `135.225.80.207` |
| **Azure Firewall Private IP** | `10.100.0.4` |
| **Explicit Proxy URL** | `http://10.100.0.4:8443` |
| **VPN Gateway Public IP** | `4.223.154.191` |
| **VPN Shared Key** | `AzureArc2025!Lab5-mmuklyjjfwml4` |
| **Admin Username** | `azureadmin` |

---

## 🚀 Step 1: Connect to Nested Hyper-V VM

### Connect via RDP

1. Open Remote Desktop Connection:
   ```cmd
   mstsc /v:135.225.80.207
   ```

2. Enter credentials:
   - **Username:** `azureadmin`
   - **Password:** (Use the password generated during deployment - check your terminal output or saved notes)

3. Accept the certificate warning and connect.

### Verify Hyper-V Installation

Once connected, verify Hyper-V is installed:

```powershell
Get-WindowsFeature -Name Hyper-V
```

Expected output: `Install State = Installed`

---

## 🔧 Step 2: Configure Nested Hyper-V Environment

### Open PowerShell as Administrator

1. Right-click **Start** → **Windows PowerShell (Admin)**

### Run Configuration Script

The configuration script is already on your local machine. Copy its contents and paste into the nested VM:

**Option A: Copy Content from Local File**

On your local machine, open:
```
C:\Users\alibengtsson\MyProjects\azfw\scripts\Lab5-Configure-NestedVM.ps1
```

Copy the entire contents and paste into the nested VM's PowerShell window.

**Option B: Download Script from GitHub (if available)**

If you've pushed the script to a repository, download it directly:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/yourrepo/script.ps1' -OutFile 'C:\Lab5-Configure-NestedVM.ps1'
.\Lab5-Configure-NestedVM.ps1
```

**Option C: Manual Entry**

```powershell
# Navigate to a working directory
cd C:\

# Create and run the script
notepad Lab5-Configure-NestedVM.ps1
# Paste the script content, save, then run:
.\Lab5-Configure-NestedVM.ps1
```

### What the Script Does

The configuration script will:

1. ✅ **Create Internal Virtual Switch** (`Internal-Lab` with IP `10.0.1.254/24`)
2. ✅ **Download Windows Server 2022 ISO** (~5GB download to `C:\ISOs\WS2022.iso`)
3. ✅ **Create Arc-enabled VM** (`ARC-Server-01` with 4GB RAM, 60GB disk)
4. ✅ **Generate Arc Onboarding Script** (saved to `C:\Arc-Onboard.ps1`)
5. ✅ **Display Summary** with next steps

**⏱️ Expected Duration:** 15-30 minutes (ISO download is slowest)

---

## 💻 Step 3: Install Windows Server on Arc VM

### Start the Arc VM

After the configuration script completes:

```powershell
Start-VM -Name 'ARC-Server-01'
```

### Connect to VM Console

```powershell
vmconnect.exe localhost 'ARC-Server-01'
```

### Install Windows Server

1. **Boot from ISO**
   - VM will boot from the Windows Server 2022 ISO automatically
   - Press any key when prompted

2. **Windows Setup**
   - Language: English (or your preference)
   - Click **Install now**

3. **Select Edition**
   - Choose: **Windows Server 2022 Standard (Desktop Experience)**
   - Click **Next**

4. **Accept License Terms**
   - Check "I accept the license terms"
   - Click **Next**

5. **Installation Type**
   - Select: **Custom: Install Windows only (advanced)**

6. **Select Drive**
   - Select the 60GB drive
   - Click **Next**

7. **Wait for Installation**
   - Installation takes 10-15 minutes
   - VM will restart automatically

8. **Set Administrator Password**
   - Create a strong password (e.g., `ArcServer2024!`)
   - Confirm password
   - Press **Finish**

⏱️ **Expected Duration:** 20-30 minutes

---

## 🌐 Step 4: Configure Networking in Arc VM

### Log In to Arc VM

- Press **Ctrl+Alt+Del** (use Hyper-V menu: Action → Ctrl+Alt+Delete)
- Enter the administrator password you just created

### Configure Static IP

Open PowerShell as Administrator:

```powershell
# Set static IP
New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress 10.0.1.10 -PrefixLength 24 -DefaultGateway 10.0.1.254

# Set DNS to Azure's DNS resolver
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 168.63.129.16
```

### Verify Connectivity

Test network connectivity:

```powershell
# Test gateway (nested Hyper-V host)
Test-Connection -ComputerName 10.0.1.254 -Count 2

# Test Azure DNS
Test-Connection -ComputerName 168.63.129.16 -Count 2

# Test internet through proxy (will fail without proxy configured - this is expected)
Test-NetConnection -ComputerName aka.ms -Port 443
```

---

## 🔐 Step 5: Onboard Arc Agent with Proxy

### Copy Onboarding Script to Arc VM

**Option 1: Type/Paste from Hyper-V Console**

The onboarding script is saved on the Hyper-V host at `C:\Arc-Onboard.ps1`. 

From the **nested Hyper-V VM** (via RDP), open the script:

```powershell
notepad C:\Arc-Onboard.ps1
```

Copy the content, then in the **Arc VM**, paste it into a new file:

```powershell
notepad C:\Arc-Onboard.ps1
# Paste content, save
```

**Option 2: Use Enhanced Session (if enabled)**

If Enhanced Session is available, you can copy-paste directly.

### Review the Onboarding Script

The script performs these actions:

```powershell
# Configure networking (should already be done)
New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress 10.0.1.10 -PrefixLength 24 -DefaultGateway 10.0.1.254
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 168.63.129.16

# Configure proxy environment variables
[Environment]::SetEnvironmentVariable('HTTPS_PROXY', 'http://10.100.0.4:8443', 'Machine')
[Environment]::SetEnvironmentVariable('HTTP_PROXY', 'http://10.100.0.4:8443', 'Machine')

# Download Arc agent via proxy
Invoke-WebRequest -Uri 'https://aka.ms/AzureConnectedMachineAgent' `
    -OutFile 'C:\AzureConnectedMachineAgent.msi' `
    -Proxy 'http://10.100.0.4:8443'

# Install Arc agent
msiexec /i C:\AzureConnectedMachineAgent.msi /qn /norestart

# Wait for installation
Start-Sleep -Seconds 30

# Onboard to Azure Arc
& 'C:\Program Files\AzureConnectedMachineAgent\azcmagent.exe' connect `
    --subscription-id 'b67d7073-183c-499f-aaa9-bbb4986dedf1' `
    --resource-group 'rg-arc-nested-lab' `
    --location 'swedencentral' `
    --proxy-url 'http://10.100.0.4:8443'
```

### Run the Onboarding Script

Execute the script:

```powershell
C:\Arc-Onboard.ps1
```

### Expected Output

You should see:

```
✓ Environment variables set
✓ Arc agent downloaded successfully
✓ Arc agent installed
✓ Connecting to Azure Arc...
info    Successfully Onboarded Resource to Azure
```

### Verify Arc Registration

Check agent status:

```powershell
& 'C:\Program Files\AzureConnectedMachineAgent\azcmagent.exe' show
```

Expected output should include:
- **Resource Name:** ARC-Server-01
- **Status:** Connected
- **Resource Group:** rg-arc-nested-lab

⏱️ **Expected Duration:** 5-10 minutes

---

## ✅ Step 6: Validate Arc Registration in Azure Portal

### Access Azure Portal

1. Open browser and navigate to [https://portal.azure.com](https://portal.azure.com)
2. Sign in with your Azure credentials

### Navigate to Resource Group

1. Search for **Resource groups** in the top search bar
2. Click on `rg-arc-nested-lab`

### Verify Arc-enabled Server

1. Look for resource named **ARC-Server-01** (type: `Microsoft.HybridCompute/machines`)
2. Click on the Arc-enabled server
3. Verify:
   - **Status:** Connected ✅
   - **Location:** Sweden Central
   - **Agent version:** (latest)
   - **Operating system:** Windows Server 2022

### Check Extensions

1. In the Arc server blade, navigate to **Extensions**
2. You should see any installed Arc extensions

---

## 🔍 Step 7: Validate Traffic Through Azure Firewall

### View Azure Firewall Logs

#### Option 1: Azure Portal - Firewall Logs

1. Navigate to **Resource groups** → `rg-arc-nested-lab`
2. Click on **afw-hub** (Azure Firewall)
3. Go to **Logs** under Monitoring
4. Run this query:

```kql
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where SourceIp == "10.0.1.10"
| project TimeGenerated, SourceIp, DestinationFqdn, Action, Protocol
| order by TimeGenerated desc
```

5. You should see traffic from `10.0.1.10` to Arc endpoints:
   - `aka.ms`
   - `download.microsoft.com`
   - `*.his.arc.azure.com`
   - `management.azure.com`
   - `login.microsoftonline.com`

#### Option 2: PowerShell Query

From your local machine:

```powershell
# Get firewall
$fw = Get-AzFirewall -Name "afw-hub" -ResourceGroupName "rg-arc-nested-lab"

# View firewall details
$fw | Select-Object Name, ProvisioningState, ThreatIntelMode

# Note: Full logs require Azure Monitor/Log Analytics workspace
```

### Verify VPN Connection

Check VPN connection status:

```powershell
Get-AzVirtualNetworkGatewayConnection `
    -Name "conn-hub-to-onprem" `
    -ResourceGroupName "rg-arc-nested-lab" | `
    Select-Object Name, ConnectionStatus, EgressBytesTransferred, IngressBytesTransferred
```

Expected output:
- **ConnectionStatus:** Connected ✅
- **EgressBytesTransferred:** > 0
- **IngressBytesTransferred:** > 0

### Test Proxy Functionality

From the Arc VM, test explicit proxy:

```powershell
# Test proxy connectivity
$proxy = "http://10.100.0.4:8443"

# Test HTTPS request through proxy
Invoke-WebRequest -Uri 'https://aka.ms/AzureConnectedMachineAgent' -Proxy $proxy -UseBasicParsing | Select-Object StatusCode

# Should return: StatusCode = 200
```

### Test Blocked Traffic

Verify that non-Arc traffic is blocked:

```powershell
# This should FAIL (no rule for google.com)
try {
    Test-NetConnection -ComputerName google.com -Port 443 -InformationLevel Detailed
} catch {
    Write-Host "✓ Correctly blocked!" -ForegroundColor Green
}
```

---

## 🎯 Success Criteria Checklist

- [ ] Nested Hyper-V VM accessible via RDP (`135.225.80.207`)
- [ ] Internal-Lab virtual switch created (`10.0.1.254/24`)
- [ ] Windows Server 2022 installed on Arc VM
- [ ] Arc VM has static IP (`10.0.1.10`)
- [ ] Arc agent installed successfully
- [ ] Arc server shows as **Connected** in Azure Portal
- [ ] Traffic from Arc VM visible in Azure Firewall logs
- [ ] VPN connection status is **Connected**
- [ ] Non-Arc traffic (e.g., google.com) is blocked

---

## 🐛 Troubleshooting

### Issue: Cannot connect to nested VM via RDP

**Solution:**
```powershell
# Check VM status
Get-AzVM -ResourceGroupName rg-arc-nested-lab -Name vm-nested-hv -Status

# Verify NSG allows RDP
Get-AzNetworkSecurityGroup -ResourceGroupName rg-arc-nested-lab -Name nsg-onprem | 
    Get-AzNetworkSecurityRuleConfig | Where-Object {$_.DestinationPortRange -eq "3389"}
```

### Issue: ISO download fails in nested VM

**Solution:**
```powershell
# Download ISO manually with progress
$wsIsoUrl = "https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
$wsIsoPath = "C:\ISOs\WS2022.iso"
Start-BitsTransfer -Source $wsIsoUrl -Destination $wsIsoPath -DisplayName "Windows Server 2022 ISO"
```

### Issue: Arc agent onboarding fails

**Solution:**

1. **Check proxy environment variables:**
   ```powershell
   [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Machine')
   [Environment]::GetEnvironmentVariable('HTTP_PROXY', 'Machine')
   ```

2. **Test proxy connectivity:**
   ```powershell
   Test-NetConnection -ComputerName 10.100.0.4 -Port 8443
   ```

3. **Verify DNS resolution:**
   ```powershell
   Resolve-DnsName aka.ms
   Resolve-DnsName management.azure.com
   ```

4. **Check Arc agent logs:**
   ```powershell
   Get-Content 'C:\ProgramData\AzureConnectedMachineAgent\Log\azcmagent.log' -Tail 50
   ```

### Issue: VPN connection shows as "NotConnected"

**Solution:**

The VPN requires configuration on the nested VM side (not just Azure). In a real on-premises scenario, you would configure a VPN device. For this lab:

1. The Local Network Gateway points to the nested VM's public IP
2. The nested VM would need Windows Server Routing and Remote Access (RRAS) to act as VPN endpoint
3. For testing Arc without VPN, the explicit proxy is sufficient

---

## 🧹 Cleanup

When you're done testing, remove all resources:

```powershell
# Remove entire resource group (WARNING: This deletes EVERYTHING)
Remove-AzResourceGroup -Name rg-arc-nested-lab -Force -AsJob

# Check deletion status
Get-AzResourceGroup -Name rg-arc-nested-lab
```

**Note:** This will delete:
- Azure Firewall (~$1.25/hour)
- VPN Gateway (~$0.19/hour)
- Nested Hyper-V VM (~$0.49/hour)
- All networking resources
- Arc-enabled server registration

**Estimated cost savings:** ~$2/hour after cleanup

---

## 📚 Additional Resources

- [Azure Arc-enabled servers documentation](https://learn.microsoft.com/azure/azure-arc/servers/overview)
- [Azure Firewall explicit proxy](https://learn.microsoft.com/azure/firewall/explicit-proxy)
- [Arc network requirements](https://learn.microsoft.com/azure/azure-arc/servers/network-requirements)
- [Troubleshoot Arc agent connection](https://learn.microsoft.com/azure/azure-arc/servers/troubleshoot-agent-onboard)

---

## 📝 Summary

You have successfully:

✅ Deployed a nested on-premises simulation in Azure  
✅ Configured Azure Firewall with explicit proxy for Arc traffic  
✅ Created a nested Hyper-V environment  
✅ Installed Windows Server in a nested VM  
✅ Onboarded an Azure Arc-enabled server through the proxy  
✅ Validated traffic flows through Azure Firewall  

This architecture demonstrates how to onboard on-premises servers to Azure Arc while routing all traffic through a controlled firewall with explicit proxy configuration.
