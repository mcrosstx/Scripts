$groups = Get-AzureRmResourceGroup
foreach($Group in $groups){
    #If Resource Group has tags find Resource Group Members
    if ($group.Tags -ne $null) {
        $resources = Find-AzureRmResource -ResourceGroupName $group.ResourceGroupName
        #For each resource check if tags are already applied, if yes, add addittional tags, if no, apply only Resource Group tags.
        foreach ($r in $resources){
            $resourcetags = (Get-AzureRmResource -ResourceId $r.ResourceId).Tags
            if ($resourcetags){
                foreach ($key in $group.Tags.Keys){
                    if (-not($resourcetags.ContainsKey($key))){
                        $resourcetags.Add($key, $group.Tags[$key])
                    }
                }
                Write-Host "`nSetting the below tags on "$r.name":"
                Write-Output $resourcetags
                Set-AzureRmResource -Tag $resourcetags -ResourceId $r.ResourceId -Force | Out-Null
            }
            else{
                Write-Host "`nSetting below Resource Group Tags on "$r.name":"
                Write-output $group.tags
                Set-AzureRmResource -Tag $group.Tags -ResourceId $r.ResourceId -Force | Out-Null
            }
        }
    }
}