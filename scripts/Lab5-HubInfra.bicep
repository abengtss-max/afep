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
