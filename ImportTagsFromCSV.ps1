
#Function to Select file from Dialog box
Function Get-FileName($initialDirectory)
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "CSV (*.csv)| *.csv"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.FileName
}

#Get the File
$inputFile = (Get-FileName ([Environment]::GetFolderPath("Desktop")))

#Import the CSV
$csv = Import-Csv -Path $inputFile | foreach {
    
    #Get relevant fields
    $s = $_.SubscriptionId
    $rgn = $_.ResourceGroupName
    $rn = $_.Name
    $tag = $_.MissingTag
    $value = $_.Value
    $hash = @{
            $tag = $value
        }
#}
    #Set Context and Find the specified Resource
    Set-AzureRmContext -Subscription $s | Out-Null
    $resource = Get-AzureRMResource -ResourceGroupName $rgn -ResourceName $rn
    $resourcetags = $resource.Tags
    
    # If Value is empty, do nothing
    if ($value) {
        # Check for tags
        if ($resourcetags) {
            #If Tag is missing, add it to existing tags
            if (-not($resourcetags.ContainsKey($tag))){
                $resourcetags.Add($tag, $value)
            }
            #If Tag's value doesn't match, update it
            elseif (-not($resourcetags[$tag] -eq $value)) {
                $resourcetags[$tag] = $value
            }
        }
        else {
            #If there are no tags, add the tag
            $resourcetags = $hash
        }
        #Set the Resource's Tags
        Set-AzureRmResource -Tag $resourcetags -ResourceId $resource.ResourceId
    }
}