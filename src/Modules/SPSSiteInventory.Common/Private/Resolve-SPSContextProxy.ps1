function Resolve-SPSContextProxy {
    <#
        .SYNOPSIS
        Finds, among the proxies of one type in a proxy group, the one that a service context binds.

        .DESCRIPTION
        A proxy group can hold several service application proxies of the same type, and a service context
        binds one of them: the default proxy of the group for that type. The farm-level collectors identify a
        service by that proxy, so that two web applications whose groups hold the same proxies are not read
        twice, and a service is attributed to the proxy that was really read.

        A group with a single proxy of the type has nothing to resolve. Otherwise the default proxy comes from
        SPServiceContext.GetDefaultProxy, which is given the type of the proxies, and is matched by its ID with
        the proxies of the group. The function returns $null when the context has no default proxy of that
        type or when it is not one of the proxies given. A failure of the call is not caught: the caller
        marks its inventory incomplete.

        Private because it is an implementation detail of the collectors of the farm-level reports.

        .PARAMETER Candidate
        The proxies of one type in the proxy group, as the collectors build them: a Proxy (the SharePoint
        object), its Id (a GUID as text) and its Name.

        .PARAMETER ServiceContext
        The SPServiceContext of the proxy group.

        .EXAMPLE
        $bound = Resolve-SPSContextProxy -Candidate $candidates -ServiceContext $context
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object[]]
        $Candidate,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $ServiceContext
    )

    if ($Candidate.Count -eq 1) {
        return $Candidate[0]
    }

    $bound = $ServiceContext.GetDefaultProxy($Candidate[0].Proxy.GetType())
    if ($null -eq $bound) {
        return $null
    }
    $boundId = Get-SPSPropertyValue -InputObject $bound -Name 'Id'
    if ($null -eq $boundId) {
        return $null
    }
    foreach ($proxy in $Candidate) {
        if ([guid]$proxy.Id -eq [guid]$boundId) {
            return $proxy
        }
    }
    return $null
}
