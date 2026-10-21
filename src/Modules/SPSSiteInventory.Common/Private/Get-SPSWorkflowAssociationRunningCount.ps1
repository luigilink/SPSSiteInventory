function Get-SPSWorkflowAssociationRunningCount {
    [CmdletBinding()]
    [OutputType([System.Int32])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Object[]]
        $WorkflowAssociations = @()
    )

    $count = 0
    foreach ($association in @($WorkflowAssociations)) {
        if ($null -eq $association) { continue }

        $runningValue = $null
        foreach ($propertyName in @('RunningInstances', 'RunningInstancesCount', 'RunningInstanceCount', 'RunningCount')) {
            if ($null -ne $association.PSObject.Properties[$propertyName]) {
                $runningValue = $association.$propertyName
                break
            }
        }

        if ($null -eq $runningValue) { continue }

        if ($runningValue -is [System.Collections.IEnumerable] -and -not ($runningValue -is [string])) {
            $count += @($runningValue).Count
            continue
        }

        try {
            $count += [int]$runningValue
        }
        catch {
            continue
        }
    }

    return $count
}
