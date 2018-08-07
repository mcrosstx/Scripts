<#
    .SYNOPSIS
        This script is designed to create AAD security groups to be used for applying Azure RBAC permissions and assign permissions to them

    .DESCRIPTION
                
    
    .NOTES
        Author: Michael Cross
        Date: August 2018
        URL: 

        Assumptions/Requirements:
            Required Modules: Azure, AzureRM, MSOnline, AzureAD, Azure-Security-Center (not officially supported yet)
            Required Access: For some items (keys, passwords, etc) you will need at least Contributor access on the Azure subscription in question.
            
    
    .PARAMETER
        

    .PARAMETER
        

    .PARAMETER
        
    
    
#>


$groups = @("sysops","devops","secops","netops")

Connect-AzureAD -Credential (Get-Credential -Message "Enter your Azure AD Credentials")
Login-AzureRmAccount -Credential (Get-Credential -Message "Enter your Azure Credentials")


foreach ($group in $groups) {
    $temp = $null
    $temp = New-AzureADGroup -DisplayName $group -MailEnabled $false -MailNickName $group -SecurityEnabled $true
    $temp | select * | Out-GridView

}