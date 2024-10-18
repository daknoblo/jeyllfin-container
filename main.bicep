targetScope = 'resourceGroup'

param projPrefix string = 'jf'

var location = 'germanywestcentral'
var rgName = 'jellyfin-dev'

var storageSku = 'Standard_LRS'
var storageKind = 'StorageV2'
var storageAccNameContainer = '${projPrefix}sacontainer7908'

// target resource group

resource resourceGroupName 'Microsoft.Resources/resourceGroups@2024-07-01' existing = {
  name: rgName
  scope: subscription(rgName)
}

//
// networking resources
//

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
        networkSecurityGroupResourceId: vnetNsg.outputs.resourceId
        delegation: 'Microsoft.ContainerInstance/containerGroups'
      }
      {
        name: 'DefaultSubnet'
        addressPrefix: '10.10.2.0/24'
        networkSecurityGroupResourceId: vnetNsg.outputs.resourceId
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
        name: 'AllowJellyfinInbound'
        properties: {
          access: 'Allow'
          description: 'Allow jellyfin traffic'
          destinationAddressPrefix: '*'
          destinationPortRange: '8096'
          direction: 'Inbound'
          priority: 200
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowJellyfinOutbound'
        properties: {
          access: 'Allow'
          description: 'Allow jellyfin traffic'
          destinationAddressPrefix: '*'
          destinationPortRange: '8096'
          direction: 'Outbound'
          priority: 200
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
    ]
  }
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-jellyfin'
  location: location
}

resource miRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountContainer.name, userAssignedIdentity.id, 'Storage Blob Data Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: userAssignedIdentity.properties.principalId
  }
}

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

//
// container instances
//

module containerGroup 'br/public:avm/res/container-instance/container-group:0.2.1' = {
  name: 'containerGroupDeployment'
  params: {
    // Required parameters
    name: '${projPrefix}-jellyfin'
    containers: [
      {
        name: 'jellyfin-test'
        properties: {
          image: 'lscr.io/linuxserver/jellyfin:latest'
          ports: [
            {
              port: 8096
              protocol: 'Tcp'
            }
          ]
          resources: {
            requests: {
              cpu: 2
              memoryInGB: 2
            }
          }
          environmentVariables: [
            {name: 'TZ', value: 'Europe/Berlin'}
          ]
          volumeMounts: [
            {
              name: 'appdata'
              mountPath: '/config'
              readOnly: false
            }
            {
              name: 'media'
              mountPath: '/media'
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
        name: 'appdata'
        azureFile: {
          shareName: 'jellyfin-appdata'
          storageAccountName: storageAccNameContainer
          identity: {
            userAssignedIdentity: userAssignedIdentity.id
          }
        }
      }
      {
        name: 'media'
        azureFile: {
          shareName: 'jellyfin-media'
          storageAccountName: storageAccNameContainer
          identity: {
            userAssignedIdentity: userAssignedIdentity.id
          }
        }
      }
    ]
  }
}
