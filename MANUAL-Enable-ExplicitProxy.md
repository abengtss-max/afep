# Manual Steps to Enable Explicit Proxy on Azure Firewall

## Issue
The current Az.Network PowerShell module (v7.23.0) doesn't support configuring Explicit Proxy programmatically.

## Solution: Configure via Azure Portal

### Steps:

1. **Open Azure Portal**
   - Navigate to: https://portal.azure.com

2. **Go to your Azure Firewall**
   - Resource Group: `rg-afep-lab04-arc-alibengtsson`
   - Firewall: `azfw-arc-lab`

3. **Enable Explicit Proxy**
   - In the left menu, click **"Configuration"** or **"Settings"**
   - Look for **"Explicit Proxy"** section
   - Toggle **"Enable"** to ON
   - Configure ports:
     - HTTP Port: `8081`
     - HTTPS Port: `8443`
     - Enable PAC file: `Yes`
     - PAC Port: `8090`

4. **Save Changes**
   - Click **"Save"**
   - Wait 5-10 minutes for the update to complete

## Alternative: Use Azure CLI (if available in newer version)

```bash
# Update Azure CLI first
az upgrade

# Then try:
az network firewall update \
  --name azfw-arc-lab \
  --resource-group rg-afep-lab04-arc-alibengtsson \
  --set additionalProperties.Network.DNS.EnableProxy=true
```

## Alternative: Use REST API

```powershell
# Get access token
$token = (Get-AzAccessToken).Token

# Firewall resource ID
$fwId = "/subscriptions/b67d7073-183c-499f-aaa9-bbb4986dedf1/resourceGroups/rg-afep-lab04-arc-alibengtsson/providers/Microsoft.Network/azureFirewalls/azfw-arc-lab"

# Get current firewall configuration
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

$fw = Invoke-RestMethod -Uri "https://management.azure.com$($fwId)?api-version=2023-09-01" -Headers $headers -Method Get

# Add explicit proxy configuration
$fw.properties.additionalProperties = @{
    "Network.ExplicitProxy.EnableExplicitProxy" = $true
    "Network.ExplicitProxy.HttpPort" = 8081
    "Network.ExplicitProxy.HttpsPort" = 8443
    "Network.ExplicitProxy.EnablePacFile" = $true
    "Network.ExplicitProxy.PacFilePort" = 8090
}

# Update firewall
$body = $fw | ConvertTo-Json -Depth 10
Invoke-RestMethod -Uri "https://management.azure.com$($fwId)?api-version=2023-09-01" -Headers $headers -Method Put -Body $body
```

## Verification

After enabling, verify with:
```powershell
.\scripts\Check-Lab4-Status.ps1 -ResourceGroupName "rg-afep-lab04-arc-alibengtsson"
```

The output should show:
```
✓ Explicit Proxy: ENABLED
  HTTP Port: 8081
  HTTPS Port: 8443
  PAC Port: 8090
```

## Next Steps After Enabling Proxy

1. Test proxy connectivity from on-premises:
   ```powershell
   Test-NetConnection 10.100.0.4 -Port 8081
   Test-NetConnection 10.100.0.4 -Port 8443
   ```

2. Configure Arc agent to use proxy:
   ```powershell
   azcmagent config set proxy.url "http://10.100.0.4:8081"
   ```

3. Test Arc connectivity:
   ```powershell
   azcmagent check
   ```
