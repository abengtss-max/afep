# Azure Firewall Explicit Proxy (AFEP) - Troubleshooting Guide

This guide contains diagnostic commands and solutions for common AFEP issues.

## Table of Contents
- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues](#common-issues)
- [Diagnostic Commands](#diagnostic-commands)
- [Error Codes](#error-codes)

---

## Quick Diagnostics

### 1. Check Firewall Configuration (Run on Local Machine)

```powershell
# Get firewall and policy details
$rg = "RG-AFEP-Lab1"
$fwName = "afw-lab1"
$policyName = "afp-lab1"

$fw = Get-AzFirewall -Name $fwName -ResourceGroupName $rg
$policy = Get-AzFirewallPolicy -Name $policyName -ResourceGroupName $rg

Write-Host "`n=== Firewall Status ===" -ForegroundColor Cyan
Write-Host "Provisioning State: $($fw.ProvisioningState)" -ForegroundColor $(if($fw.ProvisioningState -eq 'Succeeded'){'Green'}else{'Red'})
Write-Host "Tier: $($fw.Sku.Tier)" -ForegroundColor Yellow
Write-Host "Private IP: $($fw.IpConfigurations[0].PrivateIPAddress)" -ForegroundColor Yellow

Write-Host "`n=== Explicit Proxy Settings ===" -ForegroundColor Cyan
Write-Host "Enabled: $($policy.ExplicitProxy.EnableExplicitProxy)" -ForegroundColor $(if($policy.ExplicitProxy.EnableExplicitProxy){'Green'}else{'Red'})
Write-Host "HTTP Port: $($policy.ExplicitProxy.HttpPort)" -ForegroundColor Yellow
Write-Host "HTTPS Port: $($policy.ExplicitProxy.HttpsPort)" -ForegroundColor Yellow
Write-Host "PAC File Enabled: $($policy.ExplicitProxy.EnablePacFile)" -ForegroundColor Yellow
```

### 2. Check Application Rules (Run on Local Machine)

```powershell
# Get and display application rules
$rg = "RG-AFEP-Lab1"
$policyName = "afp-lab1"
$rcgName = "DefaultApplicationRuleCollectionGroup"

$rcg = Get-AzFirewallPolicyRuleCollectionGroup -Name $rcgName -ResourceGroupName $rg -AzureFirewallPolicyName $policyName

Write-Host "`n=== Application Rules ===" -ForegroundColor Cyan
$rcg.Properties.RuleCollection | ForEach-Object {
    Write-Host "`nRule Collection: $($_.Name)" -ForegroundColor Yellow
    Write-Host "  Priority: $($_.Priority)" -ForegroundColor Gray
    Write-Host "  Action: $($_.Action.Type)" -ForegroundColor Gray
    
    $_.Rules | ForEach-Object {
        Write-Host "`n  Rule: $($_.Name)" -ForegroundColor Green
        Write-Host "    Source: $($_.SourceAddresses -join ', ')" -ForegroundColor White
        Write-Host "    Protocols:" -ForegroundColor White
        $_.Protocols | ForEach-Object {
            Write-Host "      - $($_.ProtocolType):$($_.Port)" -ForegroundColor Cyan
        }
        Write-Host "    Target FQDNs: $($_.TargetFqdns -join ', ')" -ForegroundColor White
    }
}
```

### 3. Test Connectivity from VM (Run on Client VM)

```powershell
Write-Host "`n=== Connectivity Tests ===" -ForegroundColor Cyan

# Test firewall reachability
$firewallIP = "10.0.0.4"
$httpPort = 8081
$httpsPort = 8443

Write-Host "`nTesting HTTP Proxy Port ($httpPort)..." -ForegroundColor Yellow
$httpTest = Test-NetConnection -ComputerName $firewallIP -Port $httpPort -WarningAction SilentlyContinue
Write-Host "  Result: $($httpTest.TcpTestSucceeded)" -ForegroundColor $(if($httpTest.TcpTestSucceeded){'Green'}else{'Red'})

Write-Host "`nTesting HTTPS Proxy Port ($httpsPort)..." -ForegroundColor Yellow
$httpsTest = Test-NetConnection -ComputerName $firewallIP -Port $httpsPort -WarningAction SilentlyContinue
Write-Host "  Result: $($httpsTest.TcpTestSucceeded)" -ForegroundColor $(if($httpsTest.TcpTestSucceeded){'Green'}else{'Red'})

# Check current proxy settings
Write-Host "`n=== Current Proxy Configuration ===" -ForegroundColor Cyan
netsh winhttp show proxy

# Check registry proxy settings (for browsers)
Write-Host "`nRegistry Proxy Settings:" -ForegroundColor Yellow
$ieSettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
Write-Host "  ProxyEnable: $($ieSettings.ProxyEnable)" -ForegroundColor White
Write-Host "  ProxyServer: $($ieSettings.ProxyServer)" -ForegroundColor White
```

### 4. Test Proxy Functionality (Run on Client VM)

```powershell
Write-Host "`n=== Proxy Functionality Test ===" -ForegroundColor Cyan

$firewallIP = "10.0.0.4"
$httpPort = 8081

# Test HTTP through proxy
Write-Host "`nTesting HTTP request through proxy..." -ForegroundColor Yellow
try {
    $proxy = New-Object System.Net.WebProxy("http://${firewallIP}:${httpPort}")
    $client = New-Object System.Net.WebClient
    $client.Proxy = $proxy
    $result = $client.DownloadString("http://www.microsoft.com")
    Write-Host "  SUCCESS: HTTP proxy is working!" -ForegroundColor Green
    Write-Host "  Response length: $($result.Length) characters" -ForegroundColor Gray
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -like "*470*") {
        Write-Host "  Cause: Request denied by firewall policy (check application rules)" -ForegroundColor Yellow
    }
}

# Test HTTPS through proxy
Write-Host "`nTesting HTTPS request through proxy..." -ForegroundColor Yellow
try {
    $proxy = New-Object System.Net.WebProxy("http://${firewallIP}:${httpPort}")
    $client = New-Object System.Net.WebClient
    $client.Proxy = $proxy
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $result = $client.DownloadString("https://www.microsoft.com")
    Write-Host "  SUCCESS: HTTPS proxy is working!" -ForegroundColor Green
    Write-Host "  Response length: $($result.Length) characters" -ForegroundColor Gray
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -like "*470*") {
        Write-Host "  Cause: Request denied by firewall policy (check application rules)" -ForegroundColor Yellow
    }
}
```

---

## Common Issues

### Issue 1: Websites Don't Load (ERR_TUNNEL_CONNECTION_FAILED)

**Symptoms:**
- Browser shows "ERR_TUNNEL_CONNECTION_FAILED"
- Can't reach allowed websites

**Causes:**
1. Proxy ports configured incorrectly
2. Application rules too restrictive
3. Wrong IP address configured

**Solution:**

```powershell
# On the VM - Configure both HTTP and HTTPS proxy ports
netsh winhttp set proxy proxy-server="http=10.0.0.4:8081;https=10.0.0.4:8443" bypass-list="<local>"

# Update registry for browsers
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value "http=10.0.0.4:8081;https=10.0.0.4:8443"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 1

# Restart browser
Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue
```

### Issue 2: Error 470 from Proxy

**Symptoms:**
- Connection to proxy works but request fails
- Error message contains "status code 470"

**Cause:** Firewall policy is denying the request

**Solutions:**

```powershell
# Check if application rules are correct (run on local machine)
$rcg = Get-AzFirewallPolicyRuleCollectionGroup -Name "DefaultApplicationRuleCollectionGroup" `
    -ResourceGroupName "RG-AFEP-Lab1" -AzureFirewallPolicyName "afp-lab1"

$collection = $rcg.Properties.RuleCollection | Where-Object { $_.Name -eq "AllowWebTraffic" }
$collection.Rules | ForEach-Object {
    Write-Host "$($_.Name): $($_.TargetFqdns -join ', ')" -ForegroundColor Yellow
}

# Common fix: Update rules to include root domains
$rcg = Get-AzFirewallPolicyRuleCollectionGroup -Name "DefaultApplicationRuleCollectionGroup" `
    -ResourceGroupName "RG-AFEP-Lab1" -AzureFirewallPolicyName "afp-lab1"

$collection = $rcg.Properties.RuleCollection | Where-Object { $_.Name -eq "AllowWebTraffic" }
$microsoftRule = $collection.Rules | Where-Object { $_.Name -eq "AllowMicrosoft" }
$microsoftRule.TargetFqdns = @("*.microsoft.com", "microsoft.com")

$bingRule = $collection.Rules | Where-Object { $_.Name -eq "AllowBing" }
$bingRule.TargetFqdns = @("*.bing.com", "bing.com", "www.bing.com")

Set-AzFirewallPolicyRuleCollectionGroup -Name "DefaultApplicationRuleCollectionGroup" `
    -Priority $rcg.Properties.Priority `
    -RuleCollection $rcg.Properties.RuleCollection `
    -FirewallPolicyObject (Get-AzFirewallPolicy -Name "afp-lab1" -ResourceGroupName "RG-AFEP-Lab1")

Write-Host "Rules updated. Wait 30-60 seconds for changes to apply." -ForegroundColor Green
```

### Issue 3: Port 8080 Blocked

**Symptoms:**
- Azure Portal shows error: "Port number is either beyond allowable limit or standard port"
- Port 8080 cannot be configured

**Cause:** Preview feature limitation - port 8080 is blocked in some Azure regions

**Solution:** Use port 8081 or 8082 instead

```powershell
# Verify current port configuration
$policy = Get-AzFirewallPolicy -Name "afp-lab1" -ResourceGroupName "RG-AFEP-Lab1"
Write-Host "HTTP Port: $($policy.ExplicitProxy.HttpPort)"
Write-Host "HTTPS Port: $($policy.ExplicitProxy.HttpsPort)"

# If you need to change ports, do it in Azure Portal:
# Firewall Policy → Explicit Proxy (Preview) → Update ports
```

### Issue 4: Wildcards Not Matching Root Domains

**Symptoms:**
- `www.microsoft.com` doesn't load
- `*.microsoft.com` rule exists but doesn't work

**Cause:** Wildcard `*.microsoft.com` doesn't match the root domain or `www` subdomain in some cases

**Solution:** Always include both wildcard and root domain

```powershell
# Update rules to include both patterns (run on local machine)
$rcg = Get-AzFirewallPolicyRuleCollectionGroup -Name "DefaultApplicationRuleCollectionGroup" `
    -ResourceGroupName "RG-AFEP-Lab1" -AzureFirewallPolicyName "afp-lab1"

$collection = $rcg.Properties.RuleCollection | Where-Object { $_.Name -eq "AllowWebTraffic" }

# Update each rule to include root domain
$collection.Rules | ForEach-Object {
    $currentFqdns = $_.TargetFqdns
    $newFqdns = @()
    
    foreach ($fqdn in $currentFqdns) {
        $newFqdns += $fqdn
        if ($fqdn.StartsWith("*.")) {
            # Add root domain without wildcard
            $rootDomain = $fqdn.Substring(2)
            if ($newFqdns -notcontains $rootDomain) {
                $newFqdns += $rootDomain
            }
        }
    }
    
    $_.TargetFqdns = $newFqdns
}

Set-AzFirewallPolicyRuleCollectionGroup -Name "DefaultApplicationRuleCollectionGroup" `
    -Priority $rcg.Properties.Priority `
    -RuleCollection $rcg.Properties.RuleCollection `
    -FirewallPolicyObject (Get-AzFirewallPolicy -Name "afp-lab1" -ResourceGroupName "RG-AFEP-Lab1")
```

---

## Diagnostic Commands

### Check VM Network Configuration (Run on VM)

```powershell
# Get VM IP configuration
Get-NetIPAddress | Where-Object {$_.AddressFamily -eq 'IPv4' -and $_.IPAddress -ne '127.0.0.1'} | 
    Select-Object IPAddress, InterfaceAlias, PrefixLength

# Get default gateway
Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Select-Object NextHop, InterfaceAlias

# Test DNS resolution
Resolve-DnsName www.microsoft.com
Resolve-DnsName www.bing.com
```

### Check Firewall Connectivity Details (Run on VM)

```powershell
# Detailed connection test to firewall
$firewallIP = "10.0.0.4"

Write-Host "`n=== Firewall Connectivity Details ===" -ForegroundColor Cyan

# Test HTTP proxy port
$httpResult = Test-NetConnection -ComputerName $firewallIP -Port 8081 -InformationLevel Detailed
Write-Host "`nHTTP Proxy Port (8081):" -ForegroundColor Yellow
Write-Host "  TCP Test: $($httpResult.TcpTestSucceeded)" -ForegroundColor $(if($httpResult.TcpTestSucceeded){'Green'}else{'Red'})
Write-Host "  Source IP: $($httpResult.SourceAddress.IPAddress)" -ForegroundColor Gray
Write-Host "  Ping Success: $($httpResult.PingSucceeded)" -ForegroundColor Gray

# Test HTTPS proxy port
$httpsResult = Test-NetConnection -ComputerName $firewallIP -Port 8443 -InformationLevel Detailed
Write-Host "`nHTTPS Proxy Port (8443):" -ForegroundColor Yellow
Write-Host "  TCP Test: $($httpsResult.TcpTestSucceeded)" -ForegroundColor $(if($httpsResult.TcpTestSucceeded){'Green'}else{'Red'})
Write-Host "  Source IP: $($httpsResult.SourceAddress.IPAddress)" -ForegroundColor Gray
Write-Host "  Ping Success: $($httpsResult.PingSucceeded)" -ForegroundColor Gray
```

### Verify All Components (Complete Check)

```powershell
# Complete system check script - Run on VM
Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "   AFEP Complete System Check" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# 1. Network connectivity
Write-Host "`n[1/5] Network Connectivity..." -ForegroundColor Yellow
$vmIP = (Get-NetIPAddress | Where-Object {$_.AddressFamily -eq 'IPv4' -and $_.IPAddress -ne '127.0.0.1'}).IPAddress
Write-Host "  VM IP: $vmIP" -ForegroundColor White

# 2. Firewall reachability
Write-Host "`n[2/5] Firewall Reachability..." -ForegroundColor Yellow
$fwIP = "10.0.0.4"
$ping = Test-Connection -ComputerName $fwIP -Count 2 -Quiet
Write-Host "  Ping to firewall: $ping" -ForegroundColor $(if($ping){'Green'}else{'Red'})

# 3. Proxy ports
Write-Host "`n[3/5] Proxy Port Accessibility..." -ForegroundColor Yellow
$http = Test-NetConnection -ComputerName $fwIP -Port 8081 -WarningAction SilentlyContinue
$https = Test-NetConnection -ComputerName $fwIP -Port 8443 -WarningAction SilentlyContinue
Write-Host "  HTTP (8081): $($http.TcpTestSucceeded)" -ForegroundColor $(if($http.TcpTestSucceeded){'Green'}else{'Red'})
Write-Host "  HTTPS (8443): $($https.TcpTestSucceeded)" -ForegroundColor $(if($https.TcpTestSucceeded){'Green'}else{'Red'})

# 4. Proxy configuration
Write-Host "`n[4/5] Proxy Configuration..." -ForegroundColor Yellow
$proxySettings = netsh winhttp show proxy
if ($proxySettings -match "10.0.0.4") {
    Write-Host "  WinHTTP proxy: Configured" -ForegroundColor Green
    Write-Host "  $($proxySettings | Select-String -Pattern 'Proxy Server')" -ForegroundColor Gray
} else {
    Write-Host "  WinHTTP proxy: NOT configured" -ForegroundColor Red
}

# 5. Proxy functionality
Write-Host "`n[5/5] Proxy Functionality..." -ForegroundColor Yellow
try {
    $proxy = New-Object System.Net.WebProxy("http://${fwIP}:8081")
    $client = New-Object System.Net.WebClient
    $client.Proxy = $proxy
    $client.DownloadString("http://www.microsoft.com") | Out-Null
    Write-Host "  HTTP test: SUCCESS" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*470*") {
        Write-Host "  HTTP test: FAILED (Error 470 - Policy deny)" -ForegroundColor Yellow
    } else {
        Write-Host "  HTTP test: FAILED ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "   Check Complete" -ForegroundColor Cyan
Write-Host "===============================================`n" -ForegroundColor Cyan
```

---

## Error Codes

### Azure Firewall Explicit Proxy Error Codes

| Error Code | Meaning | Solution |
|------------|---------|----------|
| **470** | Request denied by firewall policy | Check application rules match the FQDN and protocol |
| **ERR_TUNNEL_CONNECTION_FAILED** | Browser can't connect to proxy | Verify proxy IP and ports are correct |
| **ERR_PROXY_CONNECTION_FAILED** | Proxy server unreachable | Check firewall is running and ports 8081/8443 are accessible |
| **Status code 407** | Proxy authentication required | AFEP doesn't support authentication - check configuration |

### Common HTTP Status Codes

| Status Code | Meaning |
|-------------|---------|
| 200 | Success - Request allowed and completed |
| 403 | Forbidden - Policy explicitly denies |
| 407 | Proxy Authentication Required |
| 502 | Bad Gateway - Proxy can't reach destination |
| 504 | Gateway Timeout - Destination didn't respond |

---

## Advanced Diagnostics

### Enable Diagnostic Logging (Run on Local Machine)

```powershell
# Create Log Analytics workspace (if you don't have one)
$workspace = New-AzOperationalInsightsWorkspace `
    -Location "Sweden Central" `
    -Name "law-afep-logs" `
    -ResourceGroupName "RG-AFEP-Lab1" `
    -Sku "PerGB2018"

# Enable firewall diagnostics
$fw = Get-AzFirewall -Name "afw-lab1" -ResourceGroupName "RG-AFEP-Lab1"

Set-AzDiagnosticSetting `
    -Name "afep-diagnostics" `
    -ResourceId $fw.Id `
    -WorkspaceId $workspace.ResourceId `
    -Enabled $true `
    -Category AzureFirewallApplicationRule,AzureFirewallNetworkRule,AzureFirewallDnsProxy

Write-Host "Diagnostic logging enabled. Wait 5-10 minutes for logs to appear." -ForegroundColor Green
```

### Query Firewall Logs (Run on Local Machine)

```powershell
# Query application rule logs
$query = @"
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s
| order by TimeGenerated desc
| take 50
"@

$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName "RG-AFEP-Lab1" -Name "law-afep-logs"
$results = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $query

$results.Results | Format-Table
```

---

## Quick Reference Commands

### On Local Machine (Managing Azure Resources)

```powershell
# Check firewall status
Get-AzFirewall -Name "afw-lab1" -ResourceGroupName "RG-AFEP-Lab1" | Select-Object Name, ProvisioningState

# Check explicit proxy settings
$policy = Get-AzFirewallPolicy -Name "afp-lab1" -ResourceGroupName "RG-AFEP-Lab1"
$policy.ExplicitProxy

# View application rules
$rcg = Get-AzFirewallPolicyRuleCollectionGroup -Name "DefaultApplicationRuleCollectionGroup" `
    -ResourceGroupName "RG-AFEP-Lab1" -AzureFirewallPolicyName "afp-lab1"
$rcg.Properties.RuleCollection.Rules | Select-Object Name, TargetFqdns
```

### On Client VM (Testing Connectivity)

```powershell
# Test firewall connectivity
Test-NetConnection -ComputerName 10.0.0.4 -Port 8081
Test-NetConnection -ComputerName 10.0.0.4 -Port 8443

# Check proxy settings
netsh winhttp show proxy

# Set correct proxy (protocol-specific format)
netsh winhttp set proxy proxy-server="http=10.0.0.4:8081;https=10.0.0.4:8443" bypass-list="<local>"

# Test proxy functionality (will use appropriate port based on URL scheme)
# HTTP test - uses port 8081
Invoke-WebRequest -Uri "http://www.microsoft.com" -UseBasicParsing | Select-Object StatusCode

# HTTPS test - uses port 8443 automatically
Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing | Select-Object StatusCode
```

**Note**: When proxy is configured with protocol-specific format (`http=IP:8081;https=IP:8443`), PowerShell automatically uses the correct port based on the URL scheme (http:// vs https://). You don't need to specify `-Proxy` parameter explicitly.

---

## Tips and Best Practices

1. **Always use both HTTP and HTTPS proxy ports**
   - HTTP: 8081
   - HTTPS: 8443
   - Configure with protocol-specific format: `http=IP:8081;https=IP:8443`

2. **Include root domains in FQDN rules**
   - Use both `*.domain.com` AND `domain.com`
   - Many sites redirect from root to www or regional subdomains

3. **Wait for policy propagation**
   - Firewall policy changes take 30-60 seconds to apply
   - Don't assume immediate failure - give it time

4. **Test with PowerShell first**
   - Use `Invoke-WebRequest` to test before browser
   - PowerShell provides clearer error messages

5. **Check error codes**
   - Error 470 = policy issue (check rules)
   - Connection failed = network/port issue
   - Timeout = firewall not responding

6. **Port restrictions**
   - Don't use port 8080 (blocked in preview in some regions)
   - Use 8081 or 8082 for HTTP
   - Port 8443 works reliably for HTTPS

---

## Getting Help

If you're still experiencing issues after following this guide:

1. Run the complete diagnostic script above
2. Capture the output
3. Check Azure Portal → Firewall → Metrics for request counts
4. Review firewall logs if diagnostic logging is enabled
5. Verify your configuration matches the READMEAUTO.md guide

For AFEP-specific issues, check:
- Azure Firewall documentation: https://docs.microsoft.com/azure/firewall/
- AFEP is in preview - some features may have limitations
