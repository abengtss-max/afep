# Lab 4: Azure Arc Connectivity Validation & Testing

## 📋 Overview

This document provides comprehensive validation procedures to verify that your Azure Arc-enabled server is:
- ✅ Communicating through Azure Firewall Explicit Proxy
- ✅ Using the S2S VPN tunnel (no direct internet)
- ✅ Successfully registered with Azure Arc
- ✅ All endpoints reachable via proxy
- ✅ Security validated (internet blocked)

---

## 🧪 Test Suite Overview

We'll run 7 comprehensive tests:

1. **Network Connectivity** - VPN and proxy ports
2. **Proxy Configuration** - Environment variables and agent settings
3. **Azure Arc Agent Status** - Registration and heartbeat
4. **Endpoint Reachability** - All required Azure endpoints
5. **Security Validation** - Confirm internet is blocked
6. **Azure Firewall Logs** - Verify traffic flow
7. **Extension Management** - Test Arc functionality

---

## 📝 Test 1: Network Connectivity

### Test VPN Tunnel

From **ArcServer01**, open PowerShell:

```powershell
Write-Host "`n=== TEST 1: NETWORK CONNECTIVITY ===" -ForegroundColor Cyan

# Test 1.1: Ping pfSense (local gateway)
Write-Host "`n[1.1] Testing pfSense reachability..." -ForegroundColor Yellow
$result = Test-NetConnection -ComputerName 10.0.1.1 -WarningAction SilentlyContinue
if ($result.PingSucceeded) {
    Write-Host "✓ pfSense reachable (10.0.1.1)" -ForegroundColor Green
} else {
    Write-Host "✗ pfSense NOT reachable" -ForegroundColor Red
}

# Test 1.2: Ping Azure Firewall via VPN
Write-Host "`n[1.2] Testing Azure Firewall reachability via VPN..." -ForegroundColor Yellow
$result = Test-NetConnection -ComputerName 10.100.0.4 -WarningAction SilentlyContinue
if ($result.PingSucceeded) {
    Write-Host "✓ Azure Firewall reachable via VPN (10.100.0.4)" -ForegroundColor Green
} else {
    Write-Host "✗ Azure Firewall NOT reachable" -ForegroundColor Red
}

# Test 1.3: Test HTTP proxy port (8081)
Write-Host "`n[1.3] Testing HTTP proxy port..." -ForegroundColor Yellow
$result = Test-NetConnection -ComputerName 10.100.0.4 -Port 8081 -WarningAction SilentlyContinue
if ($result.TcpTestSucceeded) {
    Write-Host "✓ HTTP proxy port 8081 accessible" -ForegroundColor Green
} else {
    Write-Host "✗ HTTP proxy port 8081 NOT accessible" -ForegroundColor Red
}

# Test 1.4: Test HTTPS proxy port (8443)
Write-Host "`n[1.4] Testing HTTPS proxy port..." -ForegroundColor Yellow
$result = Test-NetConnection -ComputerName 10.100.0.4 -Port 8443 -WarningAction SilentlyContinue
if ($result.TcpTestSucceeded) {
    Write-Host "✓ HTTPS proxy port 8443 accessible" -ForegroundColor Green
} else {
    Write-Host "✗ HTTPS proxy port 8443 NOT accessible" -ForegroundColor Red
}

Write-Host "`n✓ Test 1 Complete" -ForegroundColor Green
```

**Expected Results:** All 4 tests should show ✓ (green checkmarks)

---

## 📝 Test 2: Proxy Configuration

### Verify Proxy Settings

```powershell
Write-Host "`n=== TEST 2: PROXY CONFIGURATION ===" -ForegroundColor Cyan

# Test 2.1: Check environment variables
Write-Host "`n[2.1] Checking proxy environment variables..." -ForegroundColor Yellow
$httpProxy = [Environment]::GetEnvironmentVariable("HTTP_PROXY", "Machine")
$httpsProxy = [Environment]::GetEnvironmentVariable("HTTPS_PROXY", "Machine")
$noProxy = [Environment]::GetEnvironmentVariable("NO_PROXY", "Machine")

if ($httpProxy -eq "http://10.100.0.4:8081") {
    Write-Host "✓ HTTP_PROXY correctly set: $httpProxy" -ForegroundColor Green
} else {
    Write-Host "✗ HTTP_PROXY incorrect or missing: $httpProxy" -ForegroundColor Red
}

if ($httpsProxy -eq "http://10.100.0.4:8081") {
    Write-Host "✓ HTTPS_PROXY correctly set: $httpsProxy" -ForegroundColor Green
} else {
    Write-Host "✗ HTTPS_PROXY incorrect or missing: $httpsProxy" -ForegroundColor Red
}

# Test 2.2: Check Arc agent proxy configuration
Write-Host "`n[2.2] Checking Arc agent proxy configuration..." -ForegroundColor Yellow
$agentProxy = & azcmagent config get proxy.url
if ($agentProxy -match "10.100.0.4:8081") {
    Write-Host "✓ Arc agent proxy configured: $agentProxy" -ForegroundColor Green
} else {
    Write-Host "✗ Arc agent proxy NOT configured" -ForegroundColor Red
}

Write-Host "`n✓ Test 2 Complete" -ForegroundColor Green
```

---

## 📝 Test 3: Azure Arc Agent Status

### Check Agent Health

```powershell
Write-Host "`n=== TEST 3: AZURE ARC AGENT STATUS ===" -ForegroundColor Cyan

# Test 3.1: Check if agent is running
Write-Host "`n[3.1] Checking Arc agent service..." -ForegroundColor Yellow
$service = Get-Service -Name "himds" -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq "Running") {
    Write-Host "✓ Azure Hybrid Instance Metadata Service (himds) running" -ForegroundColor Green
} else {
    Write-Host "✗ himds service not running" -ForegroundColor Red
}

# Test 3.2: Check agent status
Write-Host "`n[3.2] Checking Arc agent registration status..." -ForegroundColor Yellow
$agentStatus = & azcmagent show --output json | ConvertFrom-Json

if ($agentStatus.status -eq "Connected") {
    Write-Host "✓ Agent Status: Connected" -ForegroundColor Green
    Write-Host "  Resource Name: $($agentStatus.resourceName)"
    Write-Host "  Resource Group: $($agentStatus.resourceGroup)"
    Write-Host "  Location: $($agentStatus.location)"
    Write-Host "  Last Heartbeat: $($agentStatus.lastHeartbeat)"
} else {
    Write-Host "✗ Agent Status: $($agentStatus.status)" -ForegroundColor Red
}

# Test 3.3: Check guest configuration service
Write-Host "`n[3.3] Checking Guest Configuration service..." -ForegroundColor Yellow
$gcService = Get-Service -Name "GCService" -ErrorAction SilentlyContinue
if ($gcService -and $gcService.Status -eq "Running") {
    Write-Host "✓ Guest Configuration Service running" -ForegroundColor Green
} else {
    Write-Host "⚠  Guest Configuration Service not running (may start later)" -ForegroundColor Yellow
}

Write-Host "`n✓ Test 3 Complete" -ForegroundColor Green
```

---

## 📝 Test 4: Endpoint Reachability

### Test All Required Azure Endpoints

```powershell
Write-Host "`n=== TEST 4: ENDPOINT REACHABILITY ===" -ForegroundColor Cyan
Write-Host "Testing connectivity to all required Azure Arc endpoints via proxy..." -ForegroundColor Yellow
Write-Host "This may take 1-2 minutes...`n" -ForegroundColor Yellow

# Run Arc agent connectivity check
& azcmagent check --location swedencentral

# Parse results
Write-Host "`n✓ Test 4 Complete" -ForegroundColor Green
Write-Host "Review results above. All endpoints should show 'Reachable'" -ForegroundColor Yellow
```

### Manual Endpoint Tests

If you want to test specific endpoints manually:

```powershell
# Test specific endpoints through proxy
$proxyUrl = "http://10.100.0.4:8081"
$endpoints = @(
    "https://management.azure.com",
    "https://login.microsoftonline.com",
    "https://pas.windows.net",
    "https://guestnotificationservice.azure.com",
    "https://download.microsoft.com"
)

foreach ($endpoint in $endpoints) {
    try {
        Write-Host "Testing $endpoint..." -NoNewline
        $response = Invoke-WebRequest -Uri $endpoint -Proxy $proxyUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Write-Host " ✓" -ForegroundColor Green
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -in 200,401,403,404) {
            # These status codes mean connectivity worked (even if auth failed)
            Write-Host " ✓ (HTTP $statusCode)" -ForegroundColor Green
        } else {
            Write-Host " ✗" -ForegroundColor Red
        }
    }
}
```

---

## 📝 Test 5: Security Validation

### Confirm Internet is Blocked

**Critical Test:** Verify that ArcServer01 has NO direct internet access:

```powershell
Write-Host "`n=== TEST 5: SECURITY VALIDATION ===" -ForegroundColor Cyan
Write-Host "Verifying that direct internet access is blocked..." -ForegroundColor Yellow

# Test 5.1: Try to reach public internet (should FAIL)
Write-Host "`n[5.1] Testing direct internet access (should be BLOCKED)..." -ForegroundColor Yellow

$publicSites = @("google.com", "microsoft.com", "azure.com")
$allBlocked = $true

foreach ($site in $publicSites) {
    Write-Host "  Testing $site..." -NoNewline
    try {
        $result = Test-NetConnection -ComputerName $site -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet -ErrorAction Stop
        if ($result) {
            Write-Host " ✗ REACHABLE (SECURITY ISSUE!)" -ForegroundColor Red
            $allBlocked = $false
        }
    } catch {
        Write-Host " ✓ Blocked" -ForegroundColor Green
    }
}

if ($allBlocked) {
    Write-Host "`n✓ SECURITY VALIDATED: Direct internet access is blocked" -ForegroundColor Green
    Write-Host "  All traffic must go through VPN + Azure Firewall" -ForegroundColor Green
} else {
    Write-Host "`n✗ SECURITY WARNING: Direct internet access detected!" -ForegroundColor Red
    Write-Host "  Check Windows Server Router firewall rules" -ForegroundColor Yellow
}

# Test 5.2: Verify proxy still works
Write-Host "`n[5.2] Verifying proxy connectivity still works..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://management.azure.com" -Proxy "http://10.100.0.4:8081" -UseBasicParsing -TimeoutSec 10
    Write-Host "✓ Proxy connectivity verified" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode.value__ -in 401,403) {
        Write-Host "✓ Proxy connectivity verified (auth required, as expected)" -ForegroundColor Green
    } else {
        Write-Host "✗ Proxy connectivity failed" -ForegroundColor Red
    }
}

Write-Host "`n✓ Test 5 Complete" -ForegroundColor Green
```

---

## 📝 Test 6: Azure Firewall Logs

### Verify Traffic in Firewall Logs

From your **host PC**, check Azure Firewall logs:

```powershell
Write-Host "`n=== TEST 6: AZURE FIREWALL LOGS ===" -ForegroundColor Cyan

# Connect to Azure
Connect-AzAccount

# Get firewall
$resourceGroup = "rg-afep-lab04-arc-$env:USERNAME"
$firewallName = "azfw-arc-lab"

Write-Host "`nQuerying Azure Firewall for Arc traffic..." -ForegroundColor Yellow
Write-Host "Looking for traffic from source IP 10.0.1.10 (ArcServer01)..." -ForegroundColor Yellow

# Get firewall policy
$fwPolicy = Get-AzFirewallPolicy -Name "azfwpolicy-arc-lab" -ResourceGroupName $resourceGroup

# Display rule collections
Write-Host "`nConfigured Rule Collections:" -ForegroundColor Cyan
$ruleCollectionGroup = Get-AzFirewallPolicyRuleCollectionGroup -Name "ArcRuleCollectionGroup" -AzureFirewallPolicy $fwPolicy

foreach ($collection in $ruleCollectionGroup.Properties.RuleCollection) {
    Write-Host "  - $($collection.Name) (Priority: $($collection.Priority), Rules: $($collection.Rules.Count))"
}

Write-Host "`n✓ To view detailed logs:" -ForegroundColor Yellow
Write-Host "  1. Go to Azure Portal: portal.azure.com" -ForegroundColor White
Write-Host "  2. Navigate to: Azure Firewall → azfw-arc-lab → Logs" -ForegroundColor White
Write-Host "  3. Run query:" -ForegroundColor White
Write-Host @"
    AzureDiagnostics
    | where Category == "AzureFirewallApplicationRule"
    | where SourceIp == "10.0.1.10"
    | project TimeGenerated, SourceIp, DestinationIp, Fqdn, Action
    | order by TimeGenerated desc
    | take 50
"@ -ForegroundColor Gray

Write-Host "`n✓ Test 6 Complete" -ForegroundColor Green
```

---

## 📝 Test 7: Extension Management

### Test Arc Functionality with Extensions

```powershell
Write-Host "`n=== TEST 7: EXTENSION MANAGEMENT ===" -ForegroundColor Cyan

# Test 7.1: List installed extensions
Write-Host "`n[7.1] Listing installed extensions..." -ForegroundColor Yellow
& azcmagent extension list

# Test 7.2: Install Azure Monitor Agent (if not already installed)
Write-Host "`n[7.2] Testing extension installation..." -ForegroundColor Yellow
Write-Host "Installing Azure Monitor Agent extension from Azure..." -ForegroundColor Yellow
```

From your **host PC**:

```powershell
# Install Azure Monitor Agent extension
$resourceGroup = "rg-afep-lab04-arc-$env:USERNAME"
$machineName = "ArcServer01"
$location = "swedencentral"

# Check if extension already exists
$existingExt = Get-AzConnectedMachineExtension `
    -Name "AzureMonitorWindowsAgent" `
    -ResourceGroupName $resourceGroup `
    -MachineName $machineName `
    -ErrorAction SilentlyContinue

if ($existingExt) {
    Write-Host "✓ Azure Monitor Agent already installed" -ForegroundColor Green
    Write-Host "  Status: $($existingExt.ProvisioningState)" -ForegroundColor Yellow
} else {
    Write-Host "Installing Azure Monitor Agent..." -ForegroundColor Yellow
    
    New-AzConnectedMachineExtension `
        -Name "AzureMonitorWindowsAgent" `
        -ResourceGroupName $resourceGroup `
        -MachineName $machineName `
        -Location $location `
        -Publisher "Microsoft.Azure.Monitor" `
        -ExtensionType "AzureMonitorWindowsAgent" `
        -Settings @{} `
        -AutoUpgradeMinorVersion $true
    
    Write-Host "✓ Extension installation initiated" -ForegroundColor Green
    Write-Host "  Check status in 2-3 minutes" -ForegroundColor Yellow
}

# Wait and check status
Write-Host "`nWaiting 2 minutes for extension to install..." -ForegroundColor Yellow
Start-Sleep -Seconds 120

$ext = Get-AzConnectedMachineExtension `
    -Name "AzureMonitorWindowsAgent" `
    -ResourceGroupName $resourceGroup `
    -MachineName $machineName

Write-Host "`nExtension Status:" -ForegroundColor Cyan
Write-Host "  Name: $($ext.Name)"
Write-Host "  Provisioning State: $($ext.ProvisioningState)"
Write-Host "  Type: $($ext.ExtensionType)"

if ($ext.ProvisioningState -eq "Succeeded") {
    Write-Host "`n✓ Extension installed successfully" -ForegroundColor Green
} else {
    Write-Host "`n⚠  Extension status: $($ext.ProvisioningState)" -ForegroundColor Yellow
}

Write-Host "`n✓ Test 7 Complete" -ForegroundColor Green
```

---

## 📊 Complete Validation Report

### Generate Summary Report

Run this comprehensive script to generate a full validation report:

```powershell
# Save to file
$reportFile = "C:\ArcAgent\ValidationReport-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

$report = @"
====================================================================
AZURE ARC + EXPLICIT PROXY VALIDATION REPORT
====================================================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Server: $env:COMPUTERNAME

--------------------------------------------------------------------
NETWORK CONNECTIVITY
--------------------------------------------------------------------
Windows Server Router (10.0.1.1):    $((Test-NetConnection 10.0.1.1 -WarningAction SilentlyContinue).PingSucceeded)
Azure Firewall (10.100.0.4):         $((Test-NetConnection 10.100.0.4 -WarningAction SilentlyContinue).PingSucceeded)
HTTP Proxy Port (8081):               $((Test-NetConnection 10.100.0.4 -Port 8081 -WarningAction SilentlyContinue).TcpTestSucceeded)
HTTPS Proxy Port (8443):              $((Test-NetConnection 10.100.0.4 -Port 8443 -WarningAction SilentlyContinue).TcpTestSucceeded)

--------------------------------------------------------------------
PROXY CONFIGURATION
--------------------------------------------------------------------
HTTP_PROXY:   $([Environment]::GetEnvironmentVariable("HTTP_PROXY", "Machine"))
HTTPS_PROXY:  $([Environment]::GetEnvironmentVariable("HTTPS_PROXY", "Machine"))
NO_PROXY:     $([Environment]::GetEnvironmentVariable("NO_PROXY", "Machine"))

Arc Agent Proxy: $(& azcmagent config get proxy.url)

--------------------------------------------------------------------
ARC AGENT STATUS
--------------------------------------------------------------------
$((& azcmagent show) -join "`n")

--------------------------------------------------------------------
SECURITY VALIDATION
--------------------------------------------------------------------
Direct Internet Access (google.com):  $(try { (Test-NetConnection google.com -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded } catch { "Blocked" })
Direct Internet Access (microsoft.com): $(try { (Test-NetConnection microsoft.com -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded } catch { "Blocked" })

Status: $(if ((Test-NetConnection google.com -Port 443 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue).TcpTestSucceeded) { "FAILED - Internet accessible!" } else { "PASSED - Internet blocked" })

--------------------------------------------------------------------
INSTALLED EXTENSIONS
--------------------------------------------------------------------
$((& azcmagent extension list) -join "`n")

====================================================================
VALIDATION COMPLETE
====================================================================
"@

$report | Out-File $reportFile
Write-Host "`n✓ Validation report saved to: $reportFile" -ForegroundColor Green

# Display report
Get-Content $reportFile
```

---

## ✅ Expected Results Summary

### All Tests Should Show:

1. **Network Connectivity:** ✓ All 4 tests pass (Windows Server Router, Azure Firewall, ports 8081/8443)
2. **Proxy Configuration:** ✓ Environment variables set, Arc agent configured
3. **Arc Agent Status:** ✓ Status = Connected, heartbeat recent
4. **Endpoint Reachability:** ✓ All required endpoints show "Reachable"
5. **Security Validation:** ✓ Direct internet BLOCKED, proxy works
6. **Firewall Logs:** ✓ Traffic visible from source 10.0.1.10
7. **Extension Management:** ✓ Extensions install successfully

---

## 🎉 Success Criteria

Your lab is **fully validated** if:

- ✅ All 7 tests pass
- ✅ ArcServer01 shows "Connected" in Azure Portal
- ✅ No direct internet access (security validated)
- ✅ All Arc traffic flows through Azure Firewall (visible in logs)
- ✅ Extensions can be installed and managed
- ✅ Arc agent heartbeat is regular (every 5 minutes)

**Congratulations!** You've successfully validated that Azure Arc works with Explicit Proxy over private connectivity! 🚀

---

## 🛠️ Troubleshooting Failed Tests

### Test 1 Failed: Network Connectivity

**Symptoms:** Can't reach Azure Firewall (10.100.0.4)  
**Cause:** VPN tunnel down  
**Solution:**
```powershell
# Check VPN status on Windows Server Router
# Navigate to: Server Manager → RRAS → Network Interfaces
# Status should be: Connected (for Demand Dial Interface)

# If not, reconnect:
# Right-click interface → Connect
```

### Test 2 Failed: Proxy Configuration

**Symptoms:** Proxy variables not set  
**Solution:**
```powershell
# Re-apply proxy settings
[Environment]::SetEnvironmentVariable("HTTP_PROXY", "http://10.100.0.4:8081", "Machine")
[Environment]::SetEnvironmentVariable("HTTPS_PROXY", "http://10.100.0.4:8081", "Machine")
& azcmagent config set proxy.url "http://10.100.0.4:8081"

# Restart PowerShell
```

### Test 3 Failed: Agent Not Connected

**Symptoms:** Agent status shows "Disconnected"  
**Solution:**
```powershell
# Check agent logs
Get-Content "C:\ProgramData\AzureConnectedMachineAgent\Log\himds.log" -Tail 50

# Restart agent service
Restart-Service -Name "himds"

# Wait 1 minute and check status
Start-Sleep 60
& azcmagent show
```

### Test 4 Failed: Endpoints Unreachable

**Symptoms:** `azcmagent check` shows unreachable endpoints  
**Solution:**
```powershell
# On host PC, verify firewall rules
Get-AzFirewallPolicyRuleCollectionGroup `
    -Name "ArcRuleCollectionGroup" `
    -AzureFirewallPolicyName "azfwpolicy-arc-lab" `
    -ResourceGroupName "rg-afep-lab04-arc-$env:USERNAME" `
    | Format-List

# Should show 3 rule collections with 18 rules total
# If missing, re-run deployment script
```

### Test 5 Failed: Internet Not Blocked

**Symptoms:** Can reach google.com directly  
**Solution:**
```powershell
# Check Windows Server Router firewall rules
# Navigate to: Windows Firewall with Advanced Security → Outbound Rules
# Ensure:
#  - "Block Internet Outbound" rule exists and is enabled
#  - "Allow Azure VPN" and "Allow Local Network" rules exist
```

### Test 7 Failed: Extension Won't Install

**Symptoms:** Extension stuck in "Creating" or "Failed" state  
**Solution:**
```powershell
# Check proxy is working
Invoke-WebRequest -Uri "https://guestconfiguration.blob.core.windows.net" -Proxy "http://10.100.0.4:8081" -UseBasicParsing

# If fails, verify blob storage rule in firewall:
# Azure Portal → Firewall Policy → Application Rules
# Should include: *.blob.core.windows.net
```

---

**Document Version:** 1.0  
**Last Updated:** November 10, 2025  
**Related Guides:** GUIDE-Arc-Agent-Proxy-Config.md, GUIDE-OnPremises-HyperV-Setup.md
