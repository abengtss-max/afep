# Lab 4: Azure Arc Agent Installation with Proxy Configuration

## 📋 Overview

This guide walks you through installing and configuring the **Azure Connected Machine agent** on your Windows Server 2022 VM (ArcServer01) to communicate with Azure through **Azure Firewall Explicit Proxy** over the **S2S VPN tunnel**.

**Time required:** 30-45 minutes

---

## 🎯 What You'll Accomplish

- ✅ Download Arc agent installer (via proxy)
- ✅ Install Azure Connected Machine agent
- ✅ Configure agent to use Azure Firewall Explicit Proxy
- ✅ Register server with Azure Arc
- ✅ Verify connectivity to all required Azure endpoints
- ✅ Confirm NO direct internet access (security validation)

---

## ⚙️ Prerequisites Validation

**⚠️ IMPORTANT:** Do NOT proceed until ALL prerequisites are validated!

### Step 0: Verify Prerequisites

Run these checks on **ArcServer01** before starting Arc agent installation:

```powershell
Write-Host "`n=== PREREQUISITES CHECK ===" -ForegroundColor Cyan

# Check 1: Verify you're on ArcServer01
Write-Host "`n[1/8] Verifying hostname..." -ForegroundColor Yellow
$hostname = $env:COMPUTERNAME
if ($hostname -eq "ArcServer01") {
    Write-Host "✓ Running on ArcServer01" -ForegroundColor Green
} else {
    Write-Host "✗ Expected ArcServer01, but got: $hostname" -ForegroundColor Red
    Write-Host "  Open this guide on ArcServer01 VM" -ForegroundColor Yellow
    exit 1
}

# Check 2: Verify Azure infrastructure deployed
Write-Host "`n[2/8] Checking Azure deployment info..." -ForegroundColor Yellow
$deploymentFile = "\\VBOXSVR\C_DRIVE\Users\$env:USERNAME\MyProjects\azfw\scripts\Lab4-Arc-DeploymentInfo.json"
if (Test-Path $deploymentFile) {
    Write-Host "✓ Deployment info file found" -ForegroundColor Green
    $azureInfo = Get-Content $deploymentFile | ConvertFrom-Json
    Write-Host "  Resource Group: $($azureInfo.ResourceGroup)" -ForegroundColor Gray
} else {
    Write-Host "✗ Lab4-Arc-DeploymentInfo.json NOT found" -ForegroundColor Red
    Write-Host "  Run Deploy-Lab4-Arc-ExplicitProxy.ps1 first" -ForegroundColor Yellow
    Write-Host "  Expected location: C:\Users\<USERNAME>\MyProjects\azfw\scripts\" -ForegroundColor Yellow
    exit 1
}

# Check 3: Verify pfSense reachable (local gateway)
Write-Host "`n[3/8] Testing pfSense connectivity..." -ForegroundColor Yellow
$result = Test-NetConnection -ComputerName 10.0.1.1 -WarningAction SilentlyContinue
if ($result.PingSucceeded) {
    Write-Host "✓ pfSense reachable (10.0.1.1)" -ForegroundColor Green
} else {
    Write-Host "✗ Cannot reach pfSense" -ForegroundColor Red
    Write-Host "  Check: Network adapter settings" -ForegroundColor Yellow
    Write-Host "  Expected: IP 10.0.1.10/24, Gateway 10.0.1.1" -ForegroundColor Yellow
    exit 1
}

# Check 4: Verify Azure Firewall reachable via VPN
Write-Host "`n[4/8] Testing Azure Firewall connectivity via VPN..." -ForegroundColor Yellow
$firewallIP = "10.100.0.4"
$result = Test-NetConnection -ComputerName $firewallIP -WarningAction SilentlyContinue
if ($result.PingSucceeded) {
    Write-Host "✓ Azure Firewall reachable via VPN ($firewallIP)" -ForegroundColor Green
} else {
    Write-Host "✗ Cannot reach Azure Firewall" -ForegroundColor Red
    Write-Host "  Check: S2S VPN status on Windows Server Router" -ForegroundColor Yellow
    Write-Host "  Go to: Server Manager → RRAS → Remote Access Management Console" -ForegroundColor Yellow
    Write-Host "  Status should be: ESTABLISHED (green)" -ForegroundColor Yellow
    exit 1
}

# Check 5: Verify HTTP proxy port accessible
Write-Host "`n[5/8] Testing HTTP proxy port (8081)..." -ForegroundColor Yellow
$result = Test-NetConnection -ComputerName $firewallIP -Port 8081 -WarningAction SilentlyContinue
if ($result.TcpTestSucceeded) {
    Write-Host "✓ HTTP proxy port 8081 accessible" -ForegroundColor Green
} else {
    Write-Host "✗ Port 8081 NOT accessible" -ForegroundColor Red
    Write-Host "  Check: Azure Firewall Explicit Proxy settings" -ForegroundColor Yellow
    Write-Host "  Expected: HttpPort = 8081 in firewall policy" -ForegroundColor Yellow
    exit 1
}

# Check 6: Verify HTTPS proxy port accessible
Write-Host "`n[6/8] Testing HTTPS proxy port (8443)..." -ForegroundColor Yellow
$result = Test-NetConnection -ComputerName $firewallIP -Port 8443 -WarningAction SilentlyContinue
if ($result.TcpTestSucceeded) {
    Write-Host "✓ HTTPS proxy port 8443 accessible" -ForegroundColor Green
} else {
    Write-Host "✗ Port 8443 NOT accessible" -ForegroundColor Red
    Write-Host "  Check: Azure Firewall Explicit Proxy settings" -ForegroundColor Yellow
    exit 1
}

# Check 7: Verify internet is BLOCKED (security validation)
Write-Host "`n[7/8] Verifying internet is blocked (security check)..." -ForegroundColor Yellow
try {
    $result = Test-NetConnection -ComputerName google.com -Port 443 -WarningAction SilentlyContinue -InformationLevel Quiet -ErrorAction Stop
    if ($result) {
        Write-Host "✗ SECURITY ISSUE: Internet is NOT blocked!" -ForegroundColor Red
        Write-Host "  Check: Windows Server Router firewall rules" -ForegroundColor Yellow
        Write-Host "  Required: Delete default 'allow all' rule" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "✓ Internet access blocked (as expected)" -ForegroundColor Green
}

# Check 8: Verify DNS resolution via Azure Firewall
Write-Host "`n[8/8] Testing DNS resolution..." -ForegroundColor Yellow
$dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"}).ServerAddresses
if ($dnsServers -contains "10.100.0.4") {
    Write-Host "✓ DNS configured to use Azure Firewall (10.100.0.4)" -ForegroundColor Green
} else {
    Write-Host "⚠  DNS not set to Azure Firewall" -ForegroundColor Yellow
    Write-Host "  Current DNS: $($dnsServers -join ', ')" -ForegroundColor Gray
    Write-Host "  Will configure in next steps" -ForegroundColor Yellow
}

Write-Host "`n════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✓ ALL PREREQUISITES VALIDATED - READY TO PROCEED" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════`n" -ForegroundColor Green
```

**⚠️ If ANY check fails, STOP and fix the issue before continuing!**

### What to Do If Checks Fail:

**Check 1 Failed (Wrong machine):**
- Open this guide on the Windows Server VM, not your host PC

**Check 2 Failed (No deployment info):**
- Open PowerShell on your **host PC**
- Navigate to: `C:\Users\<USERNAME>\MyProjects\azfw\scripts`
- Run: `.\Deploy-Lab4-Arc-ExplicitProxy.ps1`
- Wait 35-45 minutes for deployment

**Checks 3-6 Failed (Network issues):**
- Open guide: `GUIDE-OnPremises-HyperV-Setup.md`
- Follow **all steps** to setup VPN
- Return here after VPN shows "ESTABLISHED"

**Check 7 Failed (Internet not blocked):**
- RDP to Windows Server Router: 10.0.1.1
- Open: Windows Firewall with Advanced Security
- Go to: Outbound Rules
- Ensure "Block Internet Outbound" rule exists and is enabled
- Keep only: "Allow to Azure via VPN" and "Allow Local Network"

**Check 8 Warning (DNS):**
- This is OK, we'll configure it in Step 8

---

## 📝 Step 1: Get Azure Subscription Information

From ArcServer01, open PowerShell **as Administrator**.

### Method 1: Using Azure Portal (Easiest)

1. Open browser on your **host PC**
2. Go to: https://portal.azure.com
3. Search for "Subscriptions"
4. Note down:
   - **Subscription ID** (GUID format)
   - **Tenant ID** (GUID format - click on subscription → Overview)

### Method 2: Using Azure PowerShell

```powershell
# On your host PC (not ArcServer01)
Connect-AzAccount

# Get subscription details
$context = Get-AzContext
$subscriptionId = $context.Subscription.Id
$tenantId = $context.Tenant.Id

Write-Host "Subscription ID: $subscriptionId" -ForegroundColor Yellow
Write-Host "Tenant ID: $tenantId" -ForegroundColor Yellow

# Resource group from deployment
$resourceGroup = "rg-afep-lab04-arc-$env:USERNAME"
Write-Host "Resource Group: $resourceGroup" -ForegroundColor Yellow
```

**Write these down! You'll need them for Arc registration.**

---

## 📝 Step 2: Set Proxy Environment Variables

On **ArcServer01**, configure Windows to use the Azure Firewall proxy:

```powershell
# Open PowerShell as Administrator

# Set proxy environment variables (pointing to Azure Firewall via VPN)
$firewallIP = "10.100.0.4"
$proxyUrl = "http://$($firewallIP):8081"

[Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyUrl, "Machine")
[Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyUrl, "Machine")
[Environment]::SetEnvironmentVariable("NO_PROXY", "localhost,127.0.0.1", "Machine")

Write-Host "✓ Proxy environment variables set" -ForegroundColor Green
Write-Host "  HTTP_PROXY:  $proxyUrl" -ForegroundColor Yellow
Write-Host "  HTTPS_PROXY: $proxyUrl" -ForegroundColor Yellow

# Restart PowerShell to apply changes
exit
```

**Important:** Open a **new PowerShell window as Administrator** to continue.

### Verify Proxy Settings

```powershell
# Verify environment variables
Get-ChildItem Env:*PROXY

# Should show:
# HTTP_PROXY  = http://10.100.0.4:8081
# HTTPS_PROXY = http://10.100.0.4:8081
# NO_PROXY    = localhost,127.0.0.1
```

---

## 📝 Step 3: Test Proxy Connectivity

Before downloading the Arc agent, verify that Azure endpoints are reachable via proxy:

```powershell
# Test proxy connectivity to Azure endpoints

# Test 1: Azure Resource Manager
$testUrl = "https://management.azure.com"
try {
    $response = Invoke-WebRequest -Uri $testUrl -Proxy "http://10.100.0.4:8081" -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -in 200,401,403) {
        Write-Host "✓ Azure Resource Manager reachable via proxy" -ForegroundColor Green
    }
} catch {
    Write-Host "✗ Failed to reach $testUrl" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Test 2: Azure Arc endpoints
$testUrl = "https://his.arc.azure.com"
try {
    $response = Invoke-WebRequest -Uri $testUrl -Proxy "http://10.100.0.4:8081" -UseBasicParsing -TimeoutSec 10
    Write-Host "✓ Azure Arc endpoint reachable via proxy" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to reach $testUrl" -ForegroundColor Red
}

# Test 3: Microsoft login
$testUrl = "https://login.microsoftonline.com"
try {
    $response = Invoke-WebRequest -Uri $testUrl -Proxy "http://10.100.0.4:8081" -UseBasicParsing -TimeoutSec 10
    Write-Host "✓ Microsoft login reachable via proxy" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to reach $testUrl" -ForegroundColor Red
}
```

**All three tests should succeed (✓). If any fail, check:**
- S2S VPN is still connected
- Azure Firewall application rules are configured correctly
- Proxy environment variables are set

---

## 📝 Step 4: Download Azure Arc Agent

```powershell
# Create download directory
New-Item -ItemType Directory -Path "C:\ArcAgent" -Force
Set-Location C:\ArcAgent

# Download Arc agent installer (via proxy)
Write-Host "Downloading Azure Connected Machine agent..." -ForegroundColor Cyan

$agentUrl = "https://aka.ms/AzureConnectedMachineAgent"
$outputFile = "C:\ArcAgent\AzureConnectedMachineAgent.msi"

Invoke-WebRequest `
    -Uri $agentUrl `
    -OutFile $outputFile `
    -Proxy "http://10.100.0.4:8081" `
    -UseBasicParsing

if (Test-Path $outputFile) {
    $fileSize = (Get-Item $outputFile).Length / 1MB
    Write-Host "✓ Agent downloaded successfully ($([Math]::Round($fileSize, 2)) MB)" -ForegroundColor Green
} else {
    Write-Host "✗ Download failed" -ForegroundColor Red
    exit 1
}
```

---

## 📝 Step 5: Install Azure Arc Agent

```powershell
# Install Arc agent
Write-Host "Installing Azure Connected Machine agent..." -ForegroundColor Cyan

$installArgs = @(
    "/i"
    "C:\ArcAgent\AzureConnectedMachineAgent.msi"
    "/l*v"
    "C:\ArcAgent\install.log"
    "/qn"  # Quiet mode
)

$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru

if ($process.ExitCode -eq 0) {
    Write-Host "✓ Arc agent installed successfully" -ForegroundColor Green
} else {
    Write-Host "✗ Installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
    Write-Host "  Check log: C:\ArcAgent\install.log" -ForegroundColor Yellow
    exit 1
}

# Verify installation
$azcmagent = Get-Command azcmagent -ErrorAction SilentlyContinue
if ($azcmagent) {
    Write-Host "✓ azcmagent.exe found at: $($azcmagent.Source)" -ForegroundColor Green
    
    # Check version
    & azcmagent version
} else {
    Write-Host "✗ azcmagent.exe not found in PATH" -ForegroundColor Red
    Write-Host "  Try closing and reopening PowerShell" -ForegroundColor Yellow
    exit 1
}
```

---

## 📝 Step 6: Configure Arc Agent Proxy Settings

```powershell
# Configure Arc agent to use Azure Firewall proxy
Write-Host "`nConfiguring Arc agent proxy settings..." -ForegroundColor Cyan

# Set proxy URL
& azcmagent config set proxy.url "http://10.100.0.4:8081"

# Set proxy bypass (localhost)
& azcmagent config set proxy.bypass "localhost,127.0.0.1"

# Verify configuration
Write-Host "`n✓ Proxy configuration applied:" -ForegroundColor Green
& azcmagent config list | Select-String "proxy"
```

Expected output:
```
proxy.url     : http://10.100.0.4:8081
proxy.bypass  : localhost,127.0.0.1
```

---

## 📝 Step 7: Test Arc Agent Connectivity

Before registering, test that the agent can reach all required Azure endpoints:

```powershell
# Run Arc agent connectivity check
Write-Host "`nTesting Arc agent connectivity through proxy..." -ForegroundColor Cyan

& azcmagent check

# This will test connectivity to:
# - login.microsoftonline.com
# - management.azure.com
# - *.his.arc.azure.com
# - *.guestconfiguration.azure.com
# - *.servicebus.windows.net
# - *.blob.core.windows.net
# And more...
```

**Expected output:** All endpoints should show **Reachable**

If any endpoint shows **Unreachable**, check:
1. Azure Firewall application rules (see troubleshooting section)
2. S2S VPN is still connected
3. Proxy configuration is correct

---

## 📝 Step 8: Register Server with Azure Arc

Now register the server with Azure Arc:

```powershell
# Set variables (replace with your actual values)
$resourceGroup = "rg-afep-lab04-arc-USERNAME"  # Replace USERNAME
$tenantId = "YOUR-TENANT-ID"  # Replace with your Tenant ID
$subscriptionId = "YOUR-SUBSCRIPTION-ID"  # Replace with your Subscription ID
$location = "swedencentral"  # Or your Azure region
$proxyUrl = "http://10.100.0.4:8081"

# Connect to Azure Arc
Write-Host "`nRegistering server with Azure Arc..." -ForegroundColor Cyan

& azcmagent connect `
    --resource-group $resourceGroup `
    --tenant-id $tenantId `
    --location $location `
    --subscription-id $subscriptionId `
    --proxy-url $proxyUrl `
    --correlation-id ([guid]::NewGuid())

# This will:
# 1. Authenticate via device code flow (you'll need to open browser on host PC)
# 2. Register server with Azure
# 3. Install Azure Connected Machine agent
# 4. Start Azure Hybrid Instance Metadata Service
```

### Authentication Steps

1. **Device Code Prompt:** You'll see a message like:
   ```
   To sign in, use a web browser to open the page https://microsoft.com/devicelogin
   and enter the code XXXXXXXXX to authenticate.
   ```

2. **On Your Host PC:**
   - Open browser
   - Go to: https://microsoft.com/devicelogin
   - Enter the code shown
   - Sign in with Azure account (must have permissions on the subscription)
   - Approve the request

3. **Back on ArcServer01:**
   - Wait for registration to complete (30-60 seconds)
   - You should see: "Connected machine ArcServer01 successfully"

---

## 📝 Step 9: Verify Arc Registration

### Check Agent Status

```powershell
# Show Arc agent status
& azcmagent show

# Should display:
# - Resource Name: ArcServer01
# - Resource Group: rg-afep-lab04-arc-USERNAME
# - Location: swedencentral
# - Agent Status: Connected
# - Last Heartbeat: (recent timestamp)
```

### Check in Azure Portal

1. Open browser on **host PC**
2. Go to: https://portal.azure.com
3. Navigate to: **Azure Arc → Servers**
4. You should see: **ArcServer01** with status **Connected**

### Verify Extension Management

```powershell
# List installed extensions (should be empty initially)
& azcmagent extension list

# Check guest configuration service
Get-Service -Name "GCService" | Format-List

# Status should be: Running
```

---

## 📝 Step 10: Verify Traffic Goes Through Proxy

**Critical validation:** Ensure ALL Arc traffic goes through Azure Firewall (no direct internet).

### Test 1: Check Proxy is Being Used

```powershell
# Verify environment variables are set
$env:HTTP_PROXY
$env:HTTPS_PROXY

# Should return: http://10.100.0.4:8081
```

### Test 2: Verify Direct Internet is Still Blocked

```powershell
# This should FAIL (timeout or error)
Test-NetConnection -ComputerName google.com -Port 443

# This should SUCCEED (via VPN + proxy)
Test-NetConnection -ComputerName 10.100.0.4 -Port 8081
```

### Test 3: Check Azure Firewall Logs

On your **host PC**, check Azure Firewall logs to see Arc traffic:

```powershell
# Connect to Azure
Connect-AzAccount

# Get firewall
$fw = Get-AzFirewall -Name "azfw-arc-lab" -ResourceGroupName "rg-afep-lab04-arc-$env:USERNAME"

# Check application rule logs (last 1 hour)
# This requires Log Analytics workspace configured (optional)
# Or check Azure Portal:
# Azure Firewall → Logs → Firewall Application Rule Log
```

**What to look for:**
- Outbound connections to `*.his.arc.azure.com`
- Connections to `login.microsoftonline.com`
- Connections to `management.azure.com`
- Source IP: `10.0.1.10` (ArcServer01 via VPN)

---

## 📝 Step 11: Install Azure Monitor Agent (Optional)

To fully validate Arc functionality, install the Azure Monitor Agent extension:

```powershell
# From host PC, install Azure Monitor Agent extension
$resourceGroup = "rg-afep-lab04-arc-$env:USERNAME"
$machineName = "ArcServer01"
$location = "swedencentral"

# Create extension
New-AzConnectedMachineExtension `
    -Name "AzureMonitorWindowsAgent" `
    -ResourceGroupName $resourceGroup `
    -MachineName $machineName `
    -Location $location `
    -Publisher "Microsoft.Azure.Monitor" `
    -ExtensionType "AzureMonitorWindowsAgent" `
    -Settings @{} `
    -AutoUpgradeMinorVersion $true

Write-Host "Azure Monitor Agent installation initiated..." -ForegroundColor Cyan
Write-Host "Check status in 2-3 minutes" -ForegroundColor Yellow
```

Wait 2-3 minutes, then check:

```powershell
# On ArcServer01
& azcmagent extension list

# Should show: AzureMonitorWindowsAgent with status "Succeeded"
```

---

## ✅ Verification Checklist

Confirm everything is working:

- [ ] ✅ **Arc agent installed:** `azcmagent version` works
- [ ] ✅ **Proxy configured:** `azcmagent config list` shows proxy.url
- [ ] ✅ **Connectivity check passed:** `azcmagent check` shows all endpoints reachable
- [ ] ✅ **Server registered:** `azcmagent show` displays resource details
- [ ] ✅ **Status connected:** Agent Status = Connected
- [ ] ✅ **Portal shows server:** Azure Arc → Servers shows ArcServer01
- [ ] ✅ **Direct internet blocked:** `Test-NetConnection google.com` fails
- [ ] ✅ **Proxy traffic works:** `Test-NetConnection 10.100.0.4 -Port 8081` succeeds
- [ ] ✅ **Extensions work:** (Optional) Azure Monitor Agent installs successfully

---

## 🎉 Success!

You've successfully:
1. ✅ Installed Azure Arc agent on an on-premises server
2. ✅ Configured it to use Azure Firewall Explicit Proxy
3. ✅ Registered the server over a private S2S VPN connection
4. ✅ Verified NO direct internet access (security validated)
5. ✅ Confirmed all Arc traffic flows through Azure Firewall

This proves the Azure Arc + Explicit Proxy architecture works **exactly as documented by Microsoft**! 🚀

---

## 📚 Next Steps

Run comprehensive validation tests:

➡️ **VALIDATION-Arc-Connectivity.md**

---

## 🛠️ Troubleshooting

### Issue 1: "azcmagent: command not found"

**Cause:** PATH not updated after installation  
**Solution:**
```powershell
# Close and reopen PowerShell as Administrator
# Or manually add to PATH:
$env:Path += ";C:\Program Files\AzureConnectedMachineAgent"
```

### Issue 2: "Failed to connect: Network unreachable"

**Cause:** Proxy not configured or VPN down  
**Solution:**
```powershell
# Check proxy settings
azcmagent config list | Select-String "proxy"

# Test VPN connectivity
Test-NetConnection 10.100.0.4 -Port 8081

# If VPN is down, check Windows Server Router: RRAS Console → Network Interfaces
```

### Issue 3: "Authentication failed"

**Cause:** Wrong tenant/subscription ID  
**Solution:**
```powershell
# Verify IDs on host PC
Connect-AzAccount
Get-AzContext | Select-Object Tenant, Subscription
```

### Issue 4: "azcmagent check shows unreachable endpoints"

**Cause:** Azure Firewall application rules missing  
**Solution:**
```powershell
# On host PC, verify firewall rules
Get-AzFirewallPolicyRuleCollectionGroup `
    -Name "ArcRuleCollectionGroup" `
    -AzureFirewallPolicyName "azfwpolicy-arc-lab" `
    -ResourceGroupName "rg-afep-lab04-arc-$env:USERNAME"

# Should show 3 rule collections with 18 total rules
```

### Issue 5: "Device code authentication times out"

**Cause:** Slow internet or expired code  
**Solution:**
- Retry the azcmagent connect command
- Enter device code faster (90 seconds timeout)
- Use a different browser if issues persist

### Issue 6: "Extension installation fails"

**Cause:** Proxy not working for extension downloads  
**Solution:**
```powershell
# Check blob storage connectivity
Invoke-WebRequest `
    -Uri "https://guestconfiguration.blob.core.windows.net" `
    -Proxy "http://10.100.0.4:8081" `
    -UseBasicParsing

# Should succeed (200 OK or 404, not timeout)
```

---

**Document Version:** 1.0  
**Last Updated:** November 10, 2025  
**Next Guide:** VALIDATION-Arc-Connectivity.md
