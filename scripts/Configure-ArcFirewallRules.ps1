<#
.SYNOPSIS
    Configures Azure Firewall Application Rules for Azure Arc connectivity.

.DESCRIPTION
    This script automatically creates Application Rule Collections in Azure Firewall Policy
    to allow Azure Arc agent connectivity. The rules are based on Microsoft's official
    network requirements documentation.

.PARAMETER ResourceGroupName
    The name of the resource group containing the Azure Firewall Policy.

.PARAMETER FirewallPolicyName
    The name of the Azure Firewall Policy to configure.

.EXAMPLE
    .\Configure-ArcFirewallRules.ps1 -ResourceGroupName "rg-afep-lab04-arc-alibengtsson" -FirewallPolicyName "azfwpolicy-arc-lab"

.NOTES
    Author: Lab 4 - Azure Arc Explicit Proxy
    Date: 2025-11-13
    Version: 1.0
    
    Requirements:
    - Az.Network module
    - Contributor or Network Contributor role on the Firewall Policy

    Reference:
    https://learn.microsoft.com/en-us/azure/azure-arc/servers/network-requirements
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$FirewallPolicyName
)

# Import required modules
Import-Module Az.Network -ErrorAction Stop

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Azure Firewall Application Rules Configuration      ║" -ForegroundColor Cyan
Write-Host "║  Azure Arc Required Endpoints                        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Load deployment info if parameters not provided
if (-not $ResourceGroupName) {
    $deploymentFile = "$PSScriptRoot\Lab4-Arc-DeploymentInfo.json"
    
    if (Test-Path $deploymentFile) {
        Write-Host "Loading deployment information..." -ForegroundColor Yellow
        $azureInfo = Get-Content $deploymentFile | ConvertFrom-Json
        $ResourceGroupName = $azureInfo.ResourceGroup
        Write-Host "✓ Resource Group loaded from deployment file" -ForegroundColor Green
    } else {
        Write-Host "✗ Deployment file not found and ResourceGroupName not provided!" -ForegroundColor Red
        Write-Host "  Please provide -ResourceGroupName" -ForegroundColor Yellow
        exit 1
    }
}

# Auto-detect Firewall Policy if not provided
if (-not $FirewallPolicyName) {
    Write-Host "Auto-detecting Firewall Policy..." -ForegroundColor Yellow
    
    # List all resources in resource group and filter for Firewall Policies
    $policies = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Network/firewallPolicies" -ErrorAction SilentlyContinue
    
    if ($policies.Count -eq 1) {
        $FirewallPolicyName = $policies[0].Name
        Write-Host "✓ Found Firewall Policy: $FirewallPolicyName" -ForegroundColor Green
    } elseif ($policies.Count -gt 1) {
        Write-Host "⚠  Multiple Firewall Policies found. Please specify with -FirewallPolicyName:" -ForegroundColor Yellow
        $policies | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor White }
        exit 1
    } else {
        Write-Host "✗ No Firewall Policy found in resource group!" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "  Firewall Policy: $FirewallPolicyName" -ForegroundColor White

# Check Azure connection
Write-Host "`nChecking Azure connection..." -ForegroundColor Yellow
$context = Get-AzContext
if (-not $context) {
    Write-Host "✗ Not logged in to Azure!" -ForegroundColor Red
    Write-Host "  Run: Connect-AzAccount" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Logged in as: $($context.Account.Id)" -ForegroundColor Green

# Get Firewall Policy
Write-Host "`nRetrieving Firewall Policy..." -ForegroundColor Yellow
try {
    $policy = Get-AzFirewallPolicy -Name $FirewallPolicyName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    Write-Host "✓ Firewall Policy found" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to retrieve Firewall Policy!" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get or create Rule Collection Group
Write-Host "`nChecking Rule Collection Group..." -ForegroundColor Yellow
$ruleCollectionGroupName = "DefaultApplicationRuleCollectionGroup"

try {
    $ruleCollectionGroup = Get-AzFirewallPolicyRuleCollectionGroup -Name $ruleCollectionGroupName -ResourceGroupName $ResourceGroupName -AzureFirewallPolicyName $FirewallPolicyName -ErrorAction SilentlyContinue
    
    if (-not $ruleCollectionGroup) {
        Write-Host "  Creating new Rule Collection Group..." -ForegroundColor Yellow
        $ruleCollectionGroup = New-AzFirewallPolicyRuleCollectionGroup -Name $ruleCollectionGroupName -Priority 100 -FirewallPolicyObject $policy
        Write-Host "✓ Rule Collection Group created" -ForegroundColor Green
    } else {
        Write-Host "✓ Rule Collection Group exists" -ForegroundColor Green
    }
} catch {
    Write-Host "✗ Failed to get/create Rule Collection Group!" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Creating Application Rules for Azure Arc..." -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Define all Arc-required FQDNs based on Microsoft documentation
# https://learn.microsoft.com/en-us/azure/azure-arc/servers/network-requirements

# Rule 1: Microsoft Download and Package Repositories
Write-Host "[1/7] Creating rule: Arc-Agent-Download..." -ForegroundColor Yellow
$rule1 = New-AzFirewallPolicyApplicationRule -Name "Arc-Agent-Download" `
    -SourceAddress "*" `
    -Protocol "Http:80","Https:443" `
    -TargetFqdn @(
        "download.microsoft.com",
        "packages.microsoft.com",
        "*.download.microsoft.com"
    )
Write-Host "    ✓ Rule created" -ForegroundColor Green

# Rule 2: Microsoft Entra ID (Azure Active Directory)
Write-Host "[2/7] Creating rule: Arc-EntraID-Auth..." -ForegroundColor Yellow
$rule2 = New-AzFirewallPolicyApplicationRule -Name "Arc-EntraID-Auth" `
    -SourceAddress "*" `
    -Protocol "Https:443" `
    -TargetFqdn @(
        "login.microsoftonline.com",
        "*.login.microsoft.com",
        "login.windows.net",
        "pas.windows.net"
    )
Write-Host "    ✓ Rule created" -ForegroundColor Green

# Rule 3: Azure Resource Manager
Write-Host "[3/7] Creating rule: Arc-Azure-Management..." -ForegroundColor Yellow
$rule3 = New-AzFirewallPolicyApplicationRule -Name "Arc-Azure-Management" `
    -SourceAddress "*" `
    -Protocol "Https:443" `
    -TargetFqdn @(
        "management.azure.com"
    )
Write-Host "    ✓ Rule created" -ForegroundColor Green

# Rule 4: Azure Arc Core Services
Write-Host "[4/7] Creating rule: Arc-Core-Services..." -ForegroundColor Yellow
$rule4 = New-AzFirewallPolicyApplicationRule -Name "Arc-Core-Services" `
    -SourceAddress "*" `
    -Protocol "Https:443" `
    -TargetFqdn @(
        "*.his.arc.azure.com",
        "*.guestconfiguration.azure.com",
        "guestnotificationservice.azure.com",
        "*.guestnotificationservice.azure.com"
    )
Write-Host "    ✓ Rule created" -ForegroundColor Green

# Rule 5: Azure Service Bus (for notifications and connectivity)
Write-Host "[5/7] Creating rule: Arc-ServiceBus..." -ForegroundColor Yellow
$rule5 = New-AzFirewallPolicyApplicationRule -Name "Arc-ServiceBus" `
    -SourceAddress "*" `
    -Protocol "Https:443" `
    -TargetFqdn @(
        "*.servicebus.windows.net"
    )
Write-Host "    ✓ Rule created" -ForegroundColor Green

# Rule 6: Azure Storage (for extensions)
Write-Host "[6/7] Creating rule: Arc-Storage-Extensions..." -ForegroundColor Yellow
$rule6 = New-AzFirewallPolicyApplicationRule -Name "Arc-Storage-Extensions" `
    -SourceAddress "*" `
    -Protocol "Https:443" `
    -TargetFqdn @(
        "*.blob.core.windows.net"
    )
Write-Host "    ✓ Rule created" -ForegroundColor Green

# Rule 7: Windows Admin Center (optional but included for completeness)
Write-Host "[7/7] Creating rule: Arc-Windows-Admin-Center..." -ForegroundColor Yellow
$rule7 = New-AzFirewallPolicyApplicationRule -Name "Arc-Windows-Admin-Center" `
    -SourceAddress "*" `
    -Protocol "Https:443" `
    -TargetFqdn @(
        "*.waconazure.com"
    )
Write-Host "    ✓ Rule created" -ForegroundColor Green

# Create Application Rule Collection
Write-Host "`nCreating Application Rule Collection..." -ForegroundColor Yellow
$ruleCollectionName = "Arc-Required-Endpoints"

try {
    $appRuleCollection = New-AzFirewallPolicyFilterRuleCollection `
        -Name $ruleCollectionName `
        -Priority 100 `
        -ActionType Allow `
        -Rule $rule1, $rule2, $rule3, $rule4, $rule5, $rule6, $rule7
    
    Write-Host "✓ Rule Collection created" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to create Rule Collection!" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Add Rule Collection to Rule Collection Group
Write-Host "`nAdding Rule Collection to Firewall Policy..." -ForegroundColor Yellow
try {
    # Get current rule collections
    $currentCollections = $ruleCollectionGroup.Properties.RuleCollection
    
    # Check if collection already exists
    $existingCollection = $currentCollections | Where-Object { $_.Name -eq $ruleCollectionName }
    
    if ($existingCollection) {
        Write-Host "⚠  Rule Collection '$ruleCollectionName' already exists!" -ForegroundColor Yellow
        Write-Host "   Updating existing collection..." -ForegroundColor Yellow
        
        # Remove existing collection
        $currentCollections = $currentCollections | Where-Object { $_.Name -ne $ruleCollectionName }
    }
    
    # Add new collection
    $currentCollections += $appRuleCollection
    $ruleCollectionGroup.Properties.RuleCollection = $currentCollections
    
    # Update the Rule Collection Group
    Set-AzFirewallPolicyRuleCollectionGroup -Name $ruleCollectionGroupName `
        -Priority 100 `
        -RuleCollection $currentCollections `
        -FirewallPolicyObject $policy | Out-Null
    
    Write-Host "✓ Rule Collection added to Firewall Policy" -ForegroundColor Green
    
} catch {
    Write-Host "✗ Failed to add Rule Collection to Policy!" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`n  This might be due to Azure PowerShell SDK limitations." -ForegroundColor Yellow
    Write-Host "  Please try configuring via Azure Portal instead." -ForegroundColor Yellow
    exit 1
}

# Summary
Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✓ Application Rules Configured Successfully         ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Green

Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Firewall Policy: $FirewallPolicyName" -ForegroundColor White
Write-Host "  Rule Collection: $ruleCollectionName" -ForegroundColor White
Write-Host "  Priority: 100" -ForegroundColor White
Write-Host "  Action: Allow" -ForegroundColor White
Write-Host "  Total Rules: 7" -ForegroundColor White
Write-Host "`nRules created:" -ForegroundColor Cyan
Write-Host "  1. Arc-Agent-Download (3 FQDNs)" -ForegroundColor White
Write-Host "  2. Arc-EntraID-Auth (4 FQDNs)" -ForegroundColor White
Write-Host "  3. Arc-Azure-Management (1 FQDN)" -ForegroundColor White
Write-Host "  4. Arc-Core-Services (4 FQDNs)" -ForegroundColor White
Write-Host "  5. Arc-ServiceBus (1 FQDN)" -ForegroundColor White
Write-Host "  6. Arc-Storage-Extensions (1 FQDN)" -ForegroundColor White
Write-Host "  7. Arc-Windows-Admin-Center (1 FQDN)" -ForegroundColor White

Write-Host "`n⚠️  IMPORTANT:" -ForegroundColor Yellow
Write-Host "  - Wait 2-3 minutes for rules to propagate" -ForegroundColor White
Write-Host "  - Verify rules in Azure Portal:" -ForegroundColor White
Write-Host "    Firewall Policy → Application Rules → $ruleCollectionName" -ForegroundColor White

Write-Host "`n✓ Configuration complete!" -ForegroundColor Green
Write-Host "  You can now proceed with on-premises Hyper-V setup`n" -ForegroundColor White
