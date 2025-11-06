# Lab 3 - Hub-Spoke Infrastructure Script
# Deploy Hub-and-Spoke topology with Azure Firewall Explicit Proxy

param(
    [Parameter(Mandatory=$true)]
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "Sweden Central",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "RG-AFEP-HubSpoke"
)

Write-Host "🚀 Starting Lab 3 Hub-Spoke Infrastructure Deployment..." -ForegroundColor Cyan
Write-Host "⏱️  This will take approximately 15-20 minutes..." -ForegroundColor Yellow

# Check required modules
Write-Host "`n🔍 Checking Azure PowerShell modules..." -ForegroundColor Yellow
$requiredModules = @('Az.Network', 'Az.Compute', 'Az.Resources')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "⚠️  Module $module not found. Installing..." -ForegroundColor Yellow
        Install-Module -Name $module -Repository PSGallery -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}
Write-Host "✅ All required modules loaded" -ForegroundColor Green

# 1. Create Resource Group
Write-Host "`n📦 Creating Resource Group: $ResourceGroupName" -ForegroundColor Yellow
$rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force
Write-Host "✅ Resource Group created" -ForegroundColor Green

# 2. Create Hub VNet
Write-Host "`n🌐 Creating Hub VNet..." -ForegroundColor Yellow
$hubFirewallSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "AzureFirewallSubnet" `
    -AddressPrefix "10.0.0.0/26"

$hubSharedSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "SharedServices" `
    -AddressPrefix "10.0.2.0/24"

$hubVnet = New-AzVirtualNetwork `
    -Name "Hub-VNet" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AddressPrefix "10.0.0.0/16" `
    -Subnet $hubFirewallSubnet, $hubSharedSubnet

Write-Host "✅ Hub VNet created" -ForegroundColor Green

# 3. Create Spoke1 VNet
Write-Host "`n🌐 Creating Spoke1 VNet..." -ForegroundColor Yellow
$spoke1Subnet = New-AzVirtualNetworkSubnetConfig `
    -Name "Workload1-Subnet" `
    -AddressPrefix "10.1.0.0/24"

$spoke1Vnet = New-AzVirtualNetwork `
    -Name "Spoke1-VNet" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AddressPrefix "10.1.0.0/16" `
    -Subnet $spoke1Subnet

Write-Host "✅ Spoke1 VNet created" -ForegroundColor Green

# 4. Create Spoke2 VNet
Write-Host "`n🌐 Creating Spoke2 VNet..." -ForegroundColor Yellow
$spoke2Subnet = New-AzVirtualNetworkSubnetConfig `
    -Name "Workload2-Subnet" `
    -AddressPrefix "10.2.0.0/24"

$spoke2Vnet = New-AzVirtualNetwork `
    -Name "Spoke2-VNet" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AddressPrefix "10.2.0.0/16" `
    -Subnet $spoke2Subnet

Write-Host "✅ Spoke2 VNet created" -ForegroundColor Green

# 5. Create VNet Peerings
Write-Host "`n🔗 Creating VNet Peerings..." -ForegroundColor Yellow

Add-AzVirtualNetworkPeering `
    -Name "Hub-to-Spoke1" `
    -VirtualNetwork $hubVnet `
    -RemoteVirtualNetworkId $spoke1Vnet.Id `
    -AllowForwardedTraffic `
    -AllowGatewayTransit | Out-Null

Add-AzVirtualNetworkPeering `
    -Name "Spoke1-to-Hub" `
    -VirtualNetwork $spoke1Vnet `
    -RemoteVirtualNetworkId $hubVnet.Id `
    -AllowForwardedTraffic `
    -UseRemoteGateways:$false | Out-Null

Add-AzVirtualNetworkPeering `
    -Name "Hub-to-Spoke2" `
    -VirtualNetwork $hubVnet `
    -RemoteVirtualNetworkId $spoke2Vnet.Id `
    -AllowForwardedTraffic `
    -AllowGatewayTransit | Out-Null

Add-AzVirtualNetworkPeering `
    -Name "Spoke2-to-Hub" `
    -VirtualNetwork $spoke2Vnet `
    -RemoteVirtualNetworkId $hubVnet.Id `
    -AllowForwardedTraffic `
    -UseRemoteGateways:$false | Out-Null

Write-Host "✅ VNet Peerings created" -ForegroundColor Green

# 6. Create Firewall Public IP
Write-Host "`n🌍 Creating Firewall Public IP..." -ForegroundColor Yellow
$firewallPip = New-AzPublicIpAddress `
    -Name "pip-firewall-hub" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AllocationMethod Static `
    -Sku Standard

Write-Host "✅ Firewall Public IP created" -ForegroundColor Green

# 7. Create Firewall Policy
Write-Host "`n🛡️  Creating Firewall Policy..." -ForegroundColor Yellow
$firewallPolicy = New-AzFirewallPolicy `
    -Name "afp-hub-policy" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -ThreatIntelMode "Alert" `
    -SkuTier "Premium"

$firewallPolicy.DnsSettings = New-Object Microsoft.Azure.Commands.Network.Models.PSAzureFirewallPolicyDnsSettings
$firewallPolicy.DnsSettings.EnableProxy = $true
Set-AzFirewallPolicy -InputObject $firewallPolicy | Out-Null

Write-Host "✅ Firewall Policy created (Premium)" -ForegroundColor Green

# 8. Deploy Azure Firewall
Write-Host "`n🔥 Deploying Azure Firewall (Premium) in Hub (8-12 minutes)..." -ForegroundColor Yellow
$hubVnet = Get-AzVirtualNetwork -Name "Hub-VNet" -ResourceGroupName $ResourceGroupName
$firewall = New-AzFirewall `
    -Name "afw-hub" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -VirtualNetwork $hubVnet `
    -PublicIpAddress $firewallPip `
    -FirewallPolicyId $firewallPolicy.Id `
    -SkuName AZFW_VNet `
    -SkuTier Premium

Write-Host "✅ Azure Firewall deployed in Hub" -ForegroundColor Green

# Retrieve the firewall configuration to get the private IP
$firewall = Get-AzFirewall -Name "afw-hub" -ResourceGroupName $ResourceGroupName
if ($firewall.IpConfigurations -and $firewall.IpConfigurations.Count -gt 0) {
    $firewallPrivateIP = $firewall.IpConfigurations[0].PrivateIPAddress
} else {
    Write-Warning "Firewall IP configuration not yet available. Using default."
    $firewallPrivateIP = "Not available"
}

# 9. Create Route Tables
Write-Host "`n🛣️  Creating Route Tables for Spokes..." -ForegroundColor Yellow

# Route Table for Spoke1
$route1 = New-AzRouteConfig `
    -Name "default-via-firewall" `
    -AddressPrefix "0.0.0.0/0" `
    -NextHopType "VirtualAppliance" `
    -NextHopIpAddress $firewallPrivateIP

$routeTable1 = New-AzRouteTable `
    -Name "rt-spoke1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Route $route1 `
    -DisableBgpRoutePropagation

$spoke1Vnet = Get-AzVirtualNetwork -Name "Spoke1-VNet" -ResourceGroupName $ResourceGroupName
$spoke1Subnet = Get-AzVirtualNetworkSubnetConfig -Name "Workload1-Subnet" -VirtualNetwork $spoke1Vnet
$spoke1Subnet.RouteTable = $routeTable1
Set-AzVirtualNetwork -VirtualNetwork $spoke1Vnet | Out-Null

# Route Table for Spoke2
$route2 = New-AzRouteConfig `
    -Name "default-via-firewall" `
    -AddressPrefix "0.0.0.0/0" `
    -NextHopType "VirtualAppliance" `
    -NextHopIpAddress $firewallPrivateIP

$routeTable2 = New-AzRouteTable `
    -Name "rt-spoke2" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Route $route2 `
    -DisableBgpRoutePropagation

$spoke2Vnet = Get-AzVirtualNetwork -Name "Spoke2-VNet" -ResourceGroupName $ResourceGroupName
$spoke2Subnet = Get-AzVirtualNetworkSubnetConfig -Name "Workload2-Subnet" -VirtualNetwork $spoke2Vnet
$spoke2Subnet.RouteTable = $routeTable2
Set-AzVirtualNetwork -VirtualNetwork $spoke2Vnet | Out-Null

Write-Host "✅ Route Tables created and associated" -ForegroundColor Green

# 10. Deploy VMs in Spokes
Write-Host "`n💻 Deploying VMs in Spoke networks (5-7 minutes)..." -ForegroundColor Yellow

# VM in Spoke1
$spoke1Vnet = Get-AzVirtualNetwork -Name "Spoke1-VNet" -ResourceGroupName $ResourceGroupName
$spoke1Subnet = Get-AzVirtualNetworkSubnetConfig -Name "Workload1-Subnet" -VirtualNetwork $spoke1Vnet

$spoke1Pip = New-AzPublicIpAddress `
    -Name "pip-vm-spoke1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AllocationMethod Static `
    -Sku Standard

$spoke1Nic = New-AzNetworkInterface `
    -Name "vm-spoke1-nic" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -SubnetId $spoke1Subnet.Id `
    -PublicIpAddressId $spoke1Pip.Id

$vmConfig1 = New-AzVMConfig -VMName "vm-spoke1" -VMSize "Standard_B2s" | `
    Set-AzVMOperatingSystem -Windows -ComputerName "vm-spoke1" -Credential (New-Object PSCredential("azureadmin", $AdminPassword)) | `
    Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | `
    Add-AzVMNetworkInterface -Id $spoke1Nic.Id | `
    Set-AzVMBootDiagnostic -Disable

New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig1 -AsJob | Out-Null

# VM in Spoke2
$spoke2Vnet = Get-AzVirtualNetwork -Name "Spoke2-VNet" -ResourceGroupName $ResourceGroupName
$spoke2Subnet = Get-AzVirtualNetworkSubnetConfig -Name "Workload2-Subnet" -VirtualNetwork $spoke2Vnet

$spoke2Pip = New-AzPublicIpAddress `
    -Name "pip-vm-spoke2" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AllocationMethod Static `
    -Sku Standard

$spoke2Nic = New-AzNetworkInterface `
    -Name "vm-spoke2-nic" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -SubnetId $spoke2Subnet.Id `
    -PublicIpAddressId $spoke2Pip.Id

$vmConfig2 = New-AzVMConfig -VMName "vm-spoke2" -VMSize "Standard_B2s" | `
    Set-AzVMOperatingSystem -Windows -ComputerName "vm-spoke2" -Credential (New-Object PSCredential("azureadmin", $AdminPassword)) | `
    Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | `
    Add-AzVMNetworkInterface -Id $spoke2Nic.Id | `
    Set-AzVMBootDiagnostic -Disable

New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig2 -AsJob | Out-Null

Write-Host "✅ VM deployments started (running in background)" -ForegroundColor Green

# Wait for VM deployments
Write-Host "`n⏳ Waiting for VM deployments to complete..." -ForegroundColor Yellow
Get-Job | Wait-Job | Out-Null
Get-Job | Remove-Job

$spoke1Pip = Get-AzPublicIpAddress -Name "pip-vm-spoke1" -ResourceGroupName $ResourceGroupName
$spoke2Pip = Get-AzPublicIpAddress -Name "pip-vm-spoke2" -ResourceGroupName $ResourceGroupName

Write-Host "✅ All VMs deployed" -ForegroundColor Green

# Summary
Write-Host "`n" + ("="*80) -ForegroundColor Cyan
Write-Host "🎉 Lab 3 Hub-Spoke Infrastructure Deployment Complete!" -ForegroundColor Green
Write-Host ("="*80) -ForegroundColor Cyan
Write-Host "`nDeployment Summary:" -ForegroundColor Yellow
Write-Host "  Hub VNet: Hub-VNet (10.0.0.0/16)"
Write-Host "  Spoke1 VNet: Spoke1-VNet (10.1.0.0/16)"
Write-Host "  Spoke2 VNet: Spoke2-VNet (10.2.0.0/16)"
Write-Host "  Firewall Name: afw-hub (Premium SKU)"
Write-Host "  Firewall Private IP: $firewallPrivateIP"
Write-Host "  Firewall Public IP: $($firewallPip.IpAddress)"
Write-Host "  VM Spoke1 Public IP: $($spoke1Pip.IpAddress)"
Write-Host "  VM Spoke2 Public IP: $($spoke2Pip.IpAddress)"
Write-Host "  Admin Username: azureadmin"
Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Enable Explicit Proxy with PAC file (see READMEAUTO.md Step 2)"
Write-Host "  2. Create Application Rules for Hub-Spoke (see READMEAUTO.md Step 3)"
Write-Host "  3. Configure proxy on Spoke VMs (see READMEAUTO.md Step 4)"
Write-Host "  4. Test hub-spoke connectivity (see READMEAUTO.md Step 5)"
Write-Host ("="*80) -ForegroundColor Cyan

# Save deployment info
$deploymentInfo = @{
    ResourceGroup = $ResourceGroupName
    Location = $Location
    FirewallPrivateIP = $firewallPrivateIP
    FirewallPublicIP = $firewallPip.IpAddress
    Spoke1VMPublicIP = $spoke1Pip.IpAddress
    Spoke2VMPublicIP = $spoke2Pip.IpAddress
    FirewallPolicyId = $firewallPolicy.Id
} | ConvertTo-Json

$deploymentInfo | Out-File -FilePath ".\Lab3-DeploymentInfo.json" -Force
Write-Host "`n💾 Deployment info saved to: Lab3-DeploymentInfo.json" -ForegroundColor Green
