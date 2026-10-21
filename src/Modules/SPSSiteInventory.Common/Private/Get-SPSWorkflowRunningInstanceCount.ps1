function Get-SPSWorkflowRunningInstanceCount {
    [CmdletBinding()]
    [OutputType([System.Nullable[int]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Web,

        [Parameter()]
        [AllowNull()]
        [System.Object]
        $WorkflowManager = $null
    )

    $workflowManager = $WorkflowManager
    if ($null -eq $workflowManager) {
        try {
            $workflowManager = [Microsoft.SharePoint.WorkflowServices.WorkflowServicesManager]::new($Web)
        }
        catch {
            Write-Verbose -Message "Workflow Manager is unavailable on web '$($Web.Url)': $($_.Exception.Message)"
            return $null
        }
    }

    $isConnected = [bool]$workflowManager.IsConnected

    if (-not $isConnected) {
        return $null
    }

    $subscriptionService = $workflowManager.GetWorkflowSubscriptionService()
    $instanceService = $workflowManager.GetWorkflowInstanceService()
    if ($null -eq $subscriptionService -or $null -eq $instanceService) {
        return $null
    }

    $subscriptions = @($subscriptionService.EnumerateSubscriptions())
    if ($subscriptions.Count -eq 0) {
        return 0
    }

    $canEnumerateBySubscription = $null -ne $instanceService.PSObject.Methods['Enumerate']
    $canEnumerateBySubscriptionId = $null -ne $instanceService.PSObject.Methods['EnumerateInstancesForSubscription']
    if (-not $canEnumerateBySubscription -and -not $canEnumerateBySubscriptionId) {
        return $null
    }

    $allInstances = @()
    foreach ($subscription in $subscriptions) {
        if ($null -eq $subscription) {
            continue
        }

        $subscriptionInstances = $null
        $usedSubscriptionMethod = $false

        if ($canEnumerateBySubscription) {
            try {
                $subscriptionInstances = @($instanceService.Enumerate($subscription))
                $usedSubscriptionMethod = $true
            }
            catch {
                if (-not $canEnumerateBySubscriptionId) {
                    throw
                }
            }
        }

        if (-not $usedSubscriptionMethod -and $canEnumerateBySubscriptionId) {
            if ($null -ne $subscription.PSObject.Properties['Id'] -and $null -ne $subscription.Id) {
                $subscriptionInstances = @($instanceService.EnumerateInstancesForSubscription($subscription.Id))
            }
            else {
                $subscriptionInstances = @($instanceService.EnumerateInstancesForSubscription($subscription))
            }
            $usedSubscriptionMethod = $true
        }

        if (-not $usedSubscriptionMethod) {
            return $null
        }

        $allInstances += @($subscriptionInstances)
    }

    $activeStatuses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($status in @('Started', 'Running', 'Suspended', 'Suspending', 'CancelRequested', 'Canceling')) {
        [void]$activeStatuses.Add($status)
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

        if ($activeStatuses.Contains($statusText.Trim())) {
            $runningCount++
        }
    }

    return $runningCount
}
