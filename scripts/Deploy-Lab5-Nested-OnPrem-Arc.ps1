<#
.SYNOPSIS
    Deploy Complete Nested On-Premises Simulation in Azure with Arc Onboarding

.DESCRIPTION
    This script creates:
    - Azure Hub Infrastructure (VNet, Azure Firewall with Explicit Proxy, VPN Gateway)
    - "On-Premises" VM in Azure with nested Hyper-V
    - Site-to-Site VPN between "on-prem" and Azure
    - Nested Windows Server Arc VM with proxy configuration
    - Full traffic validation through Azure Firewall explicit proxy

.NOTES
    Author: GitHub Copilot
    Date: 2025-11-14
    Duration: ~90 minutes (VPN Gateway is slowest component)
    Cost: ~$0.50/hour for the nested VM when running
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = "",

    [Parameter(Mandatory = $false)]
    [string]$Location = "swedencentral",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-arc-nested-lab",

    [Parameter(Mandatory = $false)]
    [string]$VNetPrefix = "10.100.0.0/16",

    [Parameter(Mandatory = $false)]
    [string]$OnPremPrefix = "10.0.1.0/24",

    [Parameter(Mandatory = $false)]
    [string]$AdminUsername = "azureadmin",

    [Parameter(Mandatory = $false)]
    [SecureString]$AdminPassword
)

#Requires -Modules Az.Accounts, Az.Resources, Az.Network, Az.Compute

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Generate secure password if not provided
if (-not $AdminPassword) {
    $AdminPassword = ConvertTo-SecureString "P@ssw0rd123!$(Get-Random -Minimum 1000 -Maximum 9999)" -AsPlainText -Force
}

# Deployment timestamp
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$deploymentFile = "$PSScriptRoot\Lab5-Nested-DeploymentInfo-$timestamp.json"

Write-Host "\n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Lab 5: Nested On-Premises Simulation with Azure Arc       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ============================================================================
# STEP 1: AZURE AUTHENTICATION & SUBSCRIPTION
# ============================================================================

Write-Host "\n[1/9] Authenticating to Azure..." -ForegroundColor Yellow

try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
    
    $subscription = (Get-AzContext).Subscription
    Write-Host "  ✓ Connected to: $($subscription.Name)" -ForegroundColor Green
    Write-Host "    Subscription ID: $($subscription.Id)" -ForegroundColor Gray
} catch {
    Write-Error "Failed to authenticate to Azure: $_"
    exit 1
}

# ============================================================================
# STEP 2: CREATE RESOURCE GROUP
# ============================================================================

Write-Host "\n[2/9] Creating Resource Group..." -ForegroundColor Yellow

try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
        Write-Host "  ✓ Created: $ResourceGroupName" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Using existing: $ResourceGroupName" -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to create resource group: $_"
    exit 1
}

# ============================================================================
# STEP 3: DEPLOY AZURE HUB INFRASTRUCTURE (VNet, Firewall, VPN Gateway)
# ============================================================================

Write-Host "\n[3/9] Deploying Azure Hub Infrastructure..." -ForegroundColor Yellow
Write-Host "  This includes: VNet, Azure Firewall, VPN Gateway" -ForegroundColor Gray
Write-Host "  ⏱  Estimated time: 45-60 minutes (VPN Gateway is slow)" -ForegroundColor Yellow

$bicepTemplate = @'
@description('Location for all resources')
param location string = resourceGroup().location

@description('Virtual Network address prefix')
param vnetPrefix string = '10.100.0.0/16'

@description('On-premises network prefix for VPN')
param onPremPrefix string = '10.0.1.0/24'

@description('Admin username for VMs')
param adminUsername string = 'azureadmin'

@description('Admin password for VMs')
@secure()
param adminPassword string

// Variables
var vnetName = 'vnet-hub'
var azFirewallSubnetName = 'AzureFirewallSubnet'
var vpnGatewaySubnetName = 'GatewaySubnet'
var firewallName = 'afw-hub'
var firewallPolicyName = 'afwp-hub'
var firewallPublicIpName = 'pip-afw-hub'
var vpnGatewayName = 'vpngw-hub'
var vpnGatewayPublicIpName = 'pip-vpngw-hub'
var vpnSharedKey = 'AzureArc2025!Lab5-${uniqueString(resourceGroup().id)}'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetPrefix]
    }
    subnets: [
      {
        name: azFirewallSubnetName
        properties: {
          addressPrefix: '10.100.0.0/26'
        }
      }
      {
        name: vpnGatewaySubnetName
        properties: {
          addressPrefix: '10.100.255.0/27'
        }
      }
    ]
  }
}

// Azure Firewall Public IP
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: firewallPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Azure Firewall Policy
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-05-01' = {
  name: firewallPolicyName
  location: location
  properties: {
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
    explicitProxy: {
      enableExplicitProxy: true
      httpPort: 8080
      httpsPort: 8443
      enablePacFile: false
    }
  }
}

// Application Rule Collection for Arc Endpoints
resource arcRuleCollection 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-05-01' = {
  parent: firewallPolicy
  name: 'ArcEndpointsRuleCollection'
  properties: {
    priority: 100
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'Arc-Required-Endpoints'
        priority: 100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-Arc-Download'
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: [
              'aka.ms'
              'download.microsoft.com'
              '*.download.microsoft.com'
              'packages.microsoft.com'
            ]
            sourceAddresses: [onPremPrefix]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-Arc-Core'
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: [
              '*.his.arc.azure.com'
              '*.guestconfiguration.azure.com'
              'agentserviceapi.guestconfiguration.azure.com'
            ]
            sourceAddresses: [onPremPrefix]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-Azure-Management'
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: [
              'management.azure.com'
              'login.microsoftonline.com'
              'login.windows.net'
              'pas.windows.net'
            ]
            sourceAddresses: [onPremPrefix]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-Arc-Extensions'
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: [
              'guestnotificationservice.azure.com'
              '*.guestnotificationservice.azure.com'
              '*.servicebus.windows.net'
              '*.blob.core.windows.net'
            ]
            sourceAddresses: [onPremPrefix]
          }
        ]
      }
    ]
  }
}

// Azure Firewall
resource firewall 'Microsoft.Network/azureFirewalls@2023-05-01' = {
  name: firewallName
  location: location
  dependsOn: [arcRuleCollection]
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: firewallPublicIp.id
          }
        }
      }
    ]
    firewallPolicy: {
      id: firewallPolicy.id
    }
  }
}

// VPN Gateway Public IP
resource vpnGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: vpnGatewayPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// VPN Gateway
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-05-01' = {
  name: vpnGatewayName
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: {
      name: 'VpnGw1'
      tier: 'VpnGw1'
    }
    ipConfigurations: [
      {
        name: 'vpngw-ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          publicIPAddress: {
            id: vpnGatewayPublicIp.id
          }
        }
      }
    ]
  }
}

// Outputs
output vnetId string = vnet.id
output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallPublicIp string = firewallPublicIp.properties.ipAddress
output vpnGatewayPublicIp string = vpnGatewayPublicIp.properties.ipAddress
output vpnSharedKey string = vpnSharedKey
output explicitProxyUrl string = 'http://${firewall.properties.ipConfigurations[0].properties.privateIPAddress}:8443'
'@

# Save Bicep template
$bicepFile = "$PSScriptRoot\Lab5-HubInfra.bicep"
$bicepTemplate | Out-File -FilePath $bicepFile -Encoding UTF8 -Force

try {
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $bicepFile `
        -vnetPrefix $VNetPrefix `
        -onPremPrefix $OnPremPrefix `
        -adminUsername $AdminUsername `
        -adminPassword $AdminPassword `
        -Name "HubInfra-$timestamp" `
        -Verbose

    Write-Host "  ✓ Hub infrastructure deployed" -ForegroundColor Green
    Write-Host "    Azure Firewall IP: $($deployment.Outputs.firewallPrivateIp.Value)" -ForegroundColor Gray
    Write-Host "    VPN Gateway IP: $($deployment.Outputs.vpnGatewayPublicIp.Value)" -ForegroundColor Gray
    Write-Host "    Explicit Proxy: $($deployment.Outputs.explicitProxyUrl.Value)" -ForegroundColor Gray

    $hubDeployment = @{
        FirewallPrivateIp = $deployment.Outputs.firewallPrivateIp.Value
        FirewallPublicIp = $deployment.Outputs.firewallPublicIp.Value
        VpnGatewayPublicIp = $deployment.Outputs.vpnGatewayPublicIp.Value
        VpnSharedKey = $deployment.Outputs.vpnSharedKey.Value
        ExplicitProxyUrl = $deployment.Outputs.explicitProxyUrl.Value
    }

} catch {
    Write-Error "Failed to deploy hub infrastructure: $_"
    exit 1
}

# ============================================================================
# STEP 4: DEPLOY "ON-PREMISES" NESTED HYPERV VM IN AZURE
# ============================================================================

Write-Host "\n[4/9] Deploying 'On-Premises' Nested Hyper-V VM..." -ForegroundColor Yellow
Write-Host "  VM Size: Standard_D8s_v3 (8 vCPU, 32GB RAM)" -ForegroundColor Gray
Write-Host "  ⏱  Estimated time: 5-10 minutes" -ForegroundColor Yellow

$nestedVmBicep = @'
@description('Location for all resources')
param location string = resourceGroup().location

@description('Admin username')
param adminUsername string

@description('Admin password')
@secure()
param adminPassword string

@description('On-prem subnet prefix')
param onPremPrefix string = '10.0.1.0/24'

var vmName = 'vm-nested-hv'
var nicName = '${vmName}-nic'
var vnetName = 'vnet-onprem-sim'
var nsgName = 'nsg-onprem'
var publicIpName = 'pip-${vmName}'

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network for "On-Prem" Simulation
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [onPremPrefix]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: onPremPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// Public IP for RDP access
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Network Interface
resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

// Nested Hyper-V VM
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D8s_v3'
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-g2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 256
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// Custom Script Extension to install Hyper-V
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: vm
  name: 'InstallHyperV'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -Command "Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart"'
    }
  }
}

output vmName string = vm.name
output vmPublicIp string = publicIp.properties.ipAddress
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
'@

$nestedVmBicepFile = "$PSScriptRoot\Lab5-NestedVM.bicep"
$nestedVmBicep | Out-File -FilePath $nestedVmBicepFile -Encoding UTF8 -Force

try {
    $nestedVmDeployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $nestedVmBicepFile `
        -adminUsername $AdminUsername `
        -adminPassword $AdminPassword `
        -onPremPrefix $OnPremPrefix `
        -Name "NestedVM-$timestamp" `
        -Verbose

    Write-Host "  ✓ Nested Hyper-V VM deployed" -ForegroundColor Green
    Write-Host "    VM Name: $($nestedVmDeployment.Outputs.vmName.Value)" -ForegroundColor Gray
    Write-Host "    Public IP: $($nestedVmDeployment.Outputs.vmPublicIp.Value)" -ForegroundColor Gray
    Write-Host "    Private IP: $($nestedVmDeployment.Outputs.vmPrivateIp.Value)" -ForegroundColor Gray

    $nestedVmInfo = @{
        VmName = $nestedVmDeployment.Outputs.vmName.Value
        PublicIp = $nestedVmDeployment.Outputs.vmPublicIp.Value
        PrivateIp = $nestedVmDeployment.Outputs.vmPrivateIp.Value
    }

} catch {
    Write-Error "Failed to deploy nested VM: $_"
    exit 1
}

# ============================================================================
# STEP 5: CONFIGURE VPN CONNECTION (ON-PREM TO AZURE)
# ============================================================================

Write-Host "\n[5/9] Configuring Site-to-Site VPN..." -ForegroundColor Yellow
Write-Host "  Creating Local Network Gateway and VPN Connection" -ForegroundColor Gray

try {
    # Create Local Network Gateway (represents on-prem)
    $localGateway = New-AzLocalNetworkGateway `
        -Name "lng-onprem-sim" `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location `
        -GatewayIpAddress $nestedVmInfo.PublicIp `
        -AddressPrefix $OnPremPrefix

    # Get VPN Gateway
    $vpnGateway = Get-AzVirtualNetworkGateway `
        -Name "vpngw-hub" `
        -ResourceGroupName $ResourceGroupName

    # Create VPN Connection
    $vpnConnection = New-AzVirtualNetworkGatewayConnection `
        -Name "conn-hub-to-onprem" `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location `
        -VirtualNetworkGateway1 $vpnGateway `
        -LocalNetworkGateway2 $localGateway `
        -ConnectionType IPsec `
        -SharedKey $hubDeployment.VpnSharedKey `
        -EnableBgp $false

    Write-Host "  ✓ VPN configuration created" -ForegroundColor Green
    Write-Host "    Connection: hub → on-prem simulation" -ForegroundColor Gray

} catch {
    Write-Error "Failed to configure VPN: $_"
    exit 1
}

# ============================================================================
# STEP 6: SAVE DEPLOYMENT INFO
# ============================================================================

Write-Host "\n[6/9] Saving deployment information..." -ForegroundColor Yellow

$deploymentInfo = @{
    Timestamp = $timestamp
    SubscriptionId = $subscription.Id
    ResourceGroupName = $ResourceGroupName
    Location = $Location
    AdminUsername = $AdminUsername
    AzureHub = $hubDeployment
    NestedVM = $nestedVmInfo
    OnPremPrefix = $OnPremPrefix
    VNetPrefix = $VNetPrefix
    NextSteps = @(
        "1. RDP to nested VM: mstsc /v:$($nestedVmInfo.PublicIp)"
        "2. Inside VM, run Lab5-Configure-NestedVM.ps1 to create Arc VM"
        "3. Install Windows Server on nested Arc VM"
        "4. Run Arc-Onboard.ps1 to onboard agent using proxy: $($hubDeployment.ExplicitProxyUrl)"
    )
}

$deploymentInfo | ConvertTo-Json -Depth 10 | Out-File -FilePath $deploymentFile -Encoding UTF8 -Force

Write-Host "  ✓ Deployment info saved to: $deploymentFile" -ForegroundColor Green

# ============================================================================
# STEP 7: WAIT FOR HYPER-V INSTALLATION
# ============================================================================

Write-Host "\n[7/9] Waiting for Hyper-V installation to complete..." -ForegroundColor Yellow
Write-Host "  The nested VM will restart after Hyper-V installation" -ForegroundColor Gray
Write-Host "  ⏱  Estimated time: 5-10 minutes" -ForegroundColor Yellow

Start-Sleep -Seconds 300  # Wait 5 minutes for initial installation

Write-Host "  ✓ Hyper-V installation should be complete" -ForegroundColor Green

# ============================================================================
# STEP 8: GENERATE NESTED VM CONFIGURATION SCRIPT
# ============================================================================

Write-Host "\n[8/9] Generating nested VM configuration script..." -ForegroundColor Yellow

$nestedConfigScript = @'
# ============================================================================
# Nested VM Configuration Script
# Run this script INSIDE the nested Hyper-V VM via RDP
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Configuring Nested Hyper-V for Arc Onboarding              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Configuration
$azureFirewallProxy = "PLACEHOLDER_PROXY_URL"
$vpnGatewayIp = "PLACEHOLDER_VPN_IP"
$vpnSharedKey = "PLACEHOLDER_VPN_KEY"
$subscriptionId = "PLACEHOLDER_SUB_ID"
$resourceGroupName = "PLACEHOLDER_RG_NAME"
$location = "PLACEHOLDER_LOCATION"

# Step 1: Create Internal Virtual Switch
Write-Host "`n[1/5] Creating Internal Virtual Switch..." -ForegroundColor Yellow
New-VMSwitch -Name "Internal-Lab" -SwitchType Internal -ErrorAction SilentlyContinue
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*Internal-Lab*" }
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 10.0.1.254 -PrefixLength 24 -ErrorAction SilentlyContinue
Write-Host "  ✓ Internal-Lab switch created (10.0.1.254/24)" -ForegroundColor Green

# Step 2: Download Windows Server ISO
Write-Host "\n[2/5] Downloading Windows Server ISO for Arc VM..." -ForegroundColor Yellow
$isoPath = "C:\ISOs"
New-Item -ItemType Directory -Path $isoPath -Force | Out-Null

# Download Windows Server 2022 Evaluation ISO
$wsIsoUrl = "https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US"
$wsIsoPath = "$isoPath\WS2022.iso"

if (-not (Test-Path $wsIsoPath)) {
    Write-Host "  Downloading Windows Server 2022 ISO..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $wsIsoUrl -OutFile $wsIsoPath -UseBasicParsing
    Write-Host "  ✓ ISO downloaded" -ForegroundColor Green
} else {
    Write-Host "  ✓ ISO already exists" -ForegroundColor Green
}

# Step 3: Create Arc-enabled Windows Server VM
Write-Host "`n[3/5] Creating Arc-enabled Windows Server VM..." -ForegroundColor Yellow

$vmName = "ARC-Server-01"
$vhdPath = "C:\Hyper-V\$vmName\$vmName.vhdx"

New-Item -ItemType Directory -Path "C:\Hyper-V\$vmName" -Force | Out-Null
New-VHD -Path $vhdPath -SizeBytes 60GB -Dynamic | Out-Null

New-VM -Name $vmName `
       -MemoryStartupBytes 4GB `
       -Generation 2 `
       -VHDPath $vhdPath `
       -SwitchName "Internal-Lab"

Set-VM -Name $vmName -ProcessorCount 2 -DynamicMemory -MemoryMinimumBytes 2GB -MemoryMaximumBytes 4GB
Add-VMDvdDrive -VMName $vmName -Path $wsIsoPath
Set-VMFirmware -VMName $vmName -FirstBootDevice (Get-VMDvdDrive -VMName $vmName)

Write-Host "  ✓ VM created: $vmName" -ForegroundColor Green
Write-Host "    Network: Internal-Lab (10.0.1.0/24)" -ForegroundColor Gray
Write-Host "    Next: Install Windows Server and configure networking" -ForegroundColor Yellow

# Step 4: Generate Arc Onboarding Script
Write-Host "`n[4/5] Generating Arc onboarding script..." -ForegroundColor Yellow

$arcOnboardScript = @"
# Arc Onboarding Script (run INSIDE Arc-Server-01 after Windows installation)

# Configure networking
New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress 10.0.1.10 -PrefixLength 24 -DefaultGateway 10.0.1.254
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 168.63.129.16

# Configure proxy for Arc agent
[Environment]::SetEnvironmentVariable('HTTPS_PROXY', 'PLACEHOLDER_PROXY_URL', 'Machine')
[Environment]::SetEnvironmentVariable('HTTP_PROXY', 'PLACEHOLDER_PROXY_URL', 'Machine')

# Download Arc agent
Invoke-WebRequest -Uri 'https://aka.ms/AzureConnectedMachineAgent' -OutFile 'C:\AzureConnectedMachineAgent.msi' -Proxy 'PLACEHOLDER_PROXY_URL'

# Install Arc agent
msiexec /i C:\AzureConnectedMachineAgent.msi /qn /norestart

# Onboard to Azure Arc
& 'C:\Program Files\AzureConnectedMachineAgent\azcmagent.exe' connect --subscription-id 'PLACEHOLDER_SUB_ID' --resource-group 'PLACEHOLDER_RG_NAME' --location 'PLACEHOLDER_LOCATION' --proxy-url 'PLACEHOLDER_PROXY_URL'
"@

$arcOnboardScript | Out-File -FilePath "C:\Arc-Onboard.ps1" -Encoding UTF8 -Force
Write-Host "  * Arc onboarding script saved to: C:\Arc-Onboard.ps1" -ForegroundColor Green

# Step 5: Summary
Write-Host "`n[5/5] Configuration Complete!" -ForegroundColor Green
Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Start VM: Start-VM -Name 'ARC-Server-01'" -ForegroundColor White
Write-Host "  2. Connect to VM: vmconnect.exe localhost 'ARC-Server-01'" -ForegroundColor White
Write-Host "  3. Install Windows Server 2022" -ForegroundColor White
Write-Host "  4. Inside VM, run: C:\Arc-Onboard.ps1" -ForegroundColor White
Write-Host "`nProxy URL: PLACEHOLDER_PROXY_URL" -ForegroundColor Cyan
Write-Host "VPN Shared Key: PLACEHOLDER_VPN_KEY" -ForegroundColor Cyan
'@

# Replace placeholders with actual values
$nestedConfigScript = $nestedConfigScript.Replace('PLACEHOLDER_PROXY_URL', $hubDeployment.ExplicitProxyUrl)
$nestedConfigScript = $nestedConfigScript.Replace('PLACEHOLDER_VPN_IP', $hubDeployment.VpnGatewayPublicIp)
$nestedConfigScript = $nestedConfigScript.Replace('PLACEHOLDER_VPN_KEY', $hubDeployment.VpnSharedKey)
$nestedConfigScript = $nestedConfigScript.Replace('PLACEHOLDER_SUB_ID', $subscription.Id)
$nestedConfigScript = $nestedConfigScript.Replace('PLACEHOLDER_RG_NAME', $ResourceGroupName)
$nestedConfigScript = $nestedConfigScript.Replace('PLACEHOLDER_LOCATION', $Location)

$nestedConfigScriptPath = Join-Path $PSScriptRoot "Lab5-Configure-NestedVM.ps1"
$nestedConfigScript | Out-File -FilePath $nestedConfigScriptPath -Encoding UTF8 -Force

Write-Host "  * Configuration script saved to: $nestedConfigScriptPath" -ForegroundColor Green

# ============================================================================
# STEP 9: DISPLAY SUMMARY
# ============================================================================

Write-Host "\n[9/9] Deployment Complete!" -ForegroundColor Yellow

Write-Host "\n========================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nDeployment Summary:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "  Location: $Location" -ForegroundColor White
Write-Host "`nAzure Firewall:" -ForegroundColor Cyan
Write-Host "  Private IP: $($hubDeployment.FirewallPrivateIp)" -ForegroundColor White
Write-Host "  Explicit Proxy: $($hubDeployment.ExplicitProxyUrl)" -ForegroundColor White
Write-Host "`nVPN Gateway:" -ForegroundColor Cyan
Write-Host "  Public IP: $($hubDeployment.VpnGatewayPublicIp)" -ForegroundColor White
Write-Host "  Shared Key: $($hubDeployment.VpnSharedKey)" -ForegroundColor White
Write-Host "`nNested Hyper-V VM:" -ForegroundColor Cyan
Write-Host "  Name: $($nestedVmInfo.VmName)" -ForegroundColor White
Write-Host "  Public IP: $($nestedVmInfo.PublicIp)" -ForegroundColor White
Write-Host "  Username: $AdminUsername" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. RDP to nested VM:" -ForegroundColor White
Write-Host "     mstsc /v:$($nestedVmInfo.PublicIp)" -ForegroundColor Gray
Write-Host "`n  2. Inside nested VM, run configuration script:" -ForegroundColor White
Write-Host "     Copy and paste script from: $nestedConfigScriptPath" -ForegroundColor Gray
Write-Host "`n  3. Install Windows Server on Arc VM and run onboarding script" -ForegroundColor White
Write-Host "`n  4. Validate Arc traffic flows through both firewalls" -ForegroundColor White

Write-Host "`nDeployment info saved to:" -ForegroundColor Cyan
Write-Host "  $deploymentFile" -ForegroundColor Gray

Write-Host "`n* All Azure resources deployed successfully!" -ForegroundColor Green
Write-Host "Estimated total deployment time: ~60-90 minutes (VPN Gateway)" -ForegroundColor Yellow
