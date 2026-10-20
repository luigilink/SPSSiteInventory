function Get-SPSWorkflowSubscriptionCount {
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

    $subscriptions = $workflowManager.GetWorkflowSubscriptionService().EnumerateSubscriptions()
    return @($subscriptions).Count
}
