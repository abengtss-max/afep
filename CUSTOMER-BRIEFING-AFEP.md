# Azure Firewall Explicit Proxy - Customer Briefing

## Why Azure Firewall Explicit Proxy?

**Provide centralised, application-layer control for outbound web traffic (HTTP/HTTPS) without relying on complex network routing.**

Instead of forcing all traffic through the firewall using UDRs, clients explicitly send web requests to the firewall's proxy ports. This enables:

- **Granular filtering by FQDN and URL categories** - Control exactly which websites and web services are accessible
- **TLS inspection for secure traffic** - Decrypt and inspect HTTPS traffic for threats (Premium SKU)
- **Simplified management with PAC files for automation** - Centrally manage proxy configuration across all clients
- **Better scalability and reduced firewall load compared to full Layer 4 routing** - Process only HTTP/HTTPS at Layer 7 instead of all protocols at Layer 4

## How Azure Firewall Explicit Proxy Works

Azure Firewall Explicit Proxy acts as a forward proxy that intercepts outbound HTTP/HTTPS traffic from clients. Instead of routing all traffic through UDRs, clients explicitly configure their proxy settings to send web requests directly to the firewall's private IP on specific ports (typically 8081/8443), where the firewall applies application rules and TLS inspection before forwarding to the internet.

## PAC Files - Purpose and Configuration

**What is PAC?** PAC (Proxy Auto-Configuration) is an **industry standard** (not Microsoft-specific) JavaScript function that browsers use to automatically determine which proxy server to use for each URL. It originated from Netscape in the 1990s and is supported by all modern browsers.

**Best Practice Configuration:** Host the PAC file in Azure Storage with a SAS token URL, configure it in the Firewall Policy's Explicit Proxy settings, and clients retrieve it automatically from the firewall on port 8090 (default). The PAC file should include logic for internal networks to bypass the proxy (`return "DIRECT"`) and route internet traffic through different ports for HTTP (8081) and HTTPS (8443).

## 5 Essential Troubleshooting Tips

### 1. **Verify Proxy Connectivity from Client**
```powershell
# Test if firewall proxy ports are reachable
Test-NetConnection -ComputerName 10.0.0.4 -Port 8081
Test-NetConnection -ComputerName 10.0.0.4 -Port 8443
Test-NetConnection -ComputerName 10.0.0.4 -Port 8090  # PAC file port
```

### 2. **Check Client Proxy Configuration**
```powershell
# Verify proxy settings are applied
Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" | 
    Select-Object ProxyServer, ProxyEnable, AutoConfigURL

# Check WinHTTP proxy (for apps)
netsh winhttp show proxy
```

### 3. **Test Actual Proxy Functionality**
```powershell
# Test HTTP through proxy
$proxy = New-Object System.Net.WebProxy("http://10.0.0.4:8081")
$client = New-Object System.Net.WebClient
$client.Proxy = $proxy
$client.DownloadString("http://www.microsoft.com") | Select-String -Pattern "Microsoft"

# If you get Error 470 = Firewall policy is blocking the request
```

### 4. **Enable Firewall Diagnostic Logs (Azure Portal)**
```bash
# In Azure Portal:
# 1. Navigate to Firewall → Diagnostic settings → Add diagnostic setting
# 2. Enable these log categories:
#    - AzureFirewallApplicationRule (shows allow/deny decisions)
#    - AzureFirewallNetworkRule
#    - AZFWApplicationRule (new explicit proxy logs)
# 3. Send to Log Analytics Workspace

# Query Application Rule logs in Log Analytics:
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s, Action_s
| order by TimeGenerated desc
```

### 5. **Verify Firewall Policy Configuration (PowerShell)**
```powershell
# Check Explicit Proxy settings
$policy = Get-AzFirewallPolicy -Name "YourPolicyName" -ResourceGroupName "YourRG"

Write-Host "Explicit Proxy Enabled: $($policy.ExplicitProxy.EnableExplicitProxy)"
Write-Host "HTTP Port: $($policy.ExplicitProxy.HttpPort)"
Write-Host "HTTPS Port: $($policy.ExplicitProxy.HttpsPort)"
Write-Host "PAC File Enabled: $($policy.ExplicitProxy.EnablePacFile)"
Write-Host "PAC File URL: $($policy.ExplicitProxy.PacFileUrl)"

# Check Application Rules
$rcg = Get-AzFirewallPolicyRuleCollectionGroup -Name "DefaultApplicationRuleCollectionGroup" `
    -ResourceGroupName "YourRG" -AzureFirewallPolicyName "YourPolicyName"

$rcg.Properties.RuleCollection | ForEach-Object {
    $_.Rules | Select-Object Name, SourceAddresses, TargetFqdns
}
```

---

## UDR Requirements in Hub-and-Spoke Topology

**NO, UDRs are NOT required for Explicit Proxy traffic.**

When using Azure Firewall Explicit Proxy:
- **Client-to-Proxy traffic:** Clients send requests directly to the firewall's private IP (10.0.x.x:8081/8443) - no routing needed, it's application-layer
- **Proxy-to-Internet traffic:** The firewall itself handles outbound connections using its own public IP

**When UDRs ARE still needed:**
- Non-HTTP/HTTPS traffic (RDP, SSH, database connections, etc.)
- Legacy applications that don't support proxy configuration
- East-West traffic between spokes that must be inspected

**Hub-Spoke Best Practice:**
- Use **Explicit Proxy** for HTTP/HTTPS web traffic (90% of internet traffic)
- Use **UDRs (0.0.0.0/0 → Firewall)** for all other protocols
- This hybrid approach reduces firewall load and provides better visibility into web traffic

**⚡ Performance Consideration - Why This Matters:**

**With UDR-based routing (Layer 4):** The firewall processes ALL traffic at the network layer, including every packet for all protocols (HTTP, HTTPS, RDP, SSH, SQL, etc.). This is a **heavier load** because it involves stateful inspection and connection tracking for all flows through the firewall.

**With Explicit Proxy (Layer 7):** The firewall only processes application-layer HTTP/HTTPS requests that are explicitly sent to it. This is **much lighter** because:
- It handles fewer protocols (only web traffic)
- It focuses on web-specific features: FQDN filtering, TLS inspection, URL categorization
- Non-web traffic bypasses the explicit proxy entirely or uses selective UDRs
- The firewall can optimize for HTTP/HTTPS performance specifically

**Real-world impact:** A hub with 1000 VMs generating RDP, database, file share, and web traffic would process significantly less through the firewall when using Explicit Proxy for web traffic. This improves throughput, reduces latency, and lowers costs.

---

## Use Cases and Benefits

### Use Case 1: **Software-as-a-Service (SaaS) Application Control**
**Scenario:** Organization needs to allow Microsoft 365, Salesforce, and ServiceNow but block all other internet sites.

**Benefits:**
- **Granular FQDN filtering** - Allow specific subdomains like `*.office365.com`, `*.salesforce.com`
- **URL categorization** - Block by category (social media, gambling, adult content)
- **TLS inspection** (Premium SKU) - Inspect encrypted HTTPS traffic for malware/data exfiltration
- **User identity awareness** - Log which users accessed which websites (with IdP integration)

**Why Explicit Proxy wins:** Traditional firewall rules require IP ranges which constantly change for SaaS apps. Explicit Proxy uses FQDNs that automatically resolve.

### Use Case 2: **Developer Workstations with Selective Internet Access**
**Scenario:** Dev/Test environments need access to GitHub, Azure DevOps, NuGet, npm registries but must block general internet browsing.

**Benefits:**
- **PAC file automation** - Developers get correct proxy settings automatically, no manual configuration
- **Protocol-specific handling** - Route HTTP/HTTPS through proxy, allow direct connections for SSH/Git protocols
- **Bypass for internal resources** - PAC file routes `.internal.company.com` traffic directly, not through proxy
- **Faster updates** - Change allowed sites in firewall policy, PAC file updates automatically from Azure Storage

**Why Explicit Proxy wins:** No need to update UDRs or NSGs when adding new developer tool FQDNs. Central policy management with immediate effect.

### Use Case 3: **Compliance and Data Loss Prevention (DLP)**
**Scenario:** Financial services company must prove all internet traffic is logged and inspected per regulatory requirements (GDPR, SOC2, PCI-DSS).

**Benefits:**
- **Complete URL logging** - Every HTTPS request logged with full URL, not just destination IP
- **Certificate inspection** - TLS inspection validates certificates and detects man-in-the-middle attacks
- **Content filtering** - Block file uploads to non-approved cloud storage (Dropbox, Google Drive)
- **Audit trail** - Diagnostic logs show WHO accessed WHAT and WHEN with deny reasons

**Why Explicit Proxy wins:** Network-layer firewalls only see encrypted traffic. Explicit Proxy with TLS inspection sees the actual HTTP requests inside the encryption.

---

## Quick Reference Commands

### Client-Side Diagnostics (Run on Windows VM)
```powershell
# One-liner to check everything
$fw="10.0.0.4"; Test-NetConnection $fw -Port 8081 | Select ComputerName,TcpTestSucceeded; Test-NetConnection $fw -Port 8443 | Select ComputerName,TcpTestSucceeded; Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" | Select ProxyServer,ProxyEnable,AutoConfigURL
```

### Azure-Side Diagnostics (Run from Azure Cloud Shell or local machine)
```powershell
# Quick firewall health check
$fw = Get-AzFirewall -Name "afw-hub" -ResourceGroupName "RG-HubSpoke"
$policy = Get-AzFirewallPolicy -ResourceGroupName "RG-HubSpoke" -Name $fw.FirewallPolicy.Id.Split('/')[-1]

Write-Host "`n=== Firewall Status ===" -ForegroundColor Cyan
Write-Host "State: $($fw.ProvisioningState)" -ForegroundColor $(if($fw.ProvisioningState -eq 'Succeeded'){'Green'}else{'Red'})
Write-Host "Private IP: $($fw.IpConfigurations[0].PrivateIPAddress)"
Write-Host "`n=== Explicit Proxy ===" -ForegroundColor Cyan
Write-Host "Enabled: $($policy.ExplicitProxy.EnableExplicitProxy)" -ForegroundColor $(if($policy.ExplicitProxy.EnableExplicitProxy){'Green'}else{'Red'})
Write-Host "HTTP Port: $($policy.ExplicitProxy.HttpPort)"
Write-Host "HTTPS Port: $($policy.ExplicitProxy.HttpsPort)"
Write-Host "PAC File: $($policy.ExplicitProxy.EnablePacFile)"
```

---

## Key Takeaways for Customer

1. ✅ **Explicit Proxy is application-layer** - Works at HTTP/HTTPS level, not network routing
2. ✅ **No UDRs needed for proxy traffic** - Clients connect directly to firewall IP
3. ✅ **PAC files automate client configuration** - Industry standard, not Microsoft proprietary
4. ✅ **Best for web traffic control** - Complements traditional firewall rules
5. ✅ **TLS inspection requires Premium SKU** - Standard SKU does FQDN filtering without decryption

**Licensing Note:** Explicit Proxy is available in both Standard and Premium SKUs. Premium adds TLS inspection, IDPS, and URL filtering.

---

**Document Version:** 1.0  
**Last Updated:** November 7, 2025  
**Based on:** [Microsoft Docs - Azure Firewall Explicit Proxy](https://learn.microsoft.com/azure/firewall/explicit-proxy)

---

## 🏢 Enterprise Deployment: PAC Enforcement at Scale

### The Challenge
For enterprises with **hundreds of spokes and thousands of VMs**, manually configuring proxy settings on each VM is not feasible. You need **centralized, automated enforcement** that ensures all VMs use the firewall's explicit proxy without manual intervention.

### Enterprise-Grade Solutions

#### **1. Azure Policy + Guest Configuration (✅ Recommended)**

Deploy PAC settings via **Azure Policy Guest Configuration** to automatically configure all Windows/Linux VMs at scale.

**How it works:**
- Create a custom Guest Configuration policy that sets registry keys for WinHTTP/WinINET proxy settings
- Configure PAC URL: `http://<firewall-ip>:8090/proxy.pac`
- Apply policy at subscription or management group level
- Azure automatically configures all VMs (existing and new)

**Benefits:**
- ✅ Automatic enforcement across hundreds of spokes
- ✅ Continuous compliance monitoring with auto-remediation
- ✅ No need to touch individual VMs
- ✅ Works for both Windows and Linux
- ✅ Centrally managed from Azure Portal

**Example Policy Configuration:**
```powershell
# Policy applies these settings to all VMs
Registry Path: HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
Key: AutoConfigURL
Value: http://10.0.0.4:8090/proxy.pac
```

---

#### **2. Group Policy (GPO) - For Domain-Joined VMs**

For hybrid environments or VMs joined to Azure AD Domain Services:

**Configuration Path:**
```
Computer Configuration → Policies → Administrative Templates → 
Windows Components → Internet Explorer → 
"Use automatic configuration script" → Enabled
PAC URL: http://10.0.0.4:8090/proxy.pac
```

**Benefits:**
- ✅ Single GPO applies to all domain-joined VMs automatically
- ✅ Enforced at boot/login - users cannot disable
- ✅ Works with Azure AD Domain Services or hybrid AD
- ✅ Familiar management for IT administrators

---

#### **3. Azure VM Extensions (Bootstrap at Creation)**

Deploy PAC configuration during VM creation using **Custom Script Extension**:

**ARM/Bicep Template Example:**
```json
{
  "type": "Microsoft.Compute/virtualMachines/extensions",
  "name": "[concat(parameters('vmName'), '/ConfigureProxy')]",
  "properties": {
    "publisher": "Microsoft.Compute",
    "type": "CustomScriptExtension",
    "typeHandlerVersion": "1.10",
    "settings": {
      "commandToExecute": "powershell -command \"Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings' -Name AutoConfigURL -Value 'http://10.0.0.4:8090/proxy.pac'\""
    }
  }
}
```

**Benefits:**
- ✅ Every new VM gets proxy configuration automatically
- ✅ Can be included in infrastructure-as-code (ARM/Bicep/Terraform)
- ✅ Works with VM Scale Sets for auto-scaling scenarios
- ✅ Zero manual configuration required

---

#### **4. Azure Virtual Desktop (AVD) - Session Host Configuration**

For AVD environments with hundreds of session hosts:

**Approach:**
- Configure proxy settings in golden image
- Or use FSLogix profile containers with proxy settings
- Or apply via host pool configuration scripts

**Benefits:**
- ✅ All session hosts inherit configuration
- ✅ Consistent user experience across all sessions
- ✅ Scales to thousands of concurrent users

---

#### **5. Container Environments (AKS/ACA)**

For containerized workloads in Azure Kubernetes Service or Container Apps:

**Kubernetes Example:**
```yaml
env:
  - name: HTTP_PROXY
    value: "http://10.0.0.4:8081"
  - name: HTTPS_PROXY
    value: "http://10.0.0.4:8443"
  - name: NO_PROXY
    value: "localhost,127.0.0.1,.svc.cluster.local"
```

**Or configure at AKS node level** for cluster-wide proxy settings.

**Benefits:**
- ✅ All pods inherit proxy configuration
- ✅ No per-container configuration needed
- ✅ Supports both HTTP and HTTPS protocols

---

### Architecture: Hub-Spoke with 100s of Spokes

```
                Hub VNet (10.0.0.0/16)
         Azure Firewall with Explicit Proxy
         PAC URL: http://10.0.0.4:8090/proxy.pac
                        │
        ┌───────────────┼───────────────┐
        │               │               │
    Spoke 1         Spoke 2         Spoke N
   (50 VMs)        (75 VMs)       (100 VMs)
        │               │               │
   Azure Policy → Enforces PAC on ALL VMs ←┘
```

**Key Architecture Points:**

1. **Single Hub Firewall** - All spokes peer to hub VNet
2. **No UDRs Required** - HTTP/HTTPS traffic goes directly via proxy (major simplification!)
3. **PAC Hosted on Firewall** - Port 8090, single source of truth
4. **Azure Policy Enforcement** - Continuously monitors and auto-remediates all VMs
5. **Automatic Scale** - New spokes/VMs automatically get configuration

---

### Deployment Workflow for 100+ Spokes

**Step 1:** Deploy Hub with Azure Firewall + Explicit Proxy enabled  
**Step 2:** Configure firewall policy with application rules  
**Step 3:** Create PAC file and host on firewall (port 8090)  
**Step 4:** Create Azure Policy for Guest Configuration  
**Step 5:** Assign policy at subscription/management group level  
**Step 6:** Deploy spokes - VMs automatically configured by policy  

**Result:** Zero manual configuration per VM, automatic compliance, continuous monitoring.

---

### Compliance & Monitoring

**Track PAC enforcement** across your estate:

```powershell
# Check policy compliance across all VMs
Get-AzPolicyState -Filter "PolicyDefinitionName eq 'ConfigureProxySettings'" | 
    Select-Object ResourceId, ComplianceState, Timestamp
```

**Azure Policy Dashboard shows:**
- ✅ Compliant VMs (PAC configured correctly)
- ❌ Non-compliant VMs (automatically remediated)
- 📊 Compliance percentage across entire estate

---

### Summary: Enterprise Deployment Best Practices

| Scenario | Recommended Solution | Scale |
|----------|---------------------|-------|
| **Azure-native VMs** | Azure Policy + Guest Configuration | ✅ Thousands of VMs |
| **Domain-joined VMs** | Group Policy (GPO) | ✅ Thousands of VMs |
| **New VM deployments** | VM Extensions in templates | ✅ Automated at creation |
| **Azure Virtual Desktop** | Golden image or FSLogix | ✅ Thousands of session hosts |
| **Container workloads** | Environment variables or node-level config | ✅ Entire clusters |

**Critical Success Factor:** Use **Azure Policy** as the primary enforcement mechanism for cloud-native deployments. It provides continuous compliance, auto-remediation, and scales effortlessly to thousands of resources.

---
