#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.Resources, Az.Network

<#
.SYNOPSIS
    Deploy Lab 4: Azure Arc with Azure Firewall Explicit Proxy over S2S VPN

.DESCRIPTION
    This script deploys the Azure infrastructure for Lab 4, which demonstrates:
    - Azure Firewall with Explicit Proxy for Azure Arc traffic
    - VPN Gateway for Site-to-Site VPN from on-premises
    - Application rules for all required Azure Arc endpoints
    - Optional private endpoints for Arc services
    
    After running this script, follow the on-premises setup guide to:
    1. Configure Hyper-V VMs (OPNsense firewall + Windows Server)
    2. Establish S2S VPN connection
    3. Install and configure Azure Arc agent with proxy settings

.PARAMETER Location
    Azure region for deployment. Default: swedencentral

.PARAMETER AdminPassword
    Password for VPN Gateway shared key (generated if not provided)

.PARAMETER EnablePrivateEndpoints
    Create private endpoints for Arc services (*.his.arc.azure.com, *.guestconfiguration.azure.com)
    Default: $false (not required for basic lab)

.EXAMPLE
    .\Deploy-Lab4-Arc-ExplicitProxy.ps1
    
.EXAMPLE
    .\Deploy-Lab4-Arc-ExplicitProxy.ps1 -Location "westeurope" -EnablePrivateEndpoints $true

.NOTES
    Author: Azure Firewall Expert
    Date: November 2025
    Lab: 4 of 4 - Azure Arc + Explicit Proxy over Private Connectivity
    
    Deployment time: 35-45 minutes (VPN Gateway is slow to provision)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Location = "swedencentral",
    
    [Parameter(Mandatory = $false)]
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory = $false)]
    [bool]$EnablePrivateEndpoints = $false
)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"

$config = @{
    ResourceGroupName    = "rg-afep-lab04-arc-$env:USERNAME"
    VNetName            = "vnet-arc-hub"
    VNetAddressPrefix   = "10.100.0.0/16"
    
    # Subnets
    GatewaySubnetPrefix = "10.100.255.0/24"  # Must be named "GatewaySubnet"
    FirewallSubnetPrefix = "10.100.0.0/26"   # Must be named "AzureFirewallSubnet"
    PrivateEndpointSubnetPrefix = "10.100.1.0/24"
    ManagementSubnetPrefix = "10.100.2.0/24"
    
    # Resources
    VpnGatewayName      = "vpngw-arc-lab"
    VpnGatewayPipName   = "pip-vpngw-arc-lab"
    FirewallName        = "azfw-arc-lab"
    FirewallPipName     = "pip-azfw-arc-lab"
    FirewallPolicyName  = "azfwpolicy-arc-lab"
    
    # Proxy ports
    ProxyHttpPort       = 8081
    ProxyHttpsPort      = 8443
    ProxyPacPort        = 8090
    
    # On-premises simulation (for VPN configuration)
    OnPremAddressSpace  = "10.0.0.0/16"  # Your Hyper-V network
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor Yellow
}

# ==============================================================================
# PREREQUISITES CHECK
# ==============================================================================

Write-Step "Checking Prerequisites"

# Check Azure PowerShell modules
$requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Network')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Error "Required module '$module' is not installed. Run: Install-Module -Name $module"
    }
}
Write-Success "All required PowerShell modules are installed"

# Check Azure login
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged in to Azure. Running Connect-AzAccount..." -ForegroundColor Yellow
        Connect-AzAccount
        $context = Get-AzContext
    }
    Write-Success "Logged in as: $($context.Account.Id)"
    Write-Success "Subscription: $($context.Subscription.Name)"
}
catch {
    Write-Error "Failed to get Azure context. Run Connect-AzAccount first."
}

# Generate VPN shared key if not provided
if (-not $AdminPassword) {
    $AdminPassword = ConvertTo-SecureString -String (New-Guid).Guid -AsPlainText -Force
    Write-Info "Generated random VPN shared key"
}

# ==============================================================================
# STEP 1: CREATE RESOURCE GROUP
# ==============================================================================

Write-Step "Creating Resource Group"

$rg = Get-AzResourceGroup -Name $config.ResourceGroupName -ErrorAction SilentlyContinue
if ($rg) {
    Write-Info "Resource group already exists: $($config.ResourceGroupName)"
} else {
    $rg = New-AzResourceGroup -Name $config.ResourceGroupName -Location $Location
    Write-Success "Created resource group: $($config.ResourceGroupName)"
}

# ==============================================================================
# STEP 2: CREATE VIRTUAL NETWORK WITH SUBNETS
# ==============================================================================

Write-Step "Creating Virtual Network and Subnets"

# Create subnet configurations
$gatewaySubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "GatewaySubnet" `
    -AddressPrefix $config.GatewaySubnetPrefix

$firewallSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "AzureFirewallSubnet" `
    -AddressPrefix $config.FirewallSubnetPrefix

$privateEndpointSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "PrivateEndpointSubnet" `
    -AddressPrefix $config.PrivateEndpointSubnetPrefix `
    -PrivateEndpointNetworkPolicies Disabled

$managementSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "ManagementSubnet" `
    -AddressPrefix $config.ManagementSubnetPrefix

# Create VNet
$vnet = Get-AzVirtualNetwork -Name $config.VNetName -ResourceGroupName $config.ResourceGroupName -ErrorAction SilentlyContinue
if ($vnet) {
    Write-Info "VNet already exists: $($config.VNetName)"
} else {
    $vnet = New-AzVirtualNetwork `
        -Name $config.VNetName `
        -ResourceGroupName $config.ResourceGroupName `
        -Location $Location `
        -AddressPrefix $config.VNetAddressPrefix `
        -Subnet $gatewaySubnet, $firewallSubnet, $privateEndpointSubnet, $managementSubnet
    
    Write-Success "Created VNet: $($config.VNetName) ($($config.VNetAddressPrefix))"
    Write-Success "  - GatewaySubnet: $($config.GatewaySubnetPrefix)"
    Write-Success "  - AzureFirewallSubnet: $($config.FirewallSubnetPrefix)"
    Write-Success "  - PrivateEndpointSubnet: $($config.PrivateEndpointSubnetPrefix)"
    Write-Success "  - ManagementSubnet: $($config.ManagementSubnetPrefix)"
}

# ==============================================================================
# STEP 3: CREATE VPN GATEWAY (TAKES 30-40 MINUTES)
# ==============================================================================

Write-Step "Creating VPN Gateway (this will take 30-40 minutes)"
Write-Info "☕ Perfect time for a coffee break! You can start preparing Hyper-V setup in parallel."

# Create public IP for VPN Gateway
$vpnPip = Get-AzPublicIpAddress -Name $config.VpnGatewayPipName -ResourceGroupName $config.ResourceGroupName -ErrorAction SilentlyContinue
if (-not $vpnPip) {
    $vpnPip = New-AzPublicIpAddress `
        -Name $config.VpnGatewayPipName `
        -ResourceGroupName $config.ResourceGroupName `
        -Location $Location `
        -AllocationMethod Static `
        -Sku Standard
    
    Write-Success "Created VPN Gateway Public IP: $($vpnPip.IpAddress)"
}

# Get gateway subnet
$vnet = Get-AzVirtualNetwork -Name $config.VNetName -ResourceGroupName $config.ResourceGroupName
$gatewaySubnet = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet

# Create VPN Gateway IP configuration
$vpnGwIpConfig = New-AzVirtualNetworkGatewayIpConfig `
    -Name "vpnGwIpConfig" `
    -SubnetId $gatewaySubnet.Id `
    -PublicIpAddressId $vpnPip.Id

# Create VPN Gateway
$vpnGw = Get-AzVirtualNetworkGateway -Name $config.VpnGatewayName -ResourceGroupName $config.ResourceGroupName -ErrorAction SilentlyContinue
if ($vpnGw) {
    Write-Info "VPN Gateway already exists: $($config.VpnGatewayName)"
} else {
    Write-Host "  Creating VPN Gateway... (started at $(Get-Date -Format 'HH:mm:ss'))" -ForegroundColor Yellow
    
    $vpnGw = New-AzVirtualNetworkGateway `
        -Name $config.VpnGatewayName `
        -ResourceGroupName $config.ResourceGroupName `
        -Location $Location `
        -GatewayType Vpn `
        -VpnType RouteBased `
        -GatewaySku VpnGw1 `
        -IpConfigurations $vpnGwIpConfig `
        -EnableBgp $false
    
    Write-Success "VPN Gateway created: $($config.VpnGatewayName) (completed at $(Get-Date -Format 'HH:mm:ss'))"
}

# ==============================================================================
# STEP 4: CREATE AZURE FIREWALL WITH EXPLICIT PROXY
# ==============================================================================

Write-Step "Creating Azure Firewall with Explicit Proxy"

# Create public IP for firewall
$fwPip = Get-AzPublicIpAddress -Name $config.FirewallPipName -ResourceGroupName $config.ResourceGroupName -ErrorAction SilentlyContinue
if (-not $fwPip) {
    $fwPip = New-AzPublicIpAddress `
        -Name $config.FirewallPipName `
        -ResourceGroupName $config.ResourceGroupName `
        -Location $Location `
        -AllocationMethod Static `
        -Sku Standard
    
    Write-Success "Created Firewall Public IP: $($fwPip.IpAddress)"
}

# Create Firewall Policy with Explicit Proxy
$fwPolicy = Get-AzFirewallPolicy -Name $config.FirewallPolicyName -ResourceGroupName $config.ResourceGroupName -ErrorAction SilentlyContinue
if (-not $fwPolicy) {
    # Create explicit proxy settings
    $explicitProxy = New-AzFirewallPolicyExplicitProxy `
        -EnableExplicitProxy `
        -HttpPort $config.ProxyHttpPort `
        -HttpsPort $config.ProxyHttpsPort
    
    $fwPolicy = New-AzFirewallPolicy `
        -Name $config.FirewallPolicyName `
        -ResourceGroupName $config.ResourceGroupName `
        -Location $Location `
        -SkuTier Premium `
        -ExplicitProxy $explicitProxy `
        -ThreatIntelMode Alert
    
    Write-Success "Created Firewall Policy with Explicit Proxy enabled"
    Write-Success "  - HTTP Port: $($config.ProxyHttpPort)"
    Write-Success "  - HTTPS Port: $($config.ProxyHttpsPort)"
    Write-Success "  - PAC Port: $($config.ProxyPacPort) (not used for Arc)"
}

# Create Azure Firewall
$firewall = Get-AzFirewall -Name $config.FirewallName -ResourceGroupName $config.ResourceGroupName -ErrorAction SilentlyContinue
if ($firewall) {
    Write-Info "Azure Firewall already exists: $($config.FirewallName)"
} else {
    $firewallSubnet = Get-AzVirtualNetworkSubnetConfig -Name "AzureFirewallSubnet" -VirtualNetwork $vnet
    
    $firewall = New-AzFirewall `
        -Name $config.FirewallName `
        -ResourceGroupName $config.ResourceGroupName `
        -Location $Location `
        -VirtualNetwork $vnet `
        -PublicIpAddress $fwPip `
        -FirewallPolicyId $fwPolicy.Id `
        -SkuName AZFW_VNet `
        -SkuTier Premium
    
    Write-Success "Created Azure Firewall: $($config.FirewallName)"
    Write-Success "  - Private IP: $($firewall.IpConfigurations[0].PrivateIPAddress)"
    Write-Success "  - SKU: Premium (TLS inspection capable)"
}

# Refresh firewall object to get private IP
$firewall = Get-AzFirewall -Name $config.FirewallName -ResourceGroupName $config.ResourceGroupName
$firewallPrivateIp = $firewall.IpConfigurations[0].PrivateIPAddress

# ==============================================================================
# STEP 5: CREATE FIREWALL APPLICATION RULES FOR AZURE ARC
# ==============================================================================

Write-Step "Creating Application Rules for Azure Arc Endpoints"

# Rule Collection 1: Arc Core - Always Required (Priority 100)
$arcCoreRules = @(
    New-AzFirewallPolicyApplicationRule -Name "Entra-ID-Login" `
        -SourceAddress "*" `
        -TargetFqdn "login.microsoftonline.com", "*.login.microsoft.com", "login.windows.net", "pas.windows.net" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Azure-Resource-Manager" `
        -SourceAddress "*" `
        -TargetFqdn "management.azure.com" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Arc-Hybrid-Identity-Service" `
        -SourceAddress "*" `
        -TargetFqdn "*.his.arc.azure.com" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Arc-Guest-Configuration" `
        -SourceAddress "*" `
        -TargetFqdn "*.guestconfiguration.azure.com" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Arc-Notification-Service" `
        -SourceAddress "*" `
        -TargetFqdn "guestnotificationservice.azure.com", "*.guestnotificationservice.azure.com" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Arc-Service-Bus" `
        -SourceAddress "*" `
        -TargetFqdn "*.servicebus.windows.net", "azgn*.servicebus.windows.net" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Arc-Blob-Storage" `
        -SourceAddress "*" `
        -TargetFqdn "*.blob.core.windows.net" `
        -Protocol "https:443"
)

$arcCoreRuleCollection = New-AzFirewallPolicyFilterRuleCollection `
    -Name "Arc-Core-Always-Required" `
    -Priority 100 `
    -Rule $arcCoreRules `
    -ActionType Allow

# Rule Collection 2: Arc Installation & Updates (Priority 200)
$arcInstallRules = @(
    New-AzFirewallPolicyApplicationRule -Name "Windows-Agent-Download" `
        -SourceAddress "*" `
        -TargetFqdn "download.microsoft.com" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Linux-Agent-Download" `
        -SourceAddress "*" `
        -TargetFqdn "packages.microsoft.com" `
        -Protocol "https:443"
)

$arcInstallRuleCollection = New-AzFirewallPolicyFilterRuleCollection `
    -Name "Arc-Installation-Downloads" `
    -Priority 200 `
    -Rule $arcInstallRules `
    -ActionType Allow

# Rule Collection 3: Arc Optional Features (Priority 300)
$arcOptionalRules = @(
    New-AzFirewallPolicyApplicationRule -Name "Windows-Admin-Center" `
        -SourceAddress "*" `
        -TargetFqdn "*.waconazure.com" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Agent-Telemetry" `
        -SourceAddress "*" `
        -TargetFqdn "dc.services.visualstudio.com" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "ESU-Certificates" `
        -SourceAddress "*" `
        -TargetFqdn "www.microsoft.com" `
        -Protocol "http:80", "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "License-Validation" `
        -SourceAddress "*" `
        -TargetFqdn "dls.microsoft.com" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Arc-SQL-Server-Regional" `
        -SourceAddress "*" `
        -TargetFqdn "*.$($Location.ToLower()).arcdataservices.com" `
        -Protocol "https:443"
    
    New-AzFirewallPolicyApplicationRule -Name "Key-Vault-Graph" `
        -SourceAddress "*" `
        -TargetFqdn "*.vault.azure.net", "graph.microsoft.com" `
        -Protocol "https:443"
)

$arcOptionalRuleCollection = New-AzFirewallPolicyFilterRuleCollection `
    -Name "Arc-Optional-Features" `
    -Priority 300 `
    -Rule $arcOptionalRules `
    -ActionType Allow

# Create or get Rule Collection Group
try {
    $ruleCollectionGroup = Get-AzFirewallPolicyRuleCollectionGroup `
        -Name "DefaultApplicationRuleCollectionGroup" `
        -ResourceGroupName $config.ResourceGroupName `
        -AzureFirewallPolicyName $config.FirewallPolicyName `
        -ErrorAction SilentlyContinue

    if (-not $ruleCollectionGroup) {
        Write-Info "Creating rule collection group with Arc rules..."
        
        # Create new rule collection group with all three collections
        $ruleCollectionGroup = New-AzFirewallPolicyRuleCollectionGroup `
            -Name "DefaultApplicationRuleCollectionGroup" `
            -Priority 200 `
            -ResourceGroupName $config.ResourceGroupName `
            -AzureFirewallPolicyName $config.FirewallPolicyName `
            -RuleCollection $arcCoreRuleCollection, $arcInstallRuleCollection, $arcOptionalRuleCollection
        
        Write-Success "Created 3 Application Rule Collections:"
        Write-Success "  - Arc-Core-Always-Required (10 rules)"
        Write-Success "  - Arc-Installation-Downloads (2 rules)"
        Write-Success "  - Arc-Optional-Features (6 rules)"
    } else {
        Write-Info "Rule collection group already exists, adding Arc rules..."
        
        # Get existing collections
        $existingCollections = $ruleCollectionGroup.Properties.RuleCollection
        
        # Add new collections if they don't exist
        $collectionNames = $existingCollections | ForEach-Object { $_.Name }
        
        if ("Arc-Core-Always-Required" -notin $collectionNames) {
            $existingCollections += $arcCoreRuleCollection
        }
        if ("Arc-Installation-Downloads" -notin $collectionNames) {
            $existingCollections += $arcInstallRuleCollection
        }
        if ("Arc-Optional-Features" -notin $collectionNames) {
            $existingCollections += $arcOptionalRuleCollection
        }
        
        # Update the group
        Set-AzFirewallPolicyRuleCollectionGroup `
            -Name "DefaultApplicationRuleCollectionGroup" `
            -ResourceGroupName $config.ResourceGroupName `
            -AzureFirewallPolicyName $config.FirewallPolicyName `
            -Priority 200 `
            -RuleCollection $existingCollections | Out-Null
        
        Write-Success "Updated rule collections with Arc rules"
    }
} catch {
    Write-Warning "Failed to create rule collections automatically: $($_.Exception.Message)"
    Write-Info ""
    Write-Info "⚠️  You'll need to create these rules manually in Azure Portal:"
    Write-Info "   1. Navigate to Firewall Policy: $($config.FirewallPolicyName)"
    Write-Info "   2. Go to 'Application Rules' under Settings"
    Write-Info "   3. Create rule collections based on GUIDE-Arc-Agent-Proxy-Config.md"
    Write-Info ""
    Write-Info "   Continuing with deployment..."
}

# ==============================================================================
# STEP 6: CREATE LOCAL NETWORK GATEWAY (FOR ON-PREMISES)
# ==============================================================================

Write-Step "Creating Local Network Gateway (represents your on-premises network)"

$localGwName = "lng-onprem-lab"
$localGw = Get-AzLocalNetworkGateway -Name $localGwName -ResourceGroupName $config.ResourceGroupName -ErrorAction SilentlyContinue

if (-not $localGw) {
    # This will be updated later with your actual OPNsense public IP
    $localGw = New-AzLocalNetworkGateway `
        -Name $localGwName `
        -ResourceGroupName $config.ResourceGroupName `
        -Location $Location `
        -GatewayIpAddress "1.1.1.1" `
        -AddressPrefix $config.OnPremAddressSpace
    
    Write-Success "Created Local Network Gateway: $localGwName"
    Write-Info "⚠️  You'll need to update the GatewayIpAddress with your actual public IP later"
    Write-Info "   Run: Set-AzLocalNetworkGateway -Name $localGwName -ResourceGroupName $($config.ResourceGroupName) -GatewayIpAddress <your-public-ip>"
}

# ==============================================================================
# STEP 7: EXPORT DEPLOYMENT INFORMATION
# ==============================================================================

Write-Step "Exporting Deployment Information"

$vpnGw = Get-AzVirtualNetworkGateway -Name $config.VpnGatewayName -ResourceGroupName $config.ResourceGroupName
$vpnPip = Get-AzPublicIpAddress -Name $config.VpnGatewayPipName -ResourceGroupName $config.ResourceGroupName
$firewall = Get-AzFirewall -Name $config.FirewallName -ResourceGroupName $config.ResourceGroupName

# Convert SecureString to plain text for export (only for lab purposes)
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword)
$plainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

$deploymentInfo = @{
    ResourceGroup = $config.ResourceGroupName
    Location = $Location
    DeployedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    
    VNet = @{
        Name = $vnet.Name
        AddressSpace = $config.VNetAddressPrefix
        GatewaySubnet = $config.GatewaySubnetPrefix
        FirewallSubnet = $config.FirewallSubnetPrefix
    }
    
    VPNGateway = @{
        Name = $vpnGw.Name
        PublicIP = $vpnPip.IpAddress
        SharedKey = $plainTextPassword
        GatewayType = "VPN-RouteBased"
        SKU = "VpnGw1"
        Instructions = "Use this Public IP and Shared Key to configure S2S VPN on your OPNsense firewall"
    }
    
    AzureFirewall = @{
        Name = $firewall.Name
        PrivateIP = $firewallPrivateIp
        PublicIP = $fwPip.IpAddress
        SKU = "Premium"
        ExplicitProxy = @{
            Enabled = $true
            HttpPort = $config.ProxyHttpPort
            HttpsPort = $config.ProxyHttpsPort
            PacPort = $config.ProxyPacPort
        }
    }
    
    ArcConfiguration = @{
        ProxyUrl = "http://$($firewallPrivateIp):$($config.ProxyHttpPort)"
        ProxyBypass = "localhost,127.0.0.1"
        AgentConfigCommand = "azcmagent config set proxy.url `"http://$($firewallPrivateIp):$($config.ProxyHttpPort)`""
        AgentConnectCommand = @"
azcmagent connect \
  --resource-group "$($config.ResourceGroupName)" \
  --tenant-id "<your-tenant-id>" \
  --location "$Location" \
  --subscription-id "<your-subscription-id>" \
  --proxy-url "http://$($firewallPrivateIp):$($config.ProxyHttpPort)"
"@
    }
    
    NextSteps = @(
        "1. Follow GUIDE-OnPremises-HyperV-Setup.md to setup Hyper-V VMs"
        "2. Configure OPNsense with VPN Gateway Public IP: $($vpnPip.IpAddress)"
        "3. Update Local Network Gateway with your OPNsense public IP"
        "4. Test VPN connectivity: Test-NetConnection $firewallPrivateIp -Port $($config.ProxyHttpPort)"
        "5. Follow GUIDE-Arc-Agent-Proxy-Config.md to install Arc agent"
        "6. Run validation tests from VALIDATION-Arc-Connectivity.md"
    )
}

$outputFile = "Lab4-Arc-DeploymentInfo.json"
$deploymentInfo | ConvertTo-Json -Depth 10 | Out-File $outputFile
Write-Success "Deployment info saved to: $outputFile"

# ==============================================================================
# DEPLOYMENT SUMMARY
# ==============================================================================

Write-Host "`n" -NoNewline
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  LAB 4 DEPLOYMENT COMPLETE - AZURE ARC + EXPLICIT PROXY       ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "📋 DEPLOYMENT SUMMARY" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""
Write-Host "  Resource Group:  " -NoNewline; Write-Host $config.ResourceGroupName -ForegroundColor Yellow
Write-Host "  Location:        " -NoNewline; Write-Host $Location -ForegroundColor Yellow
Write-Host ""

Write-Host "🌐 VPN GATEWAY (for S2S VPN from your PC)" -ForegroundColor Cyan
Write-Host "  Public IP:       " -NoNewline; Write-Host $vpnPip.IpAddress -ForegroundColor Yellow
Write-Host "  Shared Key:      " -NoNewline; Write-Host $plainTextPassword -ForegroundColor Yellow
Write-Host "  ⚠️  Use these values to configure OPNsense VPN tunnel" -ForegroundColor Magenta
Write-Host ""

Write-Host "🔥 AZURE FIREWALL (Explicit Proxy)" -ForegroundColor Cyan
Write-Host "  Private IP:      " -NoNewline; Write-Host $firewallPrivateIp -ForegroundColor Yellow
Write-Host "  HTTP Proxy:      " -NoNewline; Write-Host "$($firewallPrivateIp):$($config.ProxyHttpPort)" -ForegroundColor Yellow
Write-Host "  HTTPS Proxy:     " -NoNewline; Write-Host "$($firewallPrivateIp):$($config.ProxyHttpsPort)" -ForegroundColor Yellow
Write-Host "  SKU:             " -NoNewline; Write-Host "Premium (TLS Inspection)" -ForegroundColor Yellow
Write-Host ""

Write-Host "🔗 AZURE ARC CONFIGURATION" -ForegroundColor Cyan
Write-Host "  Proxy URL:       " -NoNewline; Write-Host "http://$($firewallPrivateIp):$($config.ProxyHttpPort)" -ForegroundColor Yellow
Write-Host "  Total Rules:     " -NoNewline; Write-Host "18 Application Rules (all Arc endpoints)" -ForegroundColor Yellow
Write-Host ""

Write-Host "📚 NEXT STEPS" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""
Write-Host "  1. Open:  " -NoNewline; Write-Host "GUIDE-OnPremises-HyperV-Setup.md" -ForegroundColor Yellow
Write-Host "     → Setup Hyper-V, OPNsense firewall, Windows Server VM"
Write-Host ""
Write-Host "  2. Configure S2S VPN on OPNsense using:" -ForegroundColor White
Write-Host "     Remote Gateway: " -NoNewline; Write-Host $vpnPip.IpAddress -ForegroundColor Yellow
Write-Host "     Shared Key:     " -NoNewline; Write-Host $plainTextPassword -ForegroundColor Yellow
Write-Host ""
Write-Host "  3. After VPN is connected, test connectivity:" -ForegroundColor White
Write-Host "     Test-NetConnection $firewallPrivateIp -Port $($config.ProxyHttpPort)" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Open:  " -NoNewline; Write-Host "GUIDE-Arc-Agent-Proxy-Config.md" -ForegroundColor Yellow
Write-Host "     → Install and configure Azure Arc agent with proxy"
Write-Host ""
Write-Host "  5. Open:  " -NoNewline; Write-Host "VALIDATION-Arc-Connectivity.md" -ForegroundColor Yellow
Write-Host "     → Validate Arc registration and connectivity"
Write-Host ""

Write-Host "📄 Deployment details saved to: " -NoNewline; Write-Host $outputFile -ForegroundColor Yellow
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""
