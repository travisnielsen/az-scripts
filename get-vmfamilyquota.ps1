$config = Get-Content "config.json" | ConvertFrom-Json
$currentTime = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
$fileLocation = $config.outputFileLocation + "quota-$($config.region)-$($currentTime).csv"

Connect-AzAccount -Tenant $config.tenantId
$subscriptions = Get-AzSubscription

$vmNameDict = @{}
$vmNameDict["Standard DADSv5 Family vCPUs"] = "Standard_Dads_v5"
$vmNameDict["Standard DASv5 Family vCPUs"] = "Standard_Das_v5"
$vmNameDict["Standard DAv4 Family vCPUs"] = "Standard_Da_v4"
$vmNameDict["Standard DDSv4 Family vCPUs"] = "Standard_Dds_v4"
$vmNameDict["Standard DDSv5 Family vCPUs"] = "Standard_Dds_v5"
$vmNameDict["Standard DSv2 Family vCPUs"] = "Standard_Ds_v2"
$vmNameDict["Standard DSv3 Family vCPUs"] = "Standard_Ds_v3"
$vmNameDict["Standard DSv5 Family vCPUs"] = "Standard_Ds_v5"
$vmNameDict["Standard Dv2 Family vCPUs"] = "Standard_D_v2"
$vmNameDict["Standard Dv3 Family vCPUs"] = "Standard_D_v3"
$vmNameDict["Standard EASv4 Family vCPUs"] = "Standard_Eas_v4"
$vmNameDict["Standard EDSv4 Family vCPUs"] = "Standard_Eds_v4"
$vmNameDict["Standard EDSv5 Family vCPUs"] = "Standard_Eds_v5"
$vmNameDict["Standard EDv4 Family vCPUs"] = "Standard_Ed_v4"
$vmNameDict["Standard ESv3 Family vCPUs"] = "Standard_Es_v3"
$vmNameDict["Standard ESv4 Family vCPUs"] = "Standard_Es_v4"
$vmNameDict["Standard ESv5 Family vCPUs"] = "Standard_Es_v5"
$vmNameDict["Standard Ev3 Family vCPUs"] = "Standard_E_v3"
$vmNameDict["Standard F Family vCPUs"] = "Standard_F"
$vmNameDict["Standard FSv2 Family vCPUs"] = "Standard_Fs_v2"
$vmNameDict["Standard LSv2 Family vCPUs"] = "Standard_Ls_v2"
$vmNameDict["Standard LSv3 Family vCPUs"] = "Standard_Ls_v3"
$vmNameDict["Standard NDASv4 Family vCPUs"] = "Standard_Ndas_v4"
$vmNameDict["Standard NCSv3 Family vCPUs"] = "Standard_NCs_v3"

$records = New-Object System.Collections.Generic.List[Object]

foreach ($subscription in $subscriptions) {
    Set-AzContext -Subscription $subscription.Id -Tenant $config.tenantId

    $quotaInfo = Get-AzVmUsage -Location $config.region | Where-Object {
        $vmNameDict.ContainsKey($_.Name.LocalizedValue)
    }

    $quotaInfo | ForEach-Object {
        $vmFamily = $vmNameDict[$_.Name.LocalizedValue]

        if ($vmFamily) {
            $vmQuota = $_.Limit
            $vmUsed = $_.CurrentValue
            $vmAvailable = $_.Limit - $_.CurrentValue

            $record = [PSCustomObject]@{
                SubscriptionId = $subscription.Id
                SubscriptionName = $subscription.Name
                Region = $config.region
                VMFamily = $vmFamily
                VMQuota = $vmQuota
                VMUsed = $vmUsed
                VMsAvailable = $vmAvailable
            }

            Write-Host $record.ToString()
    
            $records.Add($record)
        }
    }
}

$records | Export-Csv -Path $fileLocation -Append -NoTypeInformation