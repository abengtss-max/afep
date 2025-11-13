#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Network

<#
.SYNOPSIS
    Enable Explicit Proxy on Azure Firewall for Lab 4

.DESCRIPTION
    This script enables and configures Explicit Proxy on an existing Azure Firewall.
    This is required for Azure Arc agent to use the firewall as an HTTP/HTTPS proxy.

.PARAMETER ResourceGroupName
    Name of the resource group containing the Azure Firewall

.PARAMETER FirewallName
    Name of the Azure Firewall. Default: azfw-arc-lab

.PARAMETER HttpPort
    HTTP proxy port. Default: 8081

.PARAMETER HttpsPort
    HTTPS proxy port. Default: 8443

.PARAMETER PacPort
    PAC file port. Default: 8090

.EXAMPLE
    .\Enable-ExplicitProxy.ps1 -ResourceGroupName "rg-afep-lab04-arc-alibengtsson"

.NOTES
    This operation will cause a brief disruption to firewall traffic (~5-10 minutes)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$FirewallName = "azfw-arc-lab",
    
    [Parameter(Mandatory = $false)]
    [int]$HttpPort = 8081,
    
    [Parameter(Mandatory = $false)]
    [int]$HttpsPort = 8443,
    
    [Parameter(Mandatory = $false)]
    [int]$PacPort = 8090
)

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

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Enable Explicit Proxy on Azure Firewall      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check Azure login
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

Write-Host ""

# Get the firewall
Write-Status "Retrieving Azure Firewall: $FirewallName" "Info"
try {
    $firewall = Get-AzFirewall -Name $FirewallName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    Write-Status "Firewall found: $($firewall.Name)" "Success"
    Write-Status "Current State: $($firewall.ProvisioningState)" "Info"
    Write-Status "SKU: $($firewall.Sku.Tier)" "Info"
} catch {
    Write-Status "Firewall not found: $FirewallName in $ResourceGroupName" "Error"
    exit 1
}

Write-Host ""

# Check current proxy configuration
if ($firewall.ExplicitProxy) {
    Write-Status "Explicit Proxy is already enabled:" "Warning"
    Write-Host "  HTTP Port:  $($firewall.ExplicitProxy.HttpPort)" -ForegroundColor Gray
    Write-Host "  HTTPS Port: $($firewall.ExplicitProxy.HttpsPort)" -ForegroundColor Gray
    Write-Host "  PAC Port:   $($firewall.ExplicitProxy.PacFilePort)" -ForegroundColor Gray
    Write-Host ""
    
    $response = Read-Host "Do you want to update the configuration? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Status "Operation cancelled" "Info"
        exit 0
    }
} else {
    Write-Status "Explicit Proxy is NOT currently enabled" "Warning"
    Write-Status "This will enable proxy with:" "Info"
    Write-Host "  HTTP Port:  $HttpPort" -ForegroundColor Gray
    Write-Host "  HTTPS Port: $HttpsPort" -ForegroundColor Gray
    Write-Host "  PAC Port:   $PacPort" -ForegroundColor Gray
}

Write-Host ""
Write-Status "⚠ WARNING: This operation will update the firewall (takes ~5-10 minutes)" "Warning"
Write-Status "⚠ There may be brief traffic disruption during the update" "Warning"
Write-Host ""

$confirm = Read-Host "Proceed with enabling Explicit Proxy? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Status "Operation cancelled" "Info"
    exit 0
}

Write-Host ""
Write-Status "Configuring Explicit Proxy..." "Info"

try {
    # Update firewall with explicit proxy using direct property assignment
    Write-Status "Updating firewall configuration (this will take several minutes)..." "Info"
    
    # Set explicit proxy properties directly
    $firewall.EnableExplicitProxy = $true
    $firewall.HttpPort = $HttpPort
    $firewall.HttpsPort = $HttpsPort
    $firewall.EnablePacFile = $true
    $firewall.PacFilePort = $PacPort
    
    Write-Status "Applying changes to Azure Firewall..." "Info"
    $result = Set-AzFirewall -AzureFirewall $firewall
    
    Write-Host ""
    Write-Status "✅ Explicit Proxy enabled successfully!" "Success"
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor Cyan
    Write-Host "  Firewall Private IP: $($result.IpConfigurations[0].PrivateIPAddress)" -ForegroundColor Gray
    Write-Host "  HTTP Proxy:  http://$($result.IpConfigurations[0].PrivateIPAddress):$HttpPort" -ForegroundColor Gray
    Write-Host "  HTTPS Proxy: https://$($result.IpConfigurations[0].PrivateIPAddress):$HttpsPort" -ForegroundColor Gray
    Write-Host "  PAC File URL: http://$($result.IpConfigurations[0].PrivateIPAddress):$PacPort/proxy.pac" -ForegroundColor Gray
    
    Write-Host ""
    Write-Status "Next Steps:" "Info"
    Write-Host "  1. Verify proxy ports are accessible: Test-NetConnection $($result.IpConfigurations[0].PrivateIPAddress) -Port $HttpPort" -ForegroundColor Gray
    Write-Host "  2. Configure Arc agent: azcmagent config set proxy.url 'http://$($result.IpConfigurations[0].PrivateIPAddress):$HttpPort'" -ForegroundColor Gray
    Write-Host "  3. Test Arc connectivity: azcmagent check" -ForegroundColor Gray
    
    # Update deployment info file if it exists
    $deploymentInfoPath = Join-Path $PSScriptRoot "Lab4-Arc-DeploymentInfo.json"
    if (Test-Path $deploymentInfoPath) {
        try {
            $deploymentInfo = Get-Content $deploymentInfoPath -Raw | ConvertFrom-Json
            
            # Add ProxyConfig if it doesn't exist
            if (-not $deploymentInfo.ProxyConfig) {
                $deploymentInfo | Add-Member -MemberType NoteProperty -Name "ProxyConfig" -Value @{
                    HttpPort = $HttpPort
                    HttpsPort = $HttpsPort
                    PacPort = $PacPort
                    HttpUrl = "http://$($result.IpConfigurations[0].PrivateIPAddress):$HttpPort"
                    HttpsUrl = "https://$($result.IpConfigurations[0].PrivateIPAddress):$HttpsPort"
                    PacUrl = "http://$($result.IpConfigurations[0].PrivateIPAddress):$PacPort/proxy.pac"
                }
            } else {
                $deploymentInfo.ProxyConfig.HttpPort = $HttpPort
                $deploymentInfo.ProxyConfig.HttpsPort = $HttpsPort
                $deploymentInfo.ProxyConfig.PacPort = $PacPort
                $deploymentInfo.ProxyConfig.HttpUrl = "http://$($result.IpConfigurations[0].PrivateIPAddress):$HttpPort"
                $deploymentInfo.ProxyConfig.HttpsUrl = "https://$($result.IpConfigurations[0].PrivateIPAddress):$HttpsPort"
                $deploymentInfo.ProxyConfig.PacUrl = "http://$($result.IpConfigurations[0].PrivateIPAddress):$PacPort/proxy.pac"
            }
            
            $deploymentInfo | ConvertTo-Json -Depth 10 | Set-Content $deploymentInfoPath
            Write-Status "Updated deployment info file with proxy configuration" "Success"
        } catch {
            Write-Status "Could not update deployment info file: $($_.Exception.Message)" "Warning"
        }
    }
    
} catch {
    Write-Host ""
    Write-Status "Failed to enable Explicit Proxy" "Error"
    Write-Status "Error: $($_.Exception.Message)" "Error"
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  • Ensure firewall SKU is Premium (Basic/Standard don't support Explicit Proxy)" -ForegroundColor Gray
    Write-Host "  • Check if firewall is in a failed state: Get-AzFirewall -Name $FirewallName -ResourceGroupName $ResourceGroupName" -ForegroundColor Gray
    Write-Host "  • Try again in a few minutes if firewall is updating" -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Status "Operation complete" "Success"
