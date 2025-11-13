# Issue: Check-Lab4-Status.ps1 Explicit Proxy Status Check

**Created:** 2025-11-13  
**Status:** Open  
**Priority:** Low  
**Labels:** bug, enhancement, powershell, azure-firewall

---

## Description

The `Check-Lab4-Status.ps1` script incorrectly reports that explicit proxy is NOT ENABLED, even though it has been successfully enabled via Azure Portal.

## Current Behavior

```powershell
================================
  Azure Firewall Status
================================
✓ Firewall Name: azfw-arc-lab
✓ Provisioning State: Succeeded
ℹ SKU: AZFW_VNet - Premium
ℹ Private IP: 10.100.0.4
✗ Explicit Proxy: NOT ENABLED
```

**Portal confirmation:**
- Explicit proxy enabled with HTTP port 8081, HTTPS port 8443
- Successfully saved with notification: "Successfully saved explicit proxy settings for firewall policy 'azfwpolicy-arc-lab'"
- Screenshot shows "Enable explicit proxy" checkbox is checked

## Root Cause

The Az.Network PowerShell module (v7.23.0) does not expose explicit proxy properties on the `Get-AzFirewall` object. This is a **preview feature** that requires alternative approaches:

1. Newer version of Az.Network module (may not exist yet)
2. Querying the firewall **policy** object instead of firewall object
3. Using Azure Resource Graph or REST API

## Investigation Performed

- ✅ Confirmed `Get-AzFirewall` returns no ExplicitProxy properties
- ✅ Confirmed Az.Network v7.23.0 lacks support for explicit proxy configuration
- ✅ Attempted REST API approach (needs implementation)
- ⚠️ Firewall policy querying not yet tested

## Proposed Solutions

### Option 1: Query Firewall Policy (Recommended)

```powershell
# Get firewall policy instead of firewall
$policy = Get-AzFirewallPolicy -Name "azfwpolicy-arc-lab" -ResourceGroupName $ResourceGroupName

# Check for explicit proxy properties
if ($policy.ExplicitProxy -and $policy.ExplicitProxy.EnableExplicitProxy) {
    Write-Host "✓ Explicit Proxy: ENABLED" -ForegroundColor Green
    Write-Host "  HTTP Port: $($policy.ExplicitProxy.HttpPort)" -ForegroundColor Cyan
    Write-Host "  HTTPS Port: $($policy.ExplicitProxy.HttpsPort)" -ForegroundColor Cyan
} else {
    Write-Host "✗ Explicit Proxy: NOT ENABLED" -ForegroundColor Red
}
```

### Option 2: Use Azure Resource Graph

```powershell
# Query using Resource Graph for policy details
$query = @"
Resources
| where type == 'microsoft.network/firewallpolicies'
| where name == 'azfwpolicy-arc-lab'
| project name, properties
"@

$result = Search-AzGraph -Query $query
# Parse properties for explicit proxy settings
```

### Option 3: REST API Call

```powershell
# Direct REST API call to get full policy properties including preview features
$subscriptionId = (Get-AzContext).Subscription.Id
$policyId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/firewallPolicies/azfwpolicy-arc-lab"

$uri = "https://management.azure.com$($policyId)?api-version=2023-09-01"
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

$response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
$response.properties.explicitProxy
```

## Impact

- **Severity:** Low (cosmetic issue)
- **User Experience:** Confusing - shows incorrect status despite correct configuration
- **Lab Functionality:** Does NOT block lab progress - explicit proxy IS actually working
- **Priority:** Can be addressed later

## Environment

- **Resource Group:** `rg-afep-lab04-arc-<username>` (example)
- **Firewall:** `azfw-arc-lab`
- **Firewall Policy:** `azfwpolicy-arc-lab`
- **Az.Network Version:** 7.23.0
- **Date:** 2025-11-13

## Next Steps

1. Test querying firewall policy object for explicit proxy settings
2. Update `Check-Lab4-Status.ps1` to use policy query instead of firewall object
3. Add version check/warning for Az.Network module capabilities
4. Consider REST API fallback for preview features
5. Test on different Az.Network module versions to identify when support was added

## Related Files

- `scripts/Check-Lab4-Status.ps1` - Script that needs updating
- `scripts/Enable-ExplicitProxy.ps1` - Related enablement script
- `MANUAL-Enable-ExplicitProxy.md` - Manual configuration guide

## Workaround

For now, **ignore the "NOT ENABLED" message** if you:
1. Successfully enabled explicit proxy in Azure Portal
2. Received confirmation notification
3. Can see the checkbox is checked in portal

The explicit proxy **IS working** - this is just a display bug in the status check script.

---

**To address this issue later, run Option 1 test code to verify policy object has the properties.**
