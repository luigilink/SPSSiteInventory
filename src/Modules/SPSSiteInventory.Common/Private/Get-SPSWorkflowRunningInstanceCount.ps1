function Get-SPSWorkflowRunningInstanceCount {
    [CmdletBinding()]
    [OutputType([System.Nullable[int]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Web
    )

    try {
        $workflowManager = [Microsoft.SharePoint.WorkflowServices.WorkflowServicesManager]::new($Web)
        $isConnected = [bool]$workflowManager.IsConnected
    }
    catch {
        Write-Verbose -Message "Workflow Manager is unavailable on web '$($Web.Url)': $($_.Exception.Message)"
        return $null
    }

    if (-not $isConnected) {
        return $null
    }

    $instanceService = $workflowManager.GetWorkflowInstanceService()
    if ($null -eq $instanceService) {
        return $null
    }

    $allInstances = @()
    if ($null -ne $instanceService.PSObject.Methods['Enumerate']) {
        $allInstances = @($instanceService.Enumerate())
    }
    elseif ($null -ne $instanceService.PSObject.Methods['EnumerateInstancesForWeb']) {
        $allInstances = @($instanceService.EnumerateInstancesForWeb($Web.ID))
    }
    elseif ($null -ne $instanceService.PSObject.Methods['EnumerateInstancesForSite'] -and
        $null -ne $Web.PSObject.Properties['Site'] -and $null -ne $Web.Site) {
        $allInstances = @($instanceService.EnumerateInstancesForSite($Web.Site.ID))
    }
    else {
        return $null
    }

    $runningCount = 0
    foreach ($instance in $allInstances) {
        if ($null -eq $instance) { continue }

        $statusText = ''
        if ($null -ne $instance.PSObject.Properties['Status'] -and $null -ne $instance.Status) {
            $statusText = [string]$instance.Status
        }
        elseif ($null -ne $instance.PSObject.Properties['InstanceStatus'] -and $null -ne $instance.InstanceStatus) {
            $statusText = [string]$instance.InstanceStatus
        }

        if ([string]::IsNullOrWhiteSpace($statusText)) {
            continue
        }

        if ($statusText -match 'Started|Running|Suspend|CancelRequested') {
            $runningCount++
        }
    }

    return $runningCount
}
