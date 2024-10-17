targetScope = 'resourceGroup'

param projPrefix string = 'jf'

var location = 'germanywestcentral'
var rgName = 'jellyfin-dev'

var storageSku = 'Standard_LRS'
var storageKind = 'StorageV2'
var storageAccNameContainer = '${projPrefix}sacontainer7908'
//var saAccKeyAppdata = listkeys(resourceId('Microsoft.Storage/storageAccounts', storageAccNameAppdata), '2019-06-01').keys[0].value
//var saAccKeyMedia = listkeys(resourceId('Microsoft.Storage/storageAccounts', storageAccNameMedia), '2019-06-01').keys[0].value


// target resource group

resource resourceGroupName 'Microsoft.Resources/resourceGroups@2024-07-01' existing = {
  name: rgName
  scope: subscription(rgName)
}

// networking resources
module virtualNetwork 'br/public:avm/res/network/virtual-network:0.4.0' = {
  name: '${projPrefix}-virtualNetworkDeployment'
  scope: resourceGroup(resourceGroupName.name)
  params: {
    // Required parameters
    name: '${projPrefix}-vnet'
    addressPrefixes: [
      '10.10.0.0/16'
    ]
    location: location
    subnets: [
      {
        name: 'GatewaySubnet'
        addressPrefix: '10.10.0.0/24'
      }
      {
        name: 'ContainerInstanceSubnet'
        addressPrefix: '10.10.1.0/24'
      }
      {
        name: 'DefaultSubnet'
        addressPrefix: '10.10.2.0/24'
      }
    ]
  }
}

module vnetNsg 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: '${projPrefix}-vnetNsgDeployment'
  scope: resourceGroup(resourceGroupName.name)
  params: {
    // Required parameters
    name: '${projPrefix}-vnetNsg'
    location: location
    securityRules: [
      {
        name: 'DenyAllInBound'
        properties: {
          access: 'Deny'
          description: 'Deny all inbound traffic'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          direction: 'Inbound'
          priority: 4096
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'DenyAllOutBound'
        properties: {
          access: 'Deny'
          description: 'Deny all outbound traffic'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          direction: 'Outbound'
          priority: 4096
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
    ]
  }
}

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.6.0' = {
  name: '${projPrefix}-privateDnsZoneDeployment'
  params: {
    // Required parameters
    name: 'jellyfin.local'
    // Non-required parameters
    location: 'global'
  }
}

//
// storage for containers
//
module storageAccountContainer 'br/public:avm/res/storage/storage-account:0.14.1' = {
  name: '${projPrefix}-storageAccount-Container'
  scope: resourceGroup(resourceGroupName.name)
  params: {
    // Required parameters
    name: storageAccNameContainer
    location: location
    // Non-required parameters
    skuName: storageSku
    kind: storageKind
    privateEndpoints: [
      {
        service: 'file'
        subnetResourceId: virtualNetwork.outputs.subnetResourceIds[2]
      }
    ]
    fileServices: {
      shares: [
        {
          name: 'jellyfin-appdata'
          enabledProtocols: 'SMB'
          accessTier: 'Cool'
          shareQuota: 5
        }
        {
          name: 'jellyfin-media'
          enabledProtocols: 'SMB'
          accessTier: 'Cool'
          shareQuota: 100
        }
      ]
      allowsharedaccesskey: false
      shareSoftDeleteEnabled: false
      largeFileSharesState: 'Enabled'
    }
  }
}
