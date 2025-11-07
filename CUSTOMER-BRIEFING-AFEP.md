# Azure Firewall Explicit Proxy - Customer Briefing

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
