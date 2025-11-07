# Azure Firewall Explicit Proxy (AFEP) – Automated Infrastructure Guide

> **📋 Having issues?** Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for diagnostic commands and solutions

## Introduction in Simple Terms

Azure Firewall Explicit Proxy (AFEP) acts like a checkpoint for internet traffic in Azure. Instead of letting servers and apps go straight to the internet, AFEP makes them send traffic through Azure Firewall first, giving you control and visibility.

**This guide automates the infrastructure deployment** so you can focus on learning and configuring the AFEP-specific features.

### Why AFEP?

- **Better control**: Decide which websites or services are allowed.
- **Security**: Block risky traffic and keep logs for audits.
- **Simpler management**: No need for complex routing tables everywhere.
- **Scalable**: Works well in large environments with many networks.

### Important Notes

⚠️ **Azure Firewall Explicit Proxy is currently in Public Preview**  
⚠️ **AzureFirewallSubnet must be exactly /26** (64 IP addresses) - This is mandatory for proper scaling  
⚠️ **Application rules must be used** - Network rules will not work with explicit proxy  
⚠️ **HTTP and HTTPS ports cannot be the same**  
⚠️ **Port 8080 may be blocked** - Some Azure regions/policies restrict port 8080 during preview. Use **8081** or **8082** instead

### Port Configuration (Important!)

**Why not standard ports 80/443?**
- Ports **80/443** are reserved for **transparent proxy mode** (different feature)
- Explicit proxy requires **separate ports** to handle proxy protocol

**Recommended ports:**
- **HTTP**: `8081` or `8082` (8080 is often blocked in preview)
- **HTTPS**: `8443` (standard, works reliably)
- **PAC file**: `8090` (for Lab 2 & 3)

**Why port 8080 doesn't work:**
- Preview feature limitation in some Azure regions
- Corporate/subscription policies may block common proxy ports
- Use 8081 or 8082 as alternatives - they work consistently

### What's Automated vs Manual

**✅ Automated (PowerShell scripts do this for you):**
- Resource Group creation
- VNet and subnet creation
- Public IP address creation
- Azure Firewall deployment
- Client VM deployment
- Network Security Groups
- VNet peering (Lab 3)
- Route tables (Lab 3)

**🎯 Manual (You'll learn AFEP by doing these):**
- Enabling Explicit Proxy on Firewall Policy
- Configuring HTTP/HTTPS ports
- Creating Application Rules
- Configuring PAC files
- Setting up proxy on client VMs
- Testing and validating traffic
- Monitoring logs

---

## Prerequisites

Before starting any lab, ensure you have:

```powershell
# Install required PowerShell modules
Install-Module -Name Az -Repository PSGallery -Force -AllowClobber

# Connect to Azure
Connect-AzAccount

# Verify you're in the correct subscription
Get-AzContext

# If needed, change subscription
Set-AzContext -SubscriptionId "your-subscription-id"
```

---

## PAC Files – Dynamic Proxy Routing

PAC files are scripts that tell apps when to use the proxy and when to go direct.

**Example:**
```javascript
function FindProxyForURL(url, host) {
    if (dnsDomainIs(host, ".company.com")) return "DIRECT";
    return "PROXY 10.0.1.4:8080";
}
```

**Benefits:**
- Route internal traffic directly.
- Send external traffic through the proxy.
- Update rules centrally without touching every device.

---

## LABS

### ✅ Lab 1: Basic Explicit Proxy Deployment

**Goal**: Deploy Azure Firewall with AFEP and test basic web traffic.

**Estimated Time**: 20-30 minutes (automated infrastructure + manual AFEP config)

#### Step 1: Deploy Infrastructure (AUTOMATED)

**Run the PowerShell deployment script:**

📁 **Script Location**: `scripts/Deploy-Lab1-Infrastructure.ps1`

**To run:**

```powershell
cd scripts
.\Deploy-Lab1-Infrastructure.ps1 -AdminPassword (ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force)
```

**What the script does:**
- ✅ Creates Resource Group (RG-AFEP-Lab1)
- ✅ Creates VNet with AzureFirewallSubnet (/26) and ClientSubnet
- ✅ Deploys Azure Firewall with DNS Proxy enabled
- ✅ Creates Network Security Group for RDP access
- ✅ Deploys Windows Server 2022 VM for testing
- ✅ Saves deployment details to `Lab1-DeploymentInfo.json`

**⏱️ Deployment Time**: 10-15 minutes

**💡 Important**: Save the Firewall Private IP from the output - you'll need it for configuration!

---

#### Step 2: Enable Explicit Proxy (MANUAL - Learn AFEP)

**🎯 This is where you learn AFEP configuration!**

1. In Azure Portal, navigate to your Firewall resource (`afw-lab1`)
2. Under **Settings**, click **Firewall Policy**
3. Click on the policy name link `afp-lab1`
4. In the left menu under **Settings**, click **Explicit Proxy (Preview)**
5. Click the **Enable Explicit Proxy** toggle switch to **ON**
6. Configure the ports:
   - **HTTP Port**: `8081` ⚠️ **Note**: Port 8080 may be blocked in some regions - use 8081 or 8082 if 8080 fails
   - **HTTPS Port**: `8443` (standard HTTPS proxy port)
   - ⚠️ **Important**: HTTP and HTTPS ports CANNOT be the same
   - ℹ️ **Port restrictions**: Avoid standard ports (80, 443) as they're reserved for transparent proxy mode
7. Leave **Enable proxy auto-configuration** unchecked (we'll do this in Lab 2)
8. Click **Apply** button (top of page)
9. Wait for "Update succeeded" notification (~30 seconds)

**💡 What you learned:**
- How to enable explicit proxy on Azure Firewall
- Standard proxy port configurations
- Difference between HTTP and HTTPS proxy ports

---

#### Step 3: Create Application Rule Collection (MANUAL - Learn AFEP)

**🎯 This is critical for AFEP - Network rules won't work!**

1. From the Firewall Policy page (`afp-lab1`), under **Settings**, click **Application Rules**
2. Click **+ Add a rule collection** button
3. **Fill in the Rule collection settings** (top section):
   
   | Field | Value | Notes |
   |-------|-------|-------|
   | **Name** | `AllowWebTraffic` | Any descriptive name |
   | **Rule collection type** | `Application` | ⚠️ Must be Application (dropdown) |
   | **Priority** | `200` | Lower = higher priority (100-65000) |
   | **Rule collection action** | `Allow` | Select from dropdown |
   | **Rule collection group** | `DefaultApplicationRuleCollectionGroup` | Select from dropdown |

4. **Add first rule** (in the Rules section below):
   
   | Field | Value | Notes |
   |-------|-------|-------|
   | **Name** | `AllowMicrosoft` | Leave blank or name it |
   | **Source type** | `IP Address` | Select from dropdown |
   | **Source** | `*` | Asterisk means any source (or use `192.168.0.0/16` for private IPs) |
   | **Protocol** | `http:80,https:443` | Type exactly as shown (port format is protocol:port) |
   | **TLS inspection** | ☐ Unchecked | Leave unchecked (requires Premium) |
   | **Destination Type** | `FQDN` | Select from dropdown |
   | **Destination** | `*.microsoft.com` | Wildcard allows all microsoft.com subdomains |

5. Click **+ Add** button (in the Rules section) to add a second rule:
   
   | Field | Value |
   |-------|-------|
   | **Name** | `AllowBing` |
   | **Source type** | `IP Address` |
   | **Source** | `*` |
   | **Protocol** | `http:80,https:443` |
   | **TLS inspection** | ☐ Unchecked |
   | **Destination Type** | `FQDN` |
   | **Destination** | `www.bing.com` |

6. Click **+ Add** button again to add a third rule:
   
   | Field | Value | Notes |
   |-------|-------|-------|
   | **Name** | `AllowTestSites` | Optional name |
   | **Source type** | `IP Address` |
   | **Source** | `*` |
   | **Protocol** | `http:80,https:443` |
   | **TLS inspection** | ☐ Unchecked |
   | **Destination Type** | `FQDN` |
   | **Destination** | `www.example.com,httpbin.org` | Comma-separated list |

7. Click **Add** button (bottom of dialog - this saves the entire rule collection)
8. Wait for "Successfully added rule collection" notification (~1-2 minutes)

**🔍 Quick Validation:**
- Your screen should show 3 rules in the Rules section before clicking final Add
- Protocol format must be `http:80,https:443` (not just "http" or "https")
- Source `*` means all IPs (or use `10.0.2.0/24` to match your VM subnet exactly)
- Don't click Add at the bottom until all 3 rules are configured

**💡 What you learned:**
- Application rules are required for explicit proxy (not network rules)
- Rule priority and collection groups
- FQDN-based filtering
- Protocol specification for HTTP/HTTPS

---

#### Step 4: Configure Proxy on Client VM (MANUAL - Learn AFEP)

**🎯 Learn how clients connect to explicit proxy**

1. **RDP into your Client VM**:
   - Find the Client VM Public IP in `Lab1-DeploymentInfo.json` or Azure Portal
   - Open **Remote Desktop Connection**
   - Enter the **Public IP address**
   - Username: `azureadmin`
   - Password: The one you provided in the script
   - Click **Connect**

2. **Configure Windows Proxy Settings** (on the VM):
   
   ⚠️ **CRITICAL**: You must configure BOTH HTTP and HTTPS proxy ports separately!
   
   **Option A: PowerShell (Recommended - Most Reliable)**
   - Open **PowerShell as Administrator** on the VM
   - Run these commands:
     ```powershell
     # Configure proxy for both HTTP and HTTPS
     netsh winhttp set proxy proxy-server="http=10.0.0.4:8081;https=10.0.0.4:8443" bypass-list="<local>"
     
     # Configure for browsers (Internet Explorer/Edge)
     Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value "http=10.0.0.4:8081;https=10.0.0.4:8443"
     Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 1
     
     # Verify settings
     netsh winhttp show proxy
     ```
   - You should see:
     ```
     Proxy Server(s) :  http=10.0.0.4:8081;https=10.0.0.4:8443
     Bypass List     :  <local>
     ```

   **Option B: Windows Settings GUI** (Alternative method)
   - Press **Windows key + I** to open Settings
   - Click **Network & Internet** (left menu)
   - Scroll down and click **Proxy** (left menu)
   - Under **Manual proxy setup**:
     - Toggle **Use a proxy server** to **ON**
     - **Address**: `10.0.0.4` (Firewall Private IP from `Lab1-DeploymentInfo.json`)
     - **Port**: `8081`
     - ⚠️ **Note**: GUI only supports one port - use PowerShell method for full HTTPS support
     - Check **Don't use the proxy server for local (intranet) addresses**
     - Click **Save** button

3. **Test the Configuration**:
   - Open **PowerShell** on the VM
   - Run this test command:
     ```powershell
     # Verify proxy settings are applied
     netsh winhttp show proxy
     
     # Test HTTP through proxy (uses port 8081)
     Invoke-WebRequest -Uri "http://www.microsoft.com" -UseBasicParsing | Select-Object StatusCode
     
     # Test HTTPS through proxy (uses port 8443 automatically when configured correctly)
     Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing | Select-Object StatusCode
     ```
   - Both should return `StatusCode : 200` (success)
   - If you get **Error 470**, your application rules need to be updated (see TROUBLESHOOTING.md)
   - If you get connection errors, verify both ports 8081 and 8443 are configured

**💡 What you learned:**
- How to configure explicit proxy on Windows clients with separate HTTP/HTTPS ports
- Difference between WinHTTP (system-wide) and IE/Edge registry settings
- Why both ports (8081 for HTTP, 8443 for HTTPS) are required
- Using PowerShell for reliable proxy configuration
- Bypass lists for local traffic

---

#### Step 5: Test the Configuration (MANUAL - Learn AFEP)

**🎯 Validate your AFEP setup works correctly**

1. **On the Client VM**, open **Microsoft Edge**
2. **Test allowed sites:**
   - Navigate to `https://www.microsoft.com`
     - ✅ **Expected**: Page loads successfully (allowed by firewall rule)
   - Navigate to `https://www.bing.com`
     - ✅ **Expected**: Page loads successfully (allowed by firewall rule)
   - Navigate to `http://www.example.com`
     - ✅ **Expected**: Page loads successfully (allowed by firewall rule)

3. **Test blocked site:**
   - Navigate to `https://www.google.com`
     - ❌ **Expected**: Connection fails with "ERR_TUNNEL_CONNECTION_FAILED" (not allowed by firewall rules)
     - This confirms the firewall is blocking traffic as expected!

**🎉 If the allowed sites work and Google is blocked, you've successfully completed Lab 1!**

---

#### 📊 Optional: View Firewall Logs

**Note:** Diagnostic logging is **not enabled by default**. This is optional and not required for the lab.

<details>
<summary>Click to expand: Enable and view firewall logs</summary>

**Why enable logs?**
- See detailed traffic analysis (source IP, destination, action taken)
- Troubleshoot rule matching issues
- Audit and compliance requirements

**Step 1: Enable Diagnostic Logging** (run on your local machine):

```powershell
# Install Az.Monitor module if needed
Install-Module Az.Monitor -Force -AllowClobber -Scope CurrentUser

# Create Log Analytics Workspace
$workspace = New-AzOperationalInsightsWorkspace `
    -Location "Sweden Central" `
    -Name "law-afep-lab1" `
    -ResourceGroupName "RG-AFEP-Lab1" `
    -Sku "PerGB2018"

# Wait for workspace to be ready
Start-Sleep -Seconds 30

# Enable firewall diagnostics
$fw = Get-AzFirewall -Name "afw-lab1" -ResourceGroupName "RG-AFEP-Lab1"

Set-AzDiagnosticSetting `
    -Name "afep-diagnostics" `
    -ResourceId $fw.Id `
    -WorkspaceId $workspace.ResourceId `
    -Enabled $true `
    -Category @("AzureFirewallApplicationRule", "AzureFirewallNetworkRule")

Write-Host "`n✅ Logging enabled! Wait 5-10 minutes for logs to appear" -ForegroundColor Green
```

**Step 2: Generate Traffic** (on the VM):
- Browse to several websites (microsoft.com, bing.com, google.com)
- Wait 5-10 minutes for logs to be ingested

**Step 3: Query Logs** (in Azure Portal):
- Go to Firewall → Monitoring → Logs
- Run this query:

```kusto
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where TimeGenerated > ago(30m)
| where isnotempty(Message)
| extend 
    Action = extract("Action: ([A-Za-z]+)", 1, Message),
    Protocol = extract("([A-Za-z]+) request", 1, Message),
    SourceIP = extract("from ([0-9.]+):", 1, Message),
    DestFQDN = extract("to ([^:]+):", 1, Message)
| project TimeGenerated, Action, Protocol, SourceIP, DestFQDN, Message
| order by TimeGenerated desc
| take 50
```

**What you'll see:**
- **Action: Allow** - Traffic permitted by rules
- **Action: Deny** - Traffic blocked (like google.com)
- Source IP will be your VM's private IP (10.0.2.4)
- Destination will show the FQDN you tried to access

</details>

---

**💡 What you learned:**
- How to test explicit proxy functionality
- Expected behavior for allowed vs blocked sites  
- Difference between allowed and denied traffic
- (Optional) How to enable and query firewall logs for troubleshooting

---

#### 🧹 Cleanup Lab 1

When you're done with Lab 1, use the cleanup script:

📁 **Script Location**: `scripts/Cleanup-Labs.ps1`

```powershell
cd scripts
.\Cleanup-Labs.ps1 -Lab Lab1
```

Or manually:
```powershell
Remove-AzResourceGroup -Name "RG-AFEP-Lab1" -Force -AsJob
```

---

### ✅ Lab 2: PAC File Configuration

**Goal**: Automate proxy settings using PAC file hosted in Azure Storage.

**Estimated Time**: 15-25 minutes (automated infrastructure + manual PAC config)

#### Step 1: Deploy Storage and Upload PAC File (AUTOMATED)

**Run the PowerShell deployment script:**

📁 **Script Location**: `scripts/Deploy-Lab2-PAC-Infrastructure.ps1`

**To run:**

```powershell
cd scripts
.\Deploy-Lab2-PAC-Infrastructure.ps1
```

**Optional parameters:**
```powershell
.\Deploy-Lab2-PAC-Infrastructure.ps1 -ResourceGroupName "RG-AFEP-Lab1" -FirewallPrivateIP "10.0.0.4"
```

**What the script does:**
- ✅ Creates Azure Storage Account
- ✅ Creates blob container for PAC files
- ✅ Generates PAC file with proxy routing logic
- ✅ Uploads PAC file to blob storage
- ✅ Generates 7-day SAS token for secure access
- ✅ Saves PAC info to `Lab2-PAC-Info.json`

**⏱️ Deployment Time**: 2-3 minutes

**⚠️ IMPORTANT**: Copy the SAS URL from the output - you'll need it in the next step!

---

#### Step 2: Configure PAC File in Firewall Policy (MANUAL - Learn AFEP)

**🎯 Learn how to enable PAC file auto-configuration**

1. In Azure Portal, navigate to your Firewall resource (`afw-lab1`)
2. Under **Settings**, click **Firewall Policy**
3. Click on the policy name link `afp-lab1`
4. In the left menu under **Settings**, click **Explicit Proxy (Preview)**
5. In the **Proxy auto-configuration (PAC)** section:
   - Toggle **Enable proxy auto-configuration** to **ON**
   - **PAC file URL**: Paste the **SAS URL** from Step 1 output (or from `Lab2-PAC-Info.json`)
   - **PAC file port**: `8090` (different from HTTP/HTTPS proxy ports)
6. Click **Apply** button (top of page)
7. Wait for "Update succeeded" notification (~30-60 seconds)

**💡 What you learned:**
- How to configure PAC file auto-configuration in Azure Firewall
- PAC file requires a separate port (8090)
- SAS tokens provide secure access to PAC files

---

#### Step 3: Configure Client to Use PAC File (MANUAL - Learn AFEP)

**🎯 Learn automatic proxy configuration**

1. **RDP into your Client VM** (`vm-client-lab1`)
2. **Remove manual proxy settings first**:
   - Press **Windows key + I** → **Network & Internet** → **Proxy**
   - Under **Manual proxy setup**, toggle **Use a proxy server** to **OFF**
   - Click **Save**

3. **Configure automatic proxy using PAC**:
   - Still in **Proxy** settings
   - Under **Automatic proxy setup**:
     - Toggle **Automatically detect settings** to **OFF**
     - Toggle **Use setup script** to **ON**
     - **Script address**: Paste your **SAS URL** from `Lab2-PAC-Info.json`
     - Click **Save** button

**💡 What you learned:**
- Difference between manual proxy and automatic (PAC) configuration
- How clients retrieve and use PAC files
- PAC file provides dynamic proxy routing

---

#### Step 4: Test PAC File Configuration (MANUAL - Learn AFEP)

**🎯 Validate PAC file routing logic**

1. **On the Client VM**, test PAC file is accessible:
   ```cmd
   curl http://10.0.0.4:8090/proxy.pac
   ```
   ✅ **Expected**: You should see the JavaScript PAC file content

2. **Test routing**:
   - Open **Microsoft Edge**
   - Navigate to `http://www.microsoft.com` → Should work (routed via proxy per PAC logic)
   - Navigate to `http://www.bing.com` → Should work (routed via proxy)

3. **Verify proxy resolution in PowerShell**:
   ```powershell
   [System.Net.WebRequest]::GetSystemWebProxy().GetProxy("http://www.microsoft.com")
   ```
   ✅ **Expected**: Should show `http://10.0.0.4:8081` (or whatever HTTP port you configured)

**💡 What you learned:**
- How to verify PAC file is being served by the firewall
- PAC file routing logic execution
- Troubleshooting PAC file issues

---

### ✅ Lab 3: Hub-and-Spoke Topology

**Goal**: Implement AFEP in enterprise hub-and-spoke architecture.

**Estimated Time**: 30-45 minutes (automated infrastructure + manual AFEP config)

#### Step 1: Deploy Hub-Spoke Infrastructure (AUTOMATED)

**Run the PowerShell deployment script:**

📁 **Script Location**: `scripts/Deploy-Lab3-HubSpoke-Infrastructure.ps1`

**To run:**

```powershell
cd scripts
.\Deploy-Lab3-HubSpoke-Infrastructure.ps1 -AdminPassword (ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force)
```

**Optional parameters:**
```powershell
.\Deploy-Lab3-HubSpoke-Infrastructure.ps1 -AdminPassword $password -Location "Sweden Central" -ResourceGroupName "RG-AFEP-HubSpoke"
```

**What the script does:**
- ✅ Creates Hub VNet (10.0.0.0/16) with AzureFirewallSubnet (/26)
- ✅ Creates Spoke1 VNet (10.1.0.0/16) for workload 1
- ✅ Creates Spoke2 VNet (10.2.0.0/16) for workload 2
- ✅ Configures VNet peering between Hub and Spokes
- ✅ Deploys Azure Firewall Premium in Hub
- ✅ Creates route tables to route traffic through firewall
- ✅ Deploys VMs in both spoke networks
- ✅ Saves deployment details to `Lab3-DeploymentInfo.json`

**⏱️ Deployment Time**: 15-20 minutes

**💡 Important**: This creates an enterprise hub-spoke topology with centralized firewall!

# 1. Create Resource Group
Write-Host "`n📦 Creating Resource Group: $ResourceGroupName" -ForegroundColor Yellow
$rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force
Write-Host "✅ Resource Group created" -ForegroundColor Green

# 2. Create Hub VNet
Write-Host "`n🌐 Creating Hub VNet..." -ForegroundColor Yellow
$hubFirewallSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "AzureFirewallSubnet" `
    -AddressPrefix "10.0.0.0/26"

$hubSharedSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "SharedServices" `
    -AddressPrefix "10.0.2.0/24"

$hubVnet = New-AzVirtualNetwork `
    -Name "Hub-VNet" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AddressPrefix "10.0.0.0/16" `
    -Subnet $hubFirewallSubnet, $hubSharedSubnet

Write-Host "✅ Hub VNet created" -ForegroundColor Green

# 3. Create Spoke1 VNet
Write-Host "`n🌐 Creating Spoke1 VNet..." -ForegroundColor Yellow
$spoke1Subnet = New-AzVirtualNetworkSubnetConfig `
    -Name "Workload1-Subnet" `
    -AddressPrefix "10.1.0.0/24"

$spoke1Vnet = New-AzVirtualNetwork `
    -Name "Spoke1-VNet" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AddressPrefix "10.1.0.0/16" `
    -Subnet $spoke1Subnet

Write-Host "✅ Spoke1 VNet created" -ForegroundColor Green

# 4. Create Spoke2 VNet
Write-Host "`n🌐 Creating Spoke2 VNet..." -ForegroundColor Yellow
$spoke2Subnet = New-AzVirtualNetworkSubnetConfig `
    -Name "Workload2-Subnet" `
    -AddressPrefix "10.2.0.0/24"

$spoke2Vnet = New-AzVirtualNetwork `
    -Name "Spoke2-VNet" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AddressPrefix "10.2.0.0/16" `
    -Subnet $spoke2Subnet

Write-Host "✅ Spoke2 VNet created" -ForegroundColor Green

# 5. Create VNet Peerings
Write-Host "`n🔗 Creating VNet Peerings..." -ForegroundColor Yellow

Add-AzVirtualNetworkPeering `
    -Name "Hub-to-Spoke1" `
    -VirtualNetwork $hubVnet `
    -RemoteVirtualNetworkId $spoke1Vnet.Id `
    -AllowForwardedTraffic `
    -AllowGatewayTransit | Out-Null

Add-AzVirtualNetworkPeering `
    -Name "Spoke1-to-Hub" `
    -VirtualNetwork $spoke1Vnet `
    -RemoteVirtualNetworkId $hubVnet.Id `
    -AllowForwardedTraffic `
    -UseRemoteGateways:$false | Out-Null

Add-AzVirtualNetworkPeering `
    -Name "Hub-to-Spoke2" `
    -VirtualNetwork $hubVnet `
    -RemoteVirtualNetworkId $spoke2Vnet.Id `
    -AllowForwardedTraffic `
    -AllowGatewayTransit | Out-Null

Add-AzVirtualNetworkPeering `
    -Name "Spoke2-to-Hub" `
    -VirtualNetwork $spoke2Vnet `
    -RemoteVirtualNetworkId $hubVnet.Id `
    -AllowForwardedTraffic `
    -UseRemoteGateways:$false | Out-Null

Write-Host "✅ VNet Peerings created" -ForegroundColor Green

# 6. Create Firewall Public IP
Write-Host "`n🌍 Creating Firewall Public IP..." -ForegroundColor Yellow
$firewallPip = New-AzPublicIpAddress `
    -Name "pip-firewall-hub" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AllocationMethod Static `
    -Sku Standard

Write-Host "✅ Firewall Public IP created" -ForegroundColor Green

# 7. Create Firewall Policy
Write-Host "`n🛡️  Creating Firewall Policy..." -ForegroundColor Yellow
$firewallPolicy = New-AzFirewallPolicy `
    -Name "afp-hub-policy" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -ThreatIntelMode "Alert" `
    -SkuTier "Premium"

$firewallPolicy.DnsSettings = New-Object Microsoft.Azure.Commands.Network.Models.PSAzureFirewallPolicyDnsSettings
$firewallPolicy.DnsSettings.EnableProxy = $true
Set-AzFirewallPolicy -InputObject $firewallPolicy | Out-Null

Write-Host "✅ Firewall Policy created (Premium)" -ForegroundColor Green

# 8. Deploy Azure Firewall
Write-Host "`n🔥 Deploying Azure Firewall (Premium) in Hub (8-12 minutes)..." -ForegroundColor Yellow
$hubVnet = Get-AzVirtualNetwork -Name "Hub-VNet" -ResourceGroupName $ResourceGroupName
$firewall = New-AzFirewall `
    -Name "afw-hub" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -VirtualNetwork $hubVnet `
    -PublicIpAddress $firewallPip `
    -FirewallPolicyId $firewallPolicy.Id `
    -Sku AZFW_VNet `
    -Tier Premium

Write-Host "✅ Azure Firewall deployed in Hub" -ForegroundColor Green
$firewallPrivateIP = $firewall.IpConfigurations[0].PrivateIPAddress

# 9. Create Route Tables
Write-Host "`n🛣️  Creating Route Tables for Spokes..." -ForegroundColor Yellow

# Route Table for Spoke1
$route1 = New-AzRouteConfig `
    -Name "default-via-firewall" `
    -AddressPrefix "0.0.0.0/0" `
    -NextHopType "VirtualAppliance" `
    -NextHopIpAddress $firewallPrivateIP

$routeTable1 = New-AzRouteTable `
    -Name "rt-spoke1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Route $route1 `
    -DisableBgpRoutePropagation

$spoke1Vnet = Get-AzVirtualNetwork -Name "Spoke1-VNet" -ResourceGroupName $ResourceGroupName
$spoke1Subnet = Get-AzVirtualNetworkSubnetConfig -Name "Workload1-Subnet" -VirtualNetwork $spoke1Vnet
$spoke1Subnet.RouteTable = $routeTable1
Set-AzVirtualNetwork -VirtualNetwork $spoke1Vnet | Out-Null

# Route Table for Spoke2
$route2 = New-AzRouteConfig `
    -Name "default-via-firewall" `
    -AddressPrefix "0.0.0.0/0" `
    -NextHopType "VirtualAppliance" `
    -NextHopIpAddress $firewallPrivateIP

$routeTable2 = New-AzRouteTable `
    -Name "rt-spoke2" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Route $route2 `
    -DisableBgpRoutePropagation

$spoke2Vnet = Get-AzVirtualNetwork -Name "Spoke2-VNet" -ResourceGroupName $ResourceGroupName
$spoke2Subnet = Get-AzVirtualNetworkSubnetConfig -Name "Workload2-Subnet" -VirtualNetwork $spoke2Vnet
$spoke2Subnet.RouteTable = $routeTable2
Set-AzVirtualNetwork -VirtualNetwork $spoke2Vnet | Out-Null

Write-Host "✅ Route Tables created and associated" -ForegroundColor Green

# 10. Deploy VMs in Spokes
Write-Host "`n💻 Deploying VMs in Spoke networks (5-7 minutes)..." -ForegroundColor Yellow

# VM in Spoke1
$spoke1Vnet = Get-AzVirtualNetwork -Name "Spoke1-VNet" -ResourceGroupName $ResourceGroupName
$spoke1Subnet = Get-AzVirtualNetworkSubnetConfig -Name "Workload1-Subnet" -VirtualNetwork $spoke1Vnet

$spoke1Pip = New-AzPublicIpAddress `
    -Name "pip-vm-spoke1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AllocationMethod Static `
    -Sku Standard

$spoke1Nic = New-AzNetworkInterface `
    -Name "vm-spoke1-nic" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -SubnetId $spoke1Subnet.Id `
    -PublicIpAddressId $spoke1Pip.Id

$vmConfig1 = New-AzVMConfig -VMName "vm-spoke1" -VMSize "Standard_B2s" | `
    Set-AzVMOperatingSystem -Windows -ComputerName "vm-spoke1" -Credential (New-Object PSCredential("azureadmin", $AdminPassword)) | `
    Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | `
    Add-AzVMNetworkInterface -Id $spoke1Nic.Id | `
    Set-AzVMBootDiagnostic -Disable

New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig1 -AsJob | Out-Null

# VM in Spoke2
$spoke2Vnet = Get-AzVirtualNetwork -Name "Spoke2-VNet" -ResourceGroupName $ResourceGroupName
$spoke2Subnet = Get-AzVirtualNetworkSubnetConfig -Name "Workload2-Subnet" -VirtualNetwork $spoke2Vnet

$spoke2Pip = New-AzPublicIpAddress `
    -Name "pip-vm-spoke2" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AllocationMethod Static `
    -Sku Standard

$spoke2Nic = New-AzNetworkInterface `
    -Name "vm-spoke2-nic" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -SubnetId $spoke2Subnet.Id `
    -PublicIpAddressId $spoke2Pip.Id

$vmConfig2 = New-AzVMConfig -VMName "vm-spoke2" -VMSize "Standard_B2s" | `
    Set-AzVMOperatingSystem -Windows -ComputerName "vm-spoke2" -Credential (New-Object PSCredential("azureadmin", $AdminPassword)) | `
    Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | `
    Add-AzVMNetworkInterface -Id $spoke2Nic.Id | `
    Set-AzVMBootDiagnostic -Disable

New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig2 -AsJob | Out-Null

Write-Host "✅ VM deployments started (running in background)" -ForegroundColor Green

# Wait for VM deployments
Write-Host "`n⏳ Waiting for VM deployments to complete..." -ForegroundColor Yellow
Get-Job | Wait-Job | Out-Null
Get-Job | Remove-Job

$spoke1Pip = Get-AzPublicIpAddress -Name "pip-vm-spoke1" -ResourceGroupName $ResourceGroupName
$spoke2Pip = Get-AzPublicIpAddress -Name "pip-vm-spoke2" -ResourceGroupName $ResourceGroupName

Write-Host "✅ All VMs deployed" -ForegroundColor Green

# Summary
Write-Host "`n" + ("="*80) -ForegroundColor Cyan
Write-Host "🎉 Lab 3 Hub-Spoke Infrastructure Deployment Complete!" -ForegroundColor Green
Write-Host ("="*80) -ForegroundColor Cyan
Write-Host "`nDeployment Summary:" -ForegroundColor Yellow
Write-Host "  Hub VNet: Hub-VNet (10.0.0.0/16)"
Write-Host "  Spoke1 VNet: Spoke1-VNet (10.1.0.0/16)"
Write-Host "  Spoke2 VNet: Spoke2-VNet (10.2.0.0/16)"
Write-Host "  Firewall Name: afw-hub (Premium SKU)"
Write-Host "  Firewall Private IP: $firewallPrivateIP"
Write-Host "  Firewall Public IP: $($firewallPip.IpAddress)"
Write-Host "  VM Spoke1 Public IP: $($spoke1Pip.IpAddress)"
Write-Host "  VM Spoke2 Public IP: $($spoke2Pip.IpAddress)"
Write-Host "  Admin Username: azureadmin"
Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Enable Explicit Proxy with PAC file (see Step 2 below)"
Write-Host "  2. Create Application Rules for Hub-Spoke (see Step 3 below)"
Write-Host "  3. Configure proxy on Spoke VMs (see Step 4 below)"
Write-Host "  4. Test hub-spoke connectivity (see Step 5 below)"
Write-Host ("="*80) -ForegroundColor Cyan

# Save deployment info
$deploymentInfo = @{
    ResourceGroup = $ResourceGroupName
    Location = $Location
    FirewallPrivateIP = $firewallPrivateIP
    FirewallPublicIP = $firewallPip.IpAddress
    Spoke1VMPublicIP = $spoke1Pip.IpAddress
    Spoke2VMPublicIP = $spoke2Pip.IpAddress
    FirewallPolicyId = $firewallPolicy.Id
} | ConvertTo-Json

$deploymentInfo | Out-File -FilePath ".\Lab3-DeploymentInfo.json" -Force
Write-Host "`n💾 Deployment info saved to: Lab3-DeploymentInfo.json" -ForegroundColor Green
```

**To run the script:**

```powershell
.\Deploy-Lab3-HubSpoke-Infrastructure.ps1 -AdminPassword (ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force)
```

---

#### Step 2: Enable Explicit Proxy with PAC File (MANUAL - Learn AFEP)

**🎯 Learn advanced PAC file configuration for hub-spoke**

1. **Create advanced PAC file** on your local computer:
   
   Save as `proxy-hubspoke.pac`:
   ```javascript
   function FindProxyForURL(url, host) {
       // Internal networks (bypass proxy)
       if (isInNet(host, "10.0.0.0", "255.0.0.0") ||
           isInNet(host, "172.16.0.0", "255.240.0.0") ||
           isInNet(host, "192.168.0.0", "255.255.0.0")) {
           return "DIRECT";
       }
       
       // Internal domains
       if (dnsDomainIs(host, ".internal.company.com") ||
           dnsDomainIs(host, ".corp.local") ||
           isPlainHostName(host)) {
           return "DIRECT";
       }
       
       // External traffic via proxy with fallback
       return "PROXY 10.0.0.4:8080; DIRECT";
   }
   ```

2. **Upload to storage** (use Lab 2 script or manual upload)

3. **Configure in Firewall Policy**:
   - Navigate to Firewall `afw-hub` → **Firewall Policy** → `afp-hub-policy`
   - Click **Explicit Proxy (Preview)**
   - **Enable Explicit Proxy**: ON
   - **HTTP Port**: `8081` (use 8081 or 8082 if 8080 is blocked in your region)
   - **HTTPS Port**: `8443`
   - **Enable proxy auto-configuration**: ON
   - **PAC file URL**: Your SAS URL
   - **PAC file port**: `8090`
   - Click **Apply**

**💡 What you learned:**
- Advanced PAC file logic for hub-spoke topologies
- Network-based routing (DIRECT for internal, PROXY for external)
- Fallback mechanisms in PAC files

---

#### Step 3: Create Application Rules (MANUAL - Learn AFEP)

**🎯 Learn rule configuration for multiple spokes**

1. Navigate to Firewall Policy `afp-hub-policy` → **Application Rules**
2. Click **+ Add a rule collection**
3. Configure:
   - **Name**: `AllowWebTrafficHubSpoke`
   - **Priority**: `100`
   - **Action**: **Allow**
   - Add rules:
     - **Name**: `AllowMicrosoft`
     - **Source**: `10.1.0.0/16,10.2.0.0/16` (both spokes)
     - **Protocol**: `http:80,https:443`
     - **Destination type**: **FQDN**
     - **Destination**: `*.microsoft.com,*.azure.com`
4. Click **Add**

**💡 What you learned:**
- Multi-source application rules (multiple spoke networks)
- Wildcard FQDN filtering
- Rule efficiency for hub-spoke architectures

---

#### Step 4: Configure Proxy on Spoke VMs (MANUAL - Learn AFEP)

**🎯 Learn client configuration in spoke networks**

RDP into both `vm-spoke1` and `vm-spoke2` and configure proxy settings (manual or PAC file method from Lab 1/2).

**💡 What you learned:**
- Consistent proxy configuration across multiple spokes
- PAC file simplifies multi-site deployments

---

#### Step 5: Test Hub-Spoke Topology (MANUAL - Learn AFEP)

**🎯 Validate enterprise topology**

1. **From vm-spoke1**, test:
   - Ping `vm-spoke2` private IP (10.2.0.4) - Should work (VNet peering)
   - Browse to `https://www.microsoft.com` - Should work via proxy
   - Browse to `https://www.google.com` - Should fail (not in rules)

2. **Verify in Azure Monitor**:
   - Check firewall logs show traffic from both spoke subnets
   - Confirm routing through firewall

**💡 What you learned:**
- Hub-spoke traffic flow validation
- Multi-spoke proxy architecture
- Centralized security enforcement

---

#### 🧹 Cleanup Lab 3

When you're done with Lab 3, use the cleanup script:

📁 **Script Location**: `scripts/Cleanup-Labs.ps1`

```powershell
cd scripts
.\Cleanup-Labs.ps1 -Lab Lab3
```

Or manually:
```powershell
Remove-AzResourceGroup -Name "RG-AFEP-HubSpoke" -Force -AsJob
```

**Cleanup all labs:**
```powershell
.\Cleanup-Labs.ps1 -Lab All
```

---

## Summary

This automated guide helps you:

✅ **Focus on learning AFEP** - Infrastructure is automated  
✅ **Hands-on AFEP configuration** - You manually configure the important parts  
✅ **Real-world scenarios** - Hub-spoke, PAC files, application rules  
✅ **Save time** - 10-15 minute infrastructure deployments instead of 45-60 minutes  

### What You'll Master

- Enabling and configuring Explicit Proxy
- Creating application rules (not network rules!)
- PAC file configuration and hosting
- Client proxy configuration
- Hub-spoke topology implementation
- Azure Monitor log analysis
- Troubleshooting AFEP issues

---

## Best Practices

For complete best practices, troubleshooting, and validation checklists, see the main [README.md](README.md) file.

---

**Document Version**: 1.0 (Automated)  
**Last Updated**: November 6, 2025  
**Compatible with**: README.md v1.0
