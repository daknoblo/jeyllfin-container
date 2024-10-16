targetScope = 'resourceGroup'

param projPrefix string = 'jf'

var location = 'germanywestcentral'
var rgName = 'jellyfin-dev'

var storageSku = 'Standard_LRS'
var storageKind = 'StorageV2'
var storageAccNameAppdata = '${projPrefix}saappdata4908'
var storageAccNameMedia = '${projPrefix}samedia4286'
var saAccKeyAppdata = listkeys(resourceId('Microsoft.Storage/storageAccounts', storageAccNameAppdata), '2019-06-01').keys[0].value
var saAccKeyMedia = listkeys(resourceId('Microsoft.Storage/storageAccounts', storageAccNameMedia), '2019-06-01').keys[0].value


// foundational resources

resource resourceGroupName 'Microsoft.Resources/resourceGroups@2024-07-01' existing = {
  name: rgName
  scope: subscription(rgName)
}

// network resources
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
        //nsg: vnetNsg.outputs.name
        delegations: [
          {
            name: 'delegate-ci'
            properties: {
              serviceName: 'Microsoft.ContainerInstance/containerGroups'
            }
          }
        ]
        networkSecurityGroup: {
          id: vnetNsg.outputs.resourceId
        }
      }
      {
        name: 'DefaultSubnet'
        addressPrefix: '10.10.2.0/24'
        networkSecurityGroup: {
          id: vnetNsg.outputs.resourceId
        }
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
    name: 'biceptest.local'
    // Non-required parameters
    location: 'global'
  }
}

// storage for containers
module storageAccountAppdata 'br/public:avm/res/storage/storage-account:0.14.1' = {
  name: '${projPrefix}-storageAccount-Appdata'
  scope: resourceGroup(resourceGroupName.name)
  params: {
    // Required parameters
    name: storageAccNameAppdata
    location: location
    // Non-required parameters
    skuName: storageSku
    kind: storageKind
    privateEndpoints: [
      {
        privateDnsZoneResourceIds: [
          privateDnsZone.outputs.resourceId
        ]
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

// container group
module containerGroup 'br/public:avm/res/container-instance/container-group:0.2.1' = {
  name: '${projPrefix}-containerGroupDeployment'
  scope: resourceGroup('bicep-dev-1')
  params: {
    // Required parameters
    name: '${projPrefix}-ci'
    ipAddressType: 'Private'
    subnetId: virtualNetwork.outputs.subnetResourceIds[1]
    autoGeneratedDomainNameLabelScope: 'SubscriptionReuse'
    containers: [
      {
        name: 'jellyfin-server'
        properties: {
          command: []
          environmentVariables: [ ]
          image: 'linuxserver/jellyfin'
          ports: [
            {
              port: 8096
              protocol: 'Tcp'
            } ]
          resources: {
            requests: {
              cpu: 2
              memoryInGB: 2
            } }
          volumeMounts: [
            {
              mountPath: '/config'
              name: 'jellyfin-appdata-config'
              readOnly: false
            }
            {
              mountPath: '/cache'
              name: 'jellyfin-appdata-cache'
              readOnly: false
            }
            {
              mountPath: '/media'
              name: 'jellyfin-media'
              readOnly: true
            }
          ]
          }
        }
        
        ]
    ipAddressPorts: [
      {
        port: 8096
        protocol: 'Tcp'
      }
    ]
    // Non-required parameters
    location: location
    volumes: [
      {
        name: 'jellyfin-appdata-config'
        azureFile: {
          shareName: 'jellyfin-appdata-config'
          storageAccountName: storageAccNameAppdata
          storageAccountKey: saAccKeyAppdata
        }
      }
      {
        name: 'jellyfin-appdata-cache'
        azureFile: {
          shareName: 'jellyfin-appdata-cache'
          storageAccountName: storageAccNameMedia
          storageAccountKey: saAccKeyMedia
        }
      }
      {
        name: 'jellyfin-media'
        azureFile: {
          shareName: 'jellyfin-media'
          storageAccountName: storageAccNameMedia
          storageAccountKey: saAccKeyMedia
        }
      }
    ]
  }
}
