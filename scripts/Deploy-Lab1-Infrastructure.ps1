# Lab 1 - Infrastructure Deployment Script
# Deploy Azure Firewall with Explicit Proxy (AFEP) - Basic Infrastructure

param(
    [Parameter(Mandatory=$true)]
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "Sweden Central",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "RG-AFEP-Lab1"
)

Write-Host "🚀 Starting Lab 1 Infrastructure Deployment..." -ForegroundColor Cyan

# 1. Create Resource Group
Write-Host "`n📦 Creating Resource Group: $ResourceGroupName" -ForegroundColor Yellow
$rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force
Write-Host "✅ Resource Group created" -ForegroundColor Green

# 2. Create Virtual Network with Subnets
Write-Host "`n🌐 Creating Virtual Network with subnets..." -ForegroundColor Yellow
$firewallSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "AzureFirewallSubnet" `
    -AddressPrefix "10.0.0.0/26"

$clientSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name "ClientSubnet" `
    -AddressPrefix "10.0.2.0/24"

$vnet = New-AzVirtualNetwork `
    -Name "VNet-Lab1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AddressPrefix "10.0.0.0/16" `
    -Subnet $firewallSubnet, $clientSubnet

Write-Host "✅ Virtual Network created with AzureFirewallSubnet (/26) and ClientSubnet" -ForegroundColor Green

# 3. Create Public IP for Firewall
Write-Host "`n🌍 Creating Public IP for Firewall..." -ForegroundColor Yellow
$firewallPip = New-AzPublicIpAddress `
    -Name "pip-firewall-lab1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AllocationMethod Static `
    -Sku Standard

Write-Host "✅ Firewall Public IP created: $($firewallPip.IpAddress)" -ForegroundColor Green

# 4. Create Firewall Policy
Write-Host "`n🛡️  Creating Firewall Policy..." -ForegroundColor Yellow
$firewallPolicy = New-AzFirewallPolicy `
    -Name "afp-lab1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -ThreatIntelMode "Alert" `
    -SkuTier "Standard"

# Enable DNS Proxy
$firewallPolicy.DnsSettings = New-Object Microsoft.Azure.Commands.Network.Models.PSAzureFirewallPolicyDnsSettings
$firewallPolicy.DnsSettings.EnableProxy = $true
Set-AzFirewallPolicy -InputObject $firewallPolicy | Out-Null

Write-Host "✅ Firewall Policy created" -ForegroundColor Green

# 5. Deploy Azure Firewall
Write-Host "`n🔥 Deploying Azure Firewall (this takes 5-10 minutes)..." -ForegroundColor Yellow
$firewall = New-AzFirewall `
    -Name "afw-lab1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -VirtualNetwork $vnet `
    -PublicIpAddress $firewallPip `
    -FirewallPolicyId $firewallPolicy.Id `
    -Sku AZFW_VNet `
    -Tier Standard

Write-Host "✅ Azure Firewall deployed" -ForegroundColor Green
Write-Host "   Private IP: $($firewall.IpConfigurations[0].PrivateIPAddress)" -ForegroundColor Cyan

# 6. Create NSG for Client Subnet
Write-Host "`n🔒 Creating Network Security Group..." -ForegroundColor Yellow
$nsgRule = New-AzNetworkSecurityRuleConfig `
    -Name "AllowRDP" `
    -Description "Allow RDP from your IP" `
    -Access Allow `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1000 `
    -SourceAddressPrefix "*" `
    -SourcePortRange "*" `
    -DestinationAddressPrefix "*" `
    -DestinationPortRange 3389

$nsg = New-AzNetworkSecurityGroup `
    -Name "nsg-client-lab1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -SecurityRules $nsgRule

Write-Host "✅ NSG created" -ForegroundColor Green

# 7. Create Public IP for Client VM
Write-Host "`n🌍 Creating Public IP for Client VM..." -ForegroundColor Yellow
$clientPip = New-AzPublicIpAddress `
    -Name "pip-client-lab1" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AllocationMethod Static `
    -Sku Standard

Write-Host "✅ Client Public IP created: $($clientPip.IpAddress)" -ForegroundColor Green

# 8. Create NIC for Client VM
Write-Host "`n🔌 Creating Network Interface for VM..." -ForegroundColor Yellow
$vnet = Get-AzVirtualNetwork -Name "VNet-Lab1" -ResourceGroupName $ResourceGroupName
$subnet = Get-AzVirtualNetworkSubnetConfig -Name "ClientSubnet" -VirtualNetwork $vnet

$nic = New-AzNetworkInterface `
    -Name "vm-client-lab1-nic" `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -SubnetId $subnet.Id `
    -PublicIpAddressId $clientPip.Id `
    -NetworkSecurityGroupId $nsg.Id

Write-Host "✅ Network Interface created" -ForegroundColor Green

# 9. Deploy Client VM
Write-Host "`n💻 Deploying Client VM (this takes 3-5 minutes)..." -ForegroundColor Yellow
$vmConfig = New-AzVMConfig -VMName "vm-client-lab1" -VMSize "Standard_B2s" | `
    Set-AzVMOperatingSystem -Windows -ComputerName "vm-client-lab1" -Credential (New-Object PSCredential("azureadmin", $AdminPassword)) | `
    Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2022-datacenter-azure-edition" -Version "latest" | `
    Add-AzVMNetworkInterface -Id $nic.Id | `
    Set-AzVMBootDiagnostic -Disable

$vm = New-AzVM `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -VM $vmConfig

Write-Host "✅ Client VM deployed" -ForegroundColor Green

# Summary
Write-Host "`n" + ("="*80) -ForegroundColor Cyan
Write-Host "🎉 Lab 1 Infrastructure Deployment Complete!" -ForegroundColor Green
Write-Host ("="*80) -ForegroundColor Cyan
Write-Host "`nDeployment Summary:" -ForegroundColor Yellow
Write-Host "  Resource Group: $ResourceGroupName"
Write-Host "  Location: $Location"
Write-Host "  Firewall Name: afw-lab1"
Write-Host "  Firewall Private IP: $($firewall.IpConfigurations[0].PrivateIPAddress)"
Write-Host "  Firewall Public IP: $($firewallPip.IpAddress)"
Write-Host "  Client VM Name: vm-client-lab1"
Write-Host "  Client VM Public IP: $($clientPip.IpAddress)"
Write-Host "  Admin Username: azureadmin"
Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Configure Explicit Proxy (see READMEAUTO.md Step 2)"
Write-Host "  2. Create Application Rules (see READMEAUTO.md Step 3)"
Write-Host "  3. Configure client proxy settings (see READMEAUTO.md Step 4)"
Write-Host "  4. Test the configuration (see READMEAUTO.md Step 5)"
Write-Host "`n💡 Save this information for later steps!" -ForegroundColor Cyan
Write-Host ("="*80) -ForegroundColor Cyan

# Save deployment info to file
$deploymentInfo = @{
    ResourceGroup = $ResourceGroupName
    Location = $Location
    FirewallPrivateIP = $firewall.IpConfigurations[0].PrivateIPAddress
    FirewallPublicIP = $firewallPip.IpAddress
    ClientVMPublicIP = $clientPip.IpAddress
    FirewallPolicyId = $firewallPolicy.Id
} | ConvertTo-Json

$deploymentInfo | Out-File -FilePath ".\Lab1-DeploymentInfo.json" -Force
Write-Host "`n💾 Deployment info saved to: Lab1-DeploymentInfo.json" -ForegroundColor Green
