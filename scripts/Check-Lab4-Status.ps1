#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Network

<#
.SYNOPSIS
    Check the status of Lab 4 Azure deployment

.DESCRIPTION
    This script checks the current status of all Lab 4 resources in Azure:
    - Resource Group
    - Virtual Network
    - VPN Gateway (and connection status)
    - Azure Firewall
    - Firewall Policy and Rules
    - Local Network Gateway
    - Deployment configuration

.PARAMETER ResourceGroupName
    Name of the resource group. Default: auto-detected from Lab4-Arc-DeploymentInfo.json

.EXAMPLE
    .\Check-Lab4-Status.ps1
    
.EXAMPLE
    .\Check-Lab4-Status.ps1 -ResourceGroupName "rg-afep-lab04-arc-myname"

.NOTES
    Author: Azure Firewall Expert
    Date: November 2025
    Lab: 4 - Status Check Script
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName
)

# Helper function for colored output
function Write-Status {
    param(
        [string]$Message,
        [string]$Status = "Info"
    )
    
    $color = switch ($Status) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Info" { "Cyan" }
        default { "White" }
    }
    
    $icon = switch ($Status) {
        "Success" { "✓" }
        "Warning" { "⚠" }
        "Error" { "✗" }
        "Info" { "ℹ" }
        default { "•" }
    }
    
    Write-Host "$icon $Message" -ForegroundColor $color
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
}

# Check Azure login
Write-Section "Azure Connection"
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Status "Not logged into Azure. Please run: Connect-AzAccount" "Error"
        exit 1
    }
    Write-Status "Logged in as: $($context.Account.Id)" "Success"
    Write-Status "Subscription: $($context.Subscription.Name)" "Info"
} catch {
    Write-Status "Azure PowerShell modules not loaded" "Error"
    exit 1
}

# Load deployment info if ResourceGroupName not provided
if (-not $ResourceGroupName) {
    $deploymentInfoPath = Join-Path $PSScriptRoot "Lab4-Arc-DeploymentInfo.json"
    if (Test-Path $deploymentInfoPath) {
        $deploymentInfo = Get-Content $deploymentInfoPath -Raw | ConvertFrom-Json
        $ResourceGroupName = $deploymentInfo.ResourceGroupName
        Write-Status "Using resource group from deployment file: $ResourceGroupName" "Info"
    } else {
        Write-Status "No deployment info file found. Please specify -ResourceGroupName" "Error"
        Write-Host "`nUsage: .\Check-Lab4-Status.ps1 -ResourceGroupName 'rg-name'" -ForegroundColor Yellow
        exit 1
    }
}

# Check Resource Group
Write-Section "Resource Group Status"
try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
    Write-Status "Resource Group: $($rg.ResourceGroupName)" "Success"
    Write-Status "Location: $($rg.Location)" "Info"
    Write-Status "Provisioning State: $($rg.ProvisioningState)" "Success"
    
    # Count resources
    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
    Write-Status "Total Resources: $($resources.Count)" "Info"
} catch {
    Write-Status "Resource Group not found: $ResourceGroupName" "Error"
    Write-Status "The deployment may not have completed or was deleted" "Warning"
    exit 1
}

# Check Virtual Network
Write-Section "Virtual Network Status"
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    Write-Status "VNet Name: $($vnet.Name)" "Success"
    Write-Status "Address Space: $($vnet.AddressSpace.AddressPrefixes -join ', ')" "Info"
    Write-Status "Subnets: $($vnet.Subnets.Count)" "Info"
    
    foreach ($subnet in $vnet.Subnets) {
        Write-Host "  - $($subnet.Name): $($subnet.AddressPrefix)" -ForegroundColor Gray
    }
} catch {
    Write-Status "Virtual Network not found" "Error"
}

# Check VPN Gateway
Write-Section "VPN Gateway Status"
try {
    $vpnGw = Get-AzVirtualNetworkGateway -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Where-Object { $_.GatewayType -eq "Vpn" }
    
    if ($vpnGw) {
        Write-Status "VPN Gateway: $($vpnGw.Name)" "Success"
        Write-Status "Provisioning State: $($vpnGw.ProvisioningState)" $(if ($vpnGw.ProvisioningState -eq "Succeeded") { "Success" } else { "Warning" })
        Write-Status "SKU: $($vpnGw.Sku.Name)" "Info"
        Write-Status "VPN Type: $($vpnGw.VpnType)" "Info"
        
        # Get public IP
        if ($vpnGw.IpConfigurations[0].PublicIpAddress.Id) {
            $pipResourceId = $vpnGw.IpConfigurations[0].PublicIpAddress.Id
            $pipName = $pipResourceId.Split('/')[-1]
            $pip = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $pipName
            Write-Status "Public IP: $($pip.IpAddress)" "Info"
        }
        
        # Check connections
        $connections = Get-AzVirtualNetworkGatewayConnection -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if ($connections) {
            Write-Host "`n  VPN Connections:" -ForegroundColor Cyan
            foreach ($conn in $connections) {
                $status = if ($conn.ConnectionStatus -eq "Connected") { "Success" } else { "Warning" }
                Write-Status "  $($conn.Name): $($conn.ConnectionStatus)" $status
                Write-Host "    Connection Type: $($conn.ConnectionType)" -ForegroundColor Gray
                Write-Host "    Provisioning State: $($conn.ProvisioningState)" -ForegroundColor Gray
                
                if ($conn.ConnectionStatus -ne "Connected") {
                    Write-Status "  Connection not established. Check on-premises VPN configuration." "Warning"
                }
            }
        } else {
            Write-Status "No VPN connections configured yet" "Warning"
        }
    } else {
        Write-Status "VPN Gateway not found" "Error"
    }
} catch {
    Write-Status "Error checking VPN Gateway: $($_.Exception.Message)" "Error"
}

# Check Local Network Gateway
Write-Section "Local Network Gateway"
try {
    $lng = Get-AzLocalNetworkGateway -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    Write-Status "Local Network Gateway: $($lng.Name)" "Success"
    Write-Status "On-Premises Public IP: $($lng.GatewayIpAddress)" "Info"
    Write-Status "On-Premises Network: $($lng.LocalNetworkAddressSpace.AddressPrefixes -join ', ')" "Info"
    
    if ($lng.GatewayIpAddress -eq "1.1.1.1") {
        Write-Status "WARNING: Using placeholder IP (1.1.1.1). Update with actual public IP!" "Warning"
    }
} catch {
    Write-Status "Local Network Gateway not found" "Warning"
}

# Check Azure Firewall
Write-Section "Azure Firewall Status"
try {
    $firewall = Get-AzFirewall -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    Write-Status "Firewall Name: $($firewall.Name)" "Success"
    Write-Status "Provisioning State: $($firewall.ProvisioningState)" $(if ($firewall.ProvisioningState -eq "Succeeded") { "Success" } else { "Warning" })
    Write-Status "SKU: $($firewall.Sku.Name) - $($firewall.Sku.Tier)" "Info"
    Write-Status "Private IP: $($firewall.IpConfigurations[0].PrivateIPAddress)" "Info"
    
    # Check explicit proxy configuration
    if ($firewall.ExplicitProxy) {
        Write-Status "Explicit Proxy: ENABLED" "Success"
        Write-Host "  HTTP Port: $($firewall.ExplicitProxy.HttpPort)" -ForegroundColor Gray
        Write-Host "  HTTPS Port: $($firewall.ExplicitProxy.HttpsPort)" -ForegroundColor Gray
        Write-Host "  PAC Port: $($firewall.ExplicitProxy.PacFilePort)" -ForegroundColor Gray
    } else {
        Write-Status "Explicit Proxy: NOT ENABLED" "Error"
    }
} catch {
    Write-Status "Azure Firewall not found" "Error"
}

# Check Firewall Policy
Write-Section "Firewall Policy & Rules"
try {
    $fwPolicies = Get-AzFirewallPolicy -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    $fwPolicy = $fwPolicies | Select-Object -First 1
    Write-Status "Firewall Policy: $($fwPolicy.Name)" "Success"
    Write-Status "Threat Intel Mode: $($fwPolicy.ThreatIntelMode)" "Info"
    
    # Get rule collection groups
    $ruleGroups = Get-AzFirewallPolicyRuleCollectionGroup -ResourceGroupName $ResourceGroupName -AzureFirewallPolicyName $fwPolicy.Name -ErrorAction SilentlyContinue
    
    if ($ruleGroups) {
        Write-Host "`n  Rule Collection Groups:" -ForegroundColor Cyan
        foreach ($group in $ruleGroups) {
            Write-Status "  $($group.Name) (Priority: $($group.Priority))" "Info"
            
            foreach ($collection in $group.Properties.RuleCollections) {
                Write-Host "    - $($collection.Name): $($collection.Rules.Count) rules" -ForegroundColor Gray
            }
        }
    } else {
        Write-Status "No rule collection groups found" "Warning"
    }
} catch {
    Write-Status "Error checking Firewall Policy: $($_.Exception.Message)" "Warning"
}

# Check Deployment File
Write-Section "Deployment Information"
$deploymentInfoPath = Join-Path $PSScriptRoot "Lab4-Arc-DeploymentInfo.json"
if (Test-Path $deploymentInfoPath) {
    Write-Status "Deployment file found: Lab4-Arc-DeploymentInfo.json" "Success"
    
    $info = Get-Content $deploymentInfoPath -Raw | ConvertFrom-Json
    Write-Host "`n  Configuration:" -ForegroundColor Cyan
    Write-Host "  VPN Gateway Public IP: $($info.VPNGateway.PublicIP)" -ForegroundColor Gray
    Write-Host "  VPN Shared Key: $($info.VPNGateway.SharedKey)" -ForegroundColor Gray
    Write-Host "  Azure Firewall IP: $($info.AzureFirewall.PrivateIP)" -ForegroundColor Gray
    Write-Host "  HTTP Proxy Port: $($info.ProxyConfig.HttpPort)" -ForegroundColor Gray
    Write-Host "  HTTPS Proxy Port: $($info.ProxyConfig.HttpsPort)" -ForegroundColor Gray
} else {
    Write-Status "Deployment info file not found" "Warning"
    Write-Host "  Expected location: $deploymentInfoPath" -ForegroundColor Gray
}

# Summary
Write-Section "Summary"

$allGood = $true

# Check critical components
if ($rg.ProvisioningState -ne "Succeeded") {
    Write-Status "Resource Group not fully provisioned" "Error"
    $allGood = $false
}

if (-not $vpnGw -or $vpnGw.ProvisioningState -ne "Succeeded") {
    Write-Status "VPN Gateway not ready (this takes 30-45 minutes)" "Warning"
    $allGood = $false
}

if (-not $firewall -or $firewall.ProvisioningState -ne "Succeeded") {
    Write-Status "Azure Firewall not ready" "Error"
    $allGood = $false
}

if ($firewall -and -not $firewall.ExplicitProxy) {
    Write-Status "Explicit Proxy not configured on firewall" "Error"
    $allGood = $false
}

if ($connections) {
    $connected = $connections | Where-Object { $_.ConnectionStatus -eq "Connected" }
    if (-not $connected) {
        Write-Status "VPN connection not established (configure on-premises OPNsense)" "Warning"
    }
}

Write-Host ""
if ($allGood) {
    Write-Status "✅ All Azure resources deployed successfully!" "Success"
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Configure on-premises OPNsense firewall (see GUIDE-OnPremises-HyperV-Setup.md)" -ForegroundColor Gray
    Write-Host "  2. Establish Site-to-Site VPN connection" -ForegroundColor Gray
    Write-Host "  3. Install Azure Arc agent with proxy settings (see GUIDE-Arc-Agent-Proxy-Config.md)" -ForegroundColor Gray
} else {
    Write-Status "Some resources are not fully deployed or configured" "Warning"
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Cyan
    Write-Host "  • VPN Gateway takes 30-45 minutes to provision - check back later" -ForegroundColor Gray
    Write-Host "  • Run: Get-AzResourceGroupDeployment -ResourceGroupName '$ResourceGroupName' | Select-Object DeploymentName, ProvisioningState" -ForegroundColor Gray
    Write-Host "  • Check Azure Portal for detailed deployment status" -ForegroundColor Gray
}

Write-Host ""
Write-Status "Status check complete" "Info"
