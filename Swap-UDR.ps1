<#
    .SYNOPSIS
        Using the names of 2 Network Virtual Appliances in Azure, this script will find all User Defined Routes and swap them to point from one to the other.

    .DESCRIPTION
        Process Flow:
            Get NVA VMs
            Get NICs for each NVA
            Get IPs for each NIC
            Confirm that each pair of NICs for the Primary & Secondary are on the same subnet
            Get the UDR for each subnet
            Check all UDR routes that point to the Primary NVA and swap them to point to the secondary NVA
            Write the changes to the UDR
    
    .NOTES
        Author: Michael Cross
        Date: April 2018
        URL: https://github.com/mcrosstx/Scripts/blob/master/Swap-UDR.ps1

        Assumptions:
            -NVAs and NICs must be in the same Resource Group
            -NVAs must have the same number of NICs
            -NICs should be in the same order on each NVA
            -NICs should only have a single IP configuration
    
    .PARAMETER PrimaryNVAName
        This is the name of the VM in Azure hosting the NVA that currently has traffic routed through it

    .PARAMETER SecondaryNVAName
        This is the name of the VM in Azure hosting the NVA that we want to fail traffic over to route through

    .PARAMETER NVAResourceGroup
        This is the Name of the Resource Group that contains the NVAs
    
    
#>

[cmdletbinding(SupportsShouldProcess=$True)]

param(
    [Parameter(Mandatory=$True)]
    [string]$PrimaryNVAName,
    [Parameter(Mandatory=$True)]
    [string]$SecondaryNVAName,
    [Parameter(Mandatory=$True)]
    [string]$NVAResourceGroup
)

# Get VMs from provided information
$PrimaryNVA = Get-AzureRMVM -ResourceGroup $NVAResourceGroup -Name $PrimaryNVAName
$SecondaryNVA = Get-AzureRMVM -ResourceGroup $NVAResourceGroup -Name $SecondaryNVAName

# Check the PrimaryNVA for number of NICs and use this to limit loops
If ($PrimaryNVA.NetworkProfile.NetworkInterfaces.Count -eq $SecondaryNVA.NetworkProfile.NetworkInterfaces.Count){
    $NICLimit = $PrimaryNVA.NetworkProfile.NetworkInterfaces.Count
}
else{
    Write-Verbose "Number of NICs is unequal between Primary and Secondary Firewalls. Stopping script execution"
    exit
}

# Initialize loop variables
$PrimaryNVANIC = $null
$SecondaryNVANIC = $null
$RouteTable = $null

# Begin looping through NICs to swap routing
For ($i=0;$i -lt $NICLimit;$i++) {
    # Get NICs
    $PrimaryNVANIC = Get-AzureRmNetworkInterface -Name ($PrimaryNVA.NetworkProfile.NetworkInterfaces[$i].Id).Split("/")[-1] -ResourceGroupName $NVAResourceGroup
    $SecondaryNVANIC = Get-AzureRmNetworkInterface -Name ($SecondaryNVA.NetworkProfile.NetworkInterfaces[$i].Id).Split("/")[-1] -ResourceGroupName $NVAResourceGroup
    $PrimaryNVAIP = $PrimaryNVANIC.IpConfigurations[0].PrivateIpAddress
    $SecondaryNVAIP = $SecondaryNVANIC.IpConfigurations[0].PrivateIpAddress

    # Get VNet and Subnets
    $Psubnetsplit = ($PrimaryNVANIC.IpConfigurations[0].subnet.Id).Split("/")
    $Ssubnetsplit = ($SecondaryNVANIC.IpConfigurations[0].subnet.Id).Split("/")
    $VirtualNetwork = Get-AzureRmVirtualNetwork -Name $Psubnetsplit[-3] -ResourceGroupName $Psubnetsplit[4]
    $PrimaryNVASubnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork  -Name $Psubnetsplit[-1]
    $SecondaryNVASubnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork  -Name $Ssubnetsplit[-1]
    
    # Confirm Primary and Secondary NICs are in the same subnet
    If ($PrimaryNVASubnet.Id -eq $SecondaryNVASubnet.Id) {
        Write-Verbose $PrimaryNVASubnet.Name
        # Get Route Table information
        $RTSplit = $PrimaryNVASubnet.RouteTable.id.Split("/")
        $RouteTable = Get-AzureRmRouteTable -ResourceGroupName $RTSplit[4] -Name $RTSplit[-1]
        # Check all Routes and update as appropriate
        Write-Verbose "$($RouteTable.Name) is being updated:"
        Foreach ($Route in $($RouteTable.Routes)){
            # Skipping any /32 routes
            If (($Route.AddressPrefix.Split("/"))[-1] -eq "32"){
                Write-Verbose "Skipping /32 Route: $($Route.Name)"
                continue
            }
            # Confirming we are only changing routes that are currently routing through the Primary Firewall
            elseif ($Route.NextHopIpAddress -eq $PrimaryNVAIP) {
                if ($PSCmdlet.ShouldProcess($Route.Name,"Update")){
                    Set-AzureRmRouteConfig -RouteTable $RouteTable -Name $Route.Name -AddressPrefix $Route.AddressPrefix -NextHopType $Route.NextHopType -NextHopIpAddress $SecondaryNVAIP | Out-Null
                }
                Write-Verbose "$($Route.Name) Route NextHopIP switched to $SecondaryNVAIP"
            }
        }
        # Updating the Route Table with the changed routes
        if ($PSCmdlet.ShouldProcess($RouteTable.Name,"Update")){
            Set-AzureRmRouteTable -RouteTable $RouteTable | Out-Null
        }
        Write-Verbose "$($RouteTable.Name) Update Complete"
    }
    else {
        Write-Verbose "Subnet/Route Table mismatch, moving to next set of NICs"
        continue
    }
}