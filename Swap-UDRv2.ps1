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

#$PrimaryNVAName = "TestingUDRVM"
#$SecondaryNVAName = "TestingUDRVM2"
#$NVAResourceGroup = "Testing"

Write-Verbose "Failover from $PrimaryNVAName to $SecondaryNVAName starting at $(Get-Date)"

# Get VMs from provided information
Write-Verbose "Gathering NVA info"
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
$RouteTables = @()
$NICSets = @()
$Subs = @((Get-AzureRmContext).Subscription.Id)
$Peerings = @()

# Begin looping through NICs to swap routing
For ($i=0;$i -lt $NICLimit;$i++) {
    # Get NICs
    $PrimaryNVANIC = Get-AzureRmNetworkInterface -Name ($PrimaryNVA.NetworkProfile.NetworkInterfaces[$i].Id).Split("/")[-1] -ResourceGroupName $NVAResourceGroup
    $SecondaryNVANIC = Get-AzureRmNetworkInterface -Name ($SecondaryNVA.NetworkProfile.NetworkInterfaces[$i].Id).Split("/")[-1] -ResourceGroupName $NVAResourceGroup
    $PrimaryNVAIP = $PrimaryNVANIC.IpConfigurations[0].PrivateIpAddress
    $SecondaryNVAIP = $SecondaryNVANIC.IpConfigurations[0].PrivateIpAddress

    # Add IPs from both FWs to NICSet
    $tmpNICSet = New-Object System.Object
    $tmpNICSet | Add-Member -MemberType NoteProperty -Name PrimaryNVAIP -Value $PrimaryNVAIP
    $tmpNICSet | Add-Member -MemberType NoteProperty -Name SecondaryNVAIP -Value $SecondaryNVAIP

    # Get VNet and Subnets
    $Psubnetsplit = ($PrimaryNVANIC.IpConfigurations[0].subnet.Id).Split("/")
    $Ssubnetsplit = ($SecondaryNVANIC.IpConfigurations[0].subnet.Id).Split("/")
    $VirtualNetwork = Get-AzureRmVirtualNetwork -Name $Psubnetsplit[-3] -ResourceGroupName $Psubnetsplit[4]
    $Peerings = $VirtualNetwork.VirtualNetworkPeerings
    $PrimaryNVASubnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork  -Name $Psubnetsplit[-1]
    $SecondaryNVASubnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VirtualNetwork  -Name $Ssubnetsplit[-1]
    
    # Confirm Primary and Secondary NICs are in the same subnet
    If ($PrimaryNVASubnet.Id -eq $SecondaryNVASubnet.Id) {
        # Store NICSet and Peering Subscription info
        $NICSets += $tmpNICSet
        foreach ($Peer in $Peerings){
            $peerSub = ($Peer.RemoteVirtualNetwork.Id.Split("/"))[2]
            If ($Subs -notcontains $peerSub) {
                $Subs += $peerSub
            }
        }
    }
    else {
        Write-Verbose "Subnet mismatch, moving to next set of NICs"
        continue
    }
}

# Iterate through each discovered Subscription and update all route tables
foreach ($Sub in $Subs){
    Select-AzureRmSubscription -Subscription $Sub | Out-Null
    Write-Verbose "Updating Route Tables in $((Get-AzureRMContext).Subscription.Name) Subscription"
    $RouteTables = Get-AzureRmRouteTable
    foreach ($RouteTable in $RouteTables) {
        Write-Verbose "$($RouteTable.Name) is being updated:"
        Foreach ($Route in $($RouteTable.Routes)){
            # Skipping any /32 routes
            If (($Route.AddressPrefix.Split("/"))[-1] -eq "32"){
                Write-Verbose "Skipping /32 Route: $($Route.Name)"
                continue
            }
            # Confirming we are only changing routes that are currently routing through one of the Primary Firewall's IPs
            else {
                foreach ($NICSet in $NICSets) {
                    if ($Route.NextHopIpAddress -eq $NICSet.PrimaryNVAIP) {
                        if ($PSCmdlet.ShouldProcess($Route.Name,"Update")){
                            Set-AzureRmRouteConfig -RouteTable $RouteTable -Name $Route.Name -AddressPrefix $Route.AddressPrefix -NextHopType $Route.NextHopType -NextHopIpAddress $NICSet.SecondaryNVAIP | Out-Null
                        }
                        Write-Verbose "$($Route.Name) Route NextHopIP switched to $($NICSet.SecondaryNVAIP)"
                        break
                    }
                }
            }
        }
        # Updating the Route Table with the changed routes
        if ($PSCmdlet.ShouldProcess($RouteTable.Name,"Update")){
            Set-AzureRmRouteTable -RouteTable $RouteTable | Out-Null
        }
        Write-Verbose "$($RouteTable.Name) Update Complete"
    }
}
Write-Verbose "Failover from $PrimaryNVAName to $SecondaryNVAName completed at $(Get-Date)"