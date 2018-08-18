<#
    .SYNOPSIS
        This script is designed to create AAD security groups to be used for applying Azure RBAC permissions and assign permissions to them

    .DESCRIPTION
        Takes an array of group names, checks to see if security groups by those names already exist and will create the groups if they do not.
    
    .NOTES
        Author: Michael Cross
        Date: August 2018
        URL: 

        Assumptions/Requirements:
            Required Modules: Azure, AzureRM, AzureAD
            Required Access: Global Admin or User Management Administrator in Office 365
            
    
    .PARAMETER
        

    .PARAMETER
        

    .PARAMETER
        
    
    
#>


#$groups = @("sysops","devops","secops","netops")

$groups = @(([PSCustomObject]@{
                groupname = "sysops"
                groupid = ""
                rolename = "Owner"
            }),([PSCustomObject]@{
                groupname = "devops"
                groupid = ""
                rolename = "Contributor"
            }),([PSCustomObject]@{
                groupname = "secops"
                groupid = ""
                rolename = "Security Admin"
            }),([PSCustomObject]@{
                groupname = "netops"
                groupid = ""
                rolename = "Network Contributor"
            }))


Connect-AzureAD -Credential (Get-Credential -Message "Enter your Azure AD Credentials")
Login-AzureRmAccount -Credential (Get-Credential -Message "Enter your Azure Credentials")


foreach ($group in $groups) {
    if ($group.groupname -match "dev") {
        $devflag = $true
    }
    else {
        $devflag = $false
    }
    
    if ( -not (Get-AzureADGroup | where {($_.DisplayName -eq $group.groupname) -and ($_.SecurityEnabled -eq $true)})) {
        New-AzureADGroup -DisplayName $group.groupname -MailEnabled $false -MailNickName $group.groupname -SecurityEnabled $true -ErrorAction Continue
        Write-Host $group.groupname "created" -ForegroundColor Green
    }
    else {
        Write-Host $group.groupname "already exists" -ForegroundColor Yellow
    }

    $group.groupid = (Get-AzureADGroup | where {($_.DisplayName -eq $group.groupname) -and ($_.SecurityEnabled -eq $true)}).ObjectID
    Write-Host $group.groupid
    
    $subscriptions = Get-AzureRmSubscription
    :sub foreach ($subscription in $subscriptions) {
        Select-AzureRmSubscription -Subscription $subscription | Out-Null
        Write-Host $subscription.Name
        $rg = Get-AzureRmResourceGroup -Name "RG-ScriptTest"
        
        if (!$devflag) {
            Write-host "Normal Permissions"
            New-AzureRmRoleAssignment -ObjectId $group.groupid -Scope $rg.ResourceId -RoleDefinitionName $group.rolename
        }
        else {
            If ($subscription.Name -match "Dev") {
                Write-Host "Development Permissions"
                New-AzureRmRoleAssignment -ObjectId $group.groupid -Scope $rg.ResourceId -RoleDefinitionName $group.rolename
            }
            else {
                Write-host "Continue Loop"
                continue sub
            }
        }
    } # foreach subscription
} # foreach group


Get-AzureRmRoleDefinition | select name,description | Out-GridView
