<#
    .SYNOPSIS
        Updates any routes using one IP to another IP

    .NOTES
        Author: Michael Cross

    .PARAMETER fromIP
        IP currently in use to be changed away from

    .PARAMETER toIP
        IP to change to
#>

[cmdletbinding(SupportsShouldProcess=$True)]

param(
    [Parameter(Mandatory=$True)]
    [string]$fromIP,
    [Parameter(Mandatory=$True)]
    [string]$toIP
)

$Subs = (Get-AzureRmSubscription).Id

foreach ($Sub in $Subs){
    Set-AzureRmContext -Subscription $Sub | Out-Null
    Write-Verbose "Updating Route Tables in $((Get-AzureRMContext).Subscription.Name) Subscription"
    $RouteTables = Get-AzureRmRouteTable
    foreach ($RouteTable in $RouteTables) {
        #Write-Verbose "$($RouteTable.Name) is being updated:"
        Foreach ($Route in $($RouteTable.Routes)){
                    if ($Route.NextHopIpAddress -eq $fromIP) {
                        if ($PSCmdlet.ShouldProcess($Route.Name,"Update")){
                            Set-AzureRmRouteConfig -RouteTable $RouteTable -Name $Route.Name -AddressPrefix $Route.AddressPrefix -NextHopType $Route.NextHopType -NextHopIpAddress $toIP | Out-Null
                        }
                        Write-Verbose "$($Route.Name) Route NextHopIP switched $fromIP to $toIP"
                    }
        }
        # Updating the Route Table with the changed routes
        if ($PSCmdlet.ShouldProcess($RouteTable.Name,"Update")){
            Set-AzureRmRouteTable -RouteTable $RouteTable | Out-Null
        }
        Write-Verbose "$($RouteTable.Name) Update Complete"
    }
}