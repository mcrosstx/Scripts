<#
    .SYNOPSIS
        Takes in the names of 2 Azure NVAs and fails over any user defined routing from one to the other.

    .DESCRIPTION
    
    .NOTES
    .

#>

param(
    [Parameter(Mandatory=$True)]
    [string]$PrimaryFWName,#="TestingUDRVM",
    [Parameter(Mandatory=$True)]
    [string]$SecondaryFWName,#="TestingUDRVM2",
    [Parameter(Mandatory=$True)]
    [string]$FWResourceGroup#="Testing"
)

# Get VMs from provided information
#Measure-Command {
$PrimaryFW = Get-AzureRMVM -ResourceGroup $FWResourceGroup -Name $PrimaryFWName
$SecondaryFW = Get-AzureRMVM -ResourceGroup $FWResourceGroup -Name $SecondaryFWName

# Check the PrimaryFW for number of NICs and use this to limit loops
If ($PrimaryFW.NetworkProfile.NetworkInterfaces.Count -eq $SecondaryFW.NetworkProfile.NetworkInterfaces.Count){
    $NICLimit = $PrimaryFW.NetworkProfile.NetworkInterfaces.Count
}
else{
    Write-Verbose "Number of NICs is unequal between Primary and Secondary Firewalls. Stopping script execution"
    exit
}

# Initialize loop variables
$PrimaryFWNIC = $null
$SecondaryFWNIC = $null
$RouteTable = $null

# Begin looping through NICs to swap routing
For ($i=0;$i -lt $NICLimit;$i++) {
    # Get NICs
    $PrimaryFWNIC = Get-AzureRmNetworkInterface -Name ($PrimaryFW.NetworkProfile.NetworkInterfaces[$i].Id).Split("/")[-1] -ResourceGroupName $FWResourceGroup
    $SecondaryFWNIC = Get-AzureRmNetworkInterface -Name ($SecondaryFW.NetworkProfile.NetworkInterfaces[$i].Id).Split("/")[-1] -ResourceGroupName $FWResourceGroup
    $PrimaryFWIP = $PrimaryFWNIC.IpConfigurations[0].PrivateIpAddress
    $SecondaryFWIP = $SecondaryFWNIC.IpConfigurations[0].PrivateIpAddress

    # Get VNet and Subnets
    $Psubnetsplit = ($PrimaryFWNIC.IpConfigurations[0].subnet.Id).Split("/")
    $Ssubnetsplit = ($SecondaryFWNIC.IpConfigurations[0].subnet.Id).Split("/")
    $VirtualNetwork = Get-AzureRmVirtualNetwork -Name $Psubnetsplit[-3] -ResourceGroupName $Psubnetsplit[4]
    $PrimaryFWSubnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork  -Name $Psubnetsplit[-1]
    $SecondaryFWSubnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork  -Name $Ssubnetsplit[-1]
    
    # Confirm Primary and Secondary NICs are in the same subnet
    If ($PrimaryFWSubnet.Id -eq $SecondaryFWSubnet.Id) {
        Write-Verbose $PrimaryFWSubnet.Name
        # Get Route Table information
        $RTSplit = $PrimaryFWSubnet.RouteTable.id.Split("/")
        $RouteTable = Get-AzureRmRouteTable -ResourceGroupName $RTSplit[4] -Name $RTSplit[-1]
        # Check all Routes and update as appropriate
        #$Routes = $RouteTable.Routes
        Write-Verbose "$($RouteTable.Name) is being updated:"
        Foreach ($Route in $($RouteTable.Routes)){
            If (($Route.AddressPrefix.Split("/"))[-1] -eq "32"){
                Write-Verbose "Skipping /32 Route: $($Route.Name)"
                continue
            }
            elseif ($Route.NextHopIpAddress -eq $PrimaryFWIP) {
                Set-AzureRmRouteConfig -RouteTable $RouteTable -Name $Route.Name -AddressPrefix $Route.AddressPrefix -NextHopType $Route.NextHopType -NextHopIpAddress $SecondaryFWIP | Out-Null
                Write-Verbose "$($Route.Name) Route NextHopIP switched to $SecondaryFWIP"
            }
        }
        Set-AzureRmRouteTable -RouteTable $RouteTable | Out-Null
        Write-Verbose "$($RouteTable.Name) Update Complete"
    }
    else {
        Write-Verbose "Subnet/Route Table mismatch, moving to next set of NICs"
        continue
    }
}
#} #Measure




#set-azurermrouteconfig -RouteTable $RouteTables[0] -Name FWRoute -NextHopIpAddress "192.168.44.4" -AddressPrefix "0.0.0.0/0" -NextHopType VirtualAppliance
#set-azurermroutetable -RouteTable $RouteTables[0]


