function Get-SPSNumericThreshold {
    [CmdletBinding()]
    [OutputType([System.Double])]
    param
    (
        [Parameter()]
        [System.Collections.IDictionary]
        $Thresholds = @{},

        [Parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [Parameter(Mandatory = $true)]
        [System.Double]
        $DefaultValue,

        [Parameter()]
        [System.Double]
        $MinimumValue = 0
    )

    if ($null -eq $Thresholds -or -not $Thresholds.Contains($Name) -or $null -eq $Thresholds[$Name]) {
        return $DefaultValue
    }

    try {
        $candidate = [double]$Thresholds[$Name]
        if ([double]::IsNaN($candidate) -or [double]::IsInfinity($candidate) -or $candidate -lt $MinimumValue) {
            return $DefaultValue
        }
        return $candidate
    }
    catch {
        return $DefaultValue
    }
}
