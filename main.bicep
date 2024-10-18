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

//// identity and role assignements ////

//// container instance ////

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
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
    restartPolicy: 'Always'
  }
}

output containerIPv4Address string = containerGroup.properties.ipAddress.ip
