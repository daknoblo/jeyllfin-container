targetScope = 'resourceGroup'

var prefix = 'jf'
var location = 'germanywestcentral'
var storageSku = 'Standard_LRS'
var storageKind = 'StorageV2'
var storageAccNameContainer = '${prefix}sacontainer7908'
var GlobalVnetName = '${prefix}-vnet'
var GlobalVnetAddressPrefix = '10.10.0.0/16'
var ContainerSubnetAddressPrefix = '10.10.1.0/24'
var ContainerSubnetName = 'aci-subnet'
//var networkProfileName = 'aci-networkProfile'
//var interfaceConfigName = 'eth0'
//var interfaceIpConfig = 'ipconfigprofile1'
var containerGroupName = '${prefix}-containergroup'
var containerName = '${prefix}-container'
var image = 'lscr.io/linuxserver/jellyfin:latest'
var port = 8096
var cpuCores = 2
var memoryInGb = 2

//// target resource group ////

//// network resources ////

resource GlobalVnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: GlobalVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        GlobalVnetAddressPrefix
      ]
    }
  }
}

resource ContainerSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  name: ContainerSubnetName
  parent: GlobalVnet
  properties: {
    addressPrefix: ContainerSubnetAddressPrefix
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
    ]
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

//// storage account ////

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccNameContainer
  location: location
  sku: {
    name: storageSku
  }
  kind: storageKind
  properties: {
    accessTier: 'Cold'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: ContainerSubnet.id
          action: 'Allow'
        }
      ]
    }
  }
}

resource fileShareJfConfig 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: '${storageAccount.name}/default/jfconfig'
  properties: {
    shareQuota: 5 // 5GB

  }
}

resource fileShareJfCache 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: '${storageAccount.name}/default/jfcache'
  properties: {
    shareQuota: 5 // 5GB
  }
}

resource fileShareJfMedia 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: '${storageAccount.name}/default/jfmedia'
  properties: {
    shareQuota: 100 // 100GB
  }
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
              name: 'jfconfig'
              mountPath: '/config'
              readOnly: false
            }
            {
              name: 'jfcache'
              mountPath: '/cache'
              readOnly: false
            }
            {
              name: 'jfmedia'
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
        id: ContainerSubnet.id
        name: ContainerSubnetName
      }
    ]
    ipAddress: {
      type: 'Private'
      ports: [
        {
          protocol: 'TCP'
          port: port
        }
      ]
    }
    volumes: [
      {
        name: 'jfconfig'
        azureFile: {
          shareName: 'jfconfig'
          storageAccountName: storageAccNameContainer
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
      {
        name: 'jfcache'
        azureFile: {
          shareName: 'jfcache'
          storageAccountName: storageAccNameContainer
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
      {
        name: 'jfmedia'
        azureFile: {
          shareName: 'jfmedia'
          storageAccountName: storageAccNameContainer
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
    ]
    restartPolicy: 'Always'
    sku: 'Standard'
  }
}
