targetScope = 'resourceGroup'

var prefix = 'jf'
var location = 'germanywestcentral'
var rgName = 'jellyfin-dev'
var storageSku = 'Standard_LRS'
var storageKind = 'StorageV2'
var storageAccNameContainer = '${prefix}sacontainer7908'
var vnetName = '${prefix}-vnet'
var vnetAddressPrefix = '10.10.0.0/16'
var subnetAddressPrefix = '10.10.1.0/24'
var subnetName = 'aci-subnet'
var networkProfileName = 'aci-networkProfile'
var interfaceConfigName = 'eth0'
var interfaceIpConfig = 'ipconfigprofile1'
var containerGroupName = 'aci-containergroup'
var containerName = 'aci-container'
var image = 'mcr.microsoft.com/azuredocs/aci-helloworld'
var port = 80
var cpuCores = 2
var memoryInGb = 2
var userAssignedIdentityName = '${prefix}-userAssignedIdentity'

//// target resource group ////

resource resourceGroupName 'Microsoft.Resources/resourceGroups@2024-07-01' existing = {
  name: rgName
  scope: subscription(rgName)
}

//// network resources ////

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  name: subnetName
  parent: vnet
  properties: {
    addressPrefix: subnetAddressPrefix
    delegations: [
      {
        name: 'DelegationService'
        properties: {
          serviceName: 'Microsoft.ContainerInstance/containerGroups'
        }
      }
    ]
  }
}

resource networkProfile 'Microsoft.Network/networkProfiles@2024-01-01' = {
  name: networkProfileName
  location: location
  properties: {
    containerNetworkInterfaceConfigurations: [
      {
        name: interfaceConfigName
        properties: {
          ipConfigurations: [
            {
              name: interfaceIpConfig
              properties: {
                subnet: {
                  id: subnet.id
                }
              }
            }
          ]
        }
      }
    ]
  }
}

//// storage account ////

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccNameContainer
  location: location
  sku: {
    name: storageSku
  }
  kind: storageKind
  properties: {
    accessTier: 'Cool'
  }
}

resource fileShareAppData 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: '${storageAccount.name}/default/appdata'
  properties: {
    shareQuota: 5120 // 5GB
  }
}

resource fileShareMedia 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: '${storageAccount.name}/default/media'
  properties: {
    shareQuota: 10240 // 10GB
  }
}

//// identity and role assignements ////

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: location
}

//// container instance ////

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2024-05-01-preview' = {
  name: containerGroupName
  location: location
  properties: {
    containers: [
      {
        name: containerName
        properties: {
          image: image
          ports: [
            {
              port: port
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryInGb
            }
          }
          volumeMounts: [
            {
              name: 'appdata'
              mountPath: '/appdata'
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
    osType: 'Linux'
    subnetIds: [
      {
        id: subnet.id
        name: subnetName
      }
    ]
    volumes: [
      {
        name: 'appdata'
        azureFile: {
          shareName: 'appdata'
          storageAccountName: storageAccNameContainer
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
      {
        name: 'media'
        azureFile: {
          shareName: 'media'
          storageAccountName: storageAccNameContainer
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
    ]
    restartPolicy: 'Always'
  }
}

output containerIPv4Address string = containerGroup.properties.ipAddress.ip
