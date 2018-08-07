<#
    .SYNOPSIS
        This script is designed to review and Azure subscription and check for recommended security settings.

    .DESCRIPTION
        Original Checklist can be found here:
            https://goplanet.sharepoint.com/:x:/r/sites/em/ECR/Azure_ECR_CoreFoundationHardening-Checklist.xlsx?d=wdae803851f8c4574af05811f51d2c5c0&csf=1&e=FwThU1

        Checklist was developed by Travis Moore based off of the Center for Internet Security benchmarks for Microsoft Azure. https://www.cisecurity.org/cybersecurity-best-practices/ 


        
    
    .NOTES
        Author: Michael Cross
        Date: July 2018
        URL: 

        Assumptions/Requirements:
            Required Modules: Azure, AzureRM, MSOnline, AzureAD, Azure-Security-Center (not officially supported yet)
            Required Access: For some items (keys, passwords, etc) you will need at least Contributor access on the Azure subscription in question.
            
    
    .PARAMETER Environment
        

    .PARAMETER
        

    .PARAMETER
        
    
    
#>

param(
    [Parameter(Mandatory=$True)][ValidateSet("AzureChinaCloud","AzureCloud","AzureGermanCloud","AzureUSGovernment")]
    [string]$Environment,
    [Parameter(Mandatory=$True)]
    [string]$param2,
    [Parameter(Mandatory=$True)]
    [string]$param3
)


#Requires -Module Azure,AzureRM,MSOnline,AzureAD,Azure-Security-Center

# Get Credentials and login to Azure and AzureAD/O365
Write-Host "Gathering Credentials..." -ForegroundColor Green
$Credential = Get-Credential -Message "Please enter your Azure Credentials"

Login-AzureRmAccount -Environment $Environment -Credential $Credential
Connect-MsolService -Credential $Credential
Connect-AzureAD -Credential $Credential

# Begin Identity and Access Management Phase
Write-Host "Beginning Identity and Access Management Phase..." -ForegroundColor Green

$users = Get-MsolUser -All
$usersAD = Get-AzureADUser -All $true

$users.Count
$usersAD.Count

$users | where {$_. }

foreach ($u in $usersAD) {
    write-host $u.UserType
}

$usersAD[0]


Function Get-ARMBearerToken {
    Param(
    
        [Parameter(Mandatory=$true)]
        [string]$ClientID,

        [Parameter(Mandatory=$true)]
        [string]$ClientSecret,

        [Parameter(Mandatory=$true)]
        [string]$TenantID

    )

    $ARMResource = "https://management.azure.com/" 
    $Body = @{
        client_id = $ClientID;
        client_secret = $ClientSecret;
        grant_type = 'client_credentials';
        resource = $ARMResource
    }

    $URI = 'https://login.microsoftonline.com/' + $TenantID + '/oauth2/token'
    $Token = Invoke-RestMethod -Uri $URI -Method Post -Body $Body -ContentType "application/x-www-form-urlencoded"
    return $Token.access_token

}


Function Get-ARMResource {
    Param(
    
        [Parameter(Mandatory=$true)]
        [string]$ResourceID,

        [Parameter(Mandatory=$true)]
        [string]$BearerToken

    )

    $ARMRESTUriPrefix = "https://management.azure.com"
    $Header = @{ 
        "Authorization" = "Bearer $BearerToken"
        “Accept” = “application/json”
    }
    return Invoke-RestMethod -Uri ($ARMRESTURIPrefix + $ResourceID +"?api-version=2014-04-01") -Method Get -Headers $Header
}

GET https://management.azure.com/subscriptions/8ee2aaf4-8329-4aa2-afa2-21cda345f7d4/providers/Microsoft.Authorization/roleDefinitions?api-version=2017-05-01