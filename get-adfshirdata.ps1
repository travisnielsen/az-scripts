$config = Get-Content "config.json" | ConvertFrom-Json
$currentTime = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
$fileLocation = $config.outputFileLocation + "adf-integrationruntimes-$($config.region)-$($currentTime).csv"
$startTime = Get-Date

Connect-AzAccount -Tenant $config.tenantId
$subscriptions = Get-AzSubscription
$records = New-Object System.Collections.Generic.List[Object]

foreach ($subscription in $subscriptions) {
    Set-AzContext -Subscription $subscription.Id -Tenant $config.tenantId

    $dataFactories = Get-AzDataFactoryV2 | Where-Object { $_.Location -eq $config.region }

    foreach ($dataFactory in $dataFactories) {
        Write-Host "Processing Data Factory: $($dataFactory.DataFactoryName)" -ForegroundColor Green
        $integrationRuntimes = Get-AzDataFactoryV2IntegrationRuntime -DataFactoryName $dataFactory.DataFactoryName -ResourceGroupName $dataFactory.ResourceGroupName

        foreach ($ir in $integrationRuntimes) {
            if ($ir.Type -eq "SelfHosted") {
                Write-Host "Processing Integration Runtime: $($ir.Name)" -ForegroundColor Cyan
                $irDetails = Get-AzDataFactoryV2IntegrationRuntime -DataFactoryName $dataFactory.DataFactoryName -ResourceGroupName $dataFactory.ResourceGroupName -Name $ir.Name -Status -ErrorAction SilentlyContinue

                foreach ($node in $irDetails.Nodes) {

                    Write-Host "Processing Node: $($node.MachineName)" -ForegroundColor Blue
                    # check if node is in the $records list
                    $vmRecord = $records | Where-Object { $_.NodeMachineName -eq $node.MachineName } | Select-Object -First 1
                    $vmZone = ""
                    $vmLocation = ""
                    $vmResourceId = ""
                    $vmResourceGroup = ""
                    $vmSku = ""
                    $vmTags = ""

                    if ($vmRecord) {
                        Write-Host "Node already exists in records" -ForegroundColor Yellow
                        $vmLocation = $vmRecord.VMLocation
                        $vmZone = $vmRecord.VMZone
                        $vmResourceId = $vmRecord.VMResourceId
                        $vmResourceGroup = $vmRecord.VMResourceGroup
                        $vmSku = $vmRecord.VMSku
                        $vmTags = $vmRecord.VMTags
                    }
                    else {
                        # $vmData = Get-AzVM -Name $node.MachineName
                        $vmData = Search-AzGraph -Query "Resources | where type =~ 'Microsoft.Compute/virtualMachines' | where name =~ '$($node.MachineName)' | project location, zones, id, resourceGroup, properties.hardwareProfile.vmSize, tags" | Select-Object -First 1
                        $vmLocation = $vmData.location
                        $vmZone = $vmData.zones.Count -gt 0 ? $vmData.zones[0] : "N/A"
                        $vmResourceId = $vmData.id
                        $vmResourceGroup = $vmData.resourceGroup
                        $vmSku = $vmData.properties_hardwareProfile_vmSize
                        # $vmTags = $vmData.tags | ConvertTo-Json -Compress
                        $vmTags = $vmData.tags
                    }

                    $record = [PSCustomObject]@{
                        SubscriptionId = $subscription.Id
                        SubscriptionName = $subscription.Name
                        DataFactoryName = $dataFactory.DataFactoryName
                        ResourceGroupName = $dataFactory.ResourceGroupName
                        IRName = $ir.Name
                        NodeMachineName = $node.MachineName
                        NodeStatus = $node.State
                        NodeLastConnectTime = $node.LastConnectTime
                        NodeLastUpdateResult = $node.LastUpdateResult
                        NodeVersion = $node.Version
                        NodeVersionStatus = $node.VersionStatus
                        NodeMaxConcurrentJobs = $node.MaxConcurrentJobs
                        VMZone = $vmZone
                        VMLocation = $vmLocation
                        VMResourceId = $vmResourceId
                        VMResourceGroup = $vmResourceGroup
                        VMSku = $vmSku
                        VMTags = $vmTags
                    }

                    $records.Add($record)

                    # save results to file
                    if ($records.Count -eq 1) {
                        $record | Export-Csv -Path $fileLocation -NoTypeInformation
                    }
                    else {
                        $record | Export-Csv -Path $fileLocation -NoTypeInformation -Append
                    }
                }
            }
        }
    }
}

$endTime = Get-Date
Write-Host "====================" -ForegroundColor Green
Write-Host "Script completed in: $(($endTime - $startTime).TotalMinutes) minutes" -ForegroundColor Green