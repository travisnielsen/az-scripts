$config = Get-Content "config.json" | ConvertFrom-Json
$currentTime = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
$fileLocation = $config.outputFileLocation + "adf-integrationruntimes-$($config.region)-$($currentTime).csv"
$startTime = Get-Date

Connect-AzAccount -Tenant $config.tenantId
$subscriptions = Get-AzSubscription
$vmRecords = New-Object System.Collections.Generic.List[Object]
$subscriptionRecords = New-Object System.Collections.Generic.List[Object]

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
                    # check if node is in the $vmRecords list
                    $vmRecord = $vmRecords | Where-Object { $_.NodeMachineName -eq $node.MachineName } | Select-Object -First 1
                    $vmSubscriptionId = ""
                    $vmZoneLogical = ""
                    $vmZonePhysical = ""
                    $vmLocation = ""
                    $vmResourceId = ""
                    $vmResourceGroup = ""
                    $vmSku = ""
                    $vmTags = ""

                    if ($vmRecord) {
                        Write-Host "Node already exists in records" -ForegroundColor Yellow
                        $vmSubscriptionId = $vmRecord.VMSubscriptionId
                        $vmLocation = $vmRecord.VMLocation
                        $vmZoneLogical = $vmRecord.VMZoneLogical
                        $vmZonePhysical = $vmRecord.VMZonePhysical
                        $vmResourceId = $vmRecord.VMResourceId
                        $vmResourceGroup = $vmRecord.VMResourceGroup
                        $vmSku = $vmRecord.VMSku
                        $vmTags = $vmRecord.VMTags
                    }
                    else {
                        # $vmData = Get-AzVM -Name $node.MachineName
                        $vmData = Search-AzGraph -Query "Resources | where type =~ 'Microsoft.Compute/virtualMachines' | where name =~ '$($node.MachineName)' | project subscriptionId, location, zones, id, resourceGroup, properties.hardwareProfile.vmSize, tags" | Select-Object -First 1
                        $vmLocation = $vmData.location
                        $vmSubscriptionId = $vmData.subscriptionId
                        $vmZoneLogical = $vmData.zones.Count -gt 0 ? $vmData.zones[0] : "N/A"
                        $vmResourceId = $vmData.id
                        $vmResourceGroup = $vmData.resourceGroup
                        $vmSku = $vmData.properties_hardwareProfile_vmSize
                        # $vmTags = $vmData.tags | ConvertTo-Json -Compress
                        $vmTags = $vmData.tags
                    }

                    # get subscription info so that the logical zone peering can be checked
                    $subscriptionData = $subscriptionRecords | Where-Object { $_.SubscriptionId -eq $vmSubscriptionId } | Select-Object -First 1

                    if (!$subscriptionData) {
                        Write-Host "Looking up zone mapping data for subscription: $vmSubscriptionId" -ForegroundColor Yellow
                        $azMappingResponse = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$($vmSubscriptionId)/locations?api-version=2022-12-01"
                        $azMappingContent = $azMappingResponse.Content
                        $azMappingData = ($azMappingContent | ConvertFrom-Json).Value
                        $azMappingDataFiltered = ($azMappingData| Where-Object {$_.Name -eq $config.region}) | Select-Object -First 1
                        $azMappings = $azMappingDataFiltered.availabilityZoneMappings

                        $zoneMappings = @{}
                        foreach ($mapping in $azMappings) {
                            $zoneMappings[$mapping.logicalZone] = $mapping.physicalZone
                        }

                        $newSubscriptionData = [PSCustomObject]@{
                            SubscriptionId = $vmSubscriptionId
                            ZoneMappings = $zoneMappings
                        }

                        $vmZonePhysical = $zoneMappings[$vmZoneLogical.ToString()]
                        $subscriptionRecords.Add($newSubscriptionData)
                    }
                    else {
                        $vmZonePhysical = $subscriptionData.ZoneMappings[$vmZoneLogical.ToString()]
                    }

                    $newVmRecord = [PSCustomObject]@{
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
                        VMSubscriptionId = $vmSubscriptionId
                        VMZoneLogical = $vmZoneLogical
                        VMZonePhysical = $vmZonePhysical
                        VMLocation = $vmLocation
                        VMResourceId = $vmResourceId
                        VMResourceGroup = $vmResourceGroup
                        VMSku = $vmSku
                        VMTags = $vmTags
                    }

                    $vmRecords.Add($newVmRecord)

                    # save results to file
                    if ($vmRecords.Count -eq 1) {
                        $newVmRecord | Export-Csv -Path $fileLocation -NoTypeInformation
                    }
                    else {
                        $newVmRecord | Export-Csv -Path $fileLocation -NoTypeInformation -Append
                    }
                }
            }
        }
    }
}

$endTime = Get-Date
Write-Host "====================" -ForegroundColor Green
Write-Host "Script completed in: $(($endTime - $startTime).TotalMinutes) minutes" -ForegroundColor Green