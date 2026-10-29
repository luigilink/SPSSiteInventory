function Get-SPSExpandedPackageInfo {
    <#
        .SYNOPSIS
        Reads the manifest, the features and the assemblies of a WSP that is expanded in a folder.

        .DESCRIPTION
        A WSP is a cabinet that holds manifest.xml, the files of its features and its assemblies.
        Once it is expanded, this function reads what a farm solution only shows as booleans:

        - manifest.xml: the solution id, the deployment type, the assemblies and where they are
          deployed (global assembly cache or web application), the safe controls, the code access
          security policy, and the number of template files, root files, web part files and site
          definitions;
        - every feature manifest the solution lists, even when the solution is not deployed: the
          feature id, the scope, the title and the receiver of the feature, and the kind of elements
          that its element manifests provision (fields, content types, modules, receivers...);
        - every DLL of the package, read as bytes and never loaded (see Get-SPSAssemblyFileInfo): the
          strong name, the public key token and the framework it was built for.

        An assembly is Microsoft when its public key token is one of the tokens that Microsoft signs
        with AND its strong-name signature is valid, and custom otherwise (an assembly that is not
        signed is custom); a satellite assembly (a culture) holds resources only and is not counted.
        That is a classification on the key of the assembly, not on the name of the solution. The
        token alone proves nothing: it is a hash of the public key that the assembly declares, and an
        assembly that is delay-signed with the public key of Microsoft, or altered after it was signed,
        carries it as well. Such an assembly is custom, and the package says so in Problems.

        The function reads what it can: a part that cannot be read (a missing feature manifest, a DLL
        that is not an assembly) is reported in Problems, and the rest is still returned. A DLL that
        was not assessed (above the size limit, not a valid image, a name that could not be read) is
        reported in Problems too, and counts as custom, because nothing shows that it is Microsoft's.
        It throws when the folder has no readable manifest.xml.

        The package is not trusted. A location in a manifest, a DLL that is found in a folder and
        manifest.xml itself must stay in the package, and a symbolic link or a junction is never
        followed (see Resolve-SPSPackagePath and Get-SPSPackageFile).

        Private because it is an implementation detail of Get-SPSSolutionPackageInfo.

        .PARAMETER Root
        The folder that holds the expanded package (manifest.xml is at its root).

        .PARAMETER MicrosoftPublicKeyToken
        The public key tokens that count as Microsoft.

        .PARAMETER MaximumMegabyte
        The size above which a DLL is not read. Defaults to 256.

        .OUTPUTS
        An object with the content of the package: SolutionId, SharePointProductVersion,
        DeploymentServerType, ResetWebServer, Assemblies, Features, the counts and the flags that
        Get-SPSSolutionPackageInfo reports, and Problems.

        .EXAMPLE
        Get-SPSExpandedPackageInfo -Root $folder -MicrosoftPublicKeyToken @('71e9bce111e9429c')
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Root,

        [Parameter()]
        [System.String[]]
        $MicrosoftPublicKeyToken = @(),

        [Parameter()]
        [ValidateRange(1, 4096)]
        [System.Int32]
        $MaximumMegabyte = 256
    )

    $dllLimit = $MaximumMegabyte
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd($separator, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    $problem = [System.Collections.Generic.List[string]]::new()
    $token = @($MicrosoftPublicKeyToken | Where-Object { -not [System.String]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() })

    # A location in a manifest comes from a file that is not trusted: it must stay in the package, and must not go through a link.
    $resolveInside = {
        param ([System.String] $Base, [System.String] $Location)
        return (Resolve-SPSPackagePath -Root $Root -Base $Base -Location $Location)
    }
    $normalizeGuid = {
        param ([System.String] $Text)
        $parsed = [System.Guid]::Empty
        if ([System.Guid]::TryParse(([System.String]$Text).Trim(), [ref]$parsed)) {
            return $parsed.ToString()
        }
        return ([System.String]$Text).Trim().ToLowerInvariant()
    }
    $isTrue = {
        param ([System.String] $Text)
        return ([System.String]$Text).Trim() -ieq 'true'
    }

    $manifestFile = @(Get-ChildItem -LiteralPath $Root -File -Force | Where-Object { $_.Name -ieq 'manifest.xml' }) | Select-Object -First 1
    if ($null -eq $manifestFile) {
        throw 'The package has no manifest.xml.'
    }
    if (Test-SPSFileSystemLink -Item $manifestFile) {
        throw 'manifest.xml is a link (a symbolic link or a junction), which is not followed.'
    }
    try {
        $manifest = Read-SPSPackageXml -Path $manifestFile.FullName
    }
    catch {
        throw "manifest.xml could not be read: $($_.Exception.Message)"
    }
    $solution = $manifest.DocumentElement
    if ($solution.LocalName -ne 'Solution') {
        throw "manifest.xml is not a solution manifest (its root element is '$($solution.LocalName)')."
    }

    $count = {
        param ([System.String] $Group, [System.String] $Item)
        return @($manifest.SelectNodes("/*[local-name()='Solution']/*[local-name()='$Group']/*[local-name()='$Item']")).Count
    }

    # The assemblies of the manifest, and then the other DLLs of the package.
    $assembly = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $addAssembly = {
        param ([System.String] $Location, [System.String] $Target, $Resolved, [System.Int32] $SafeControl)
        $status = 'Read'
        $detail = ''
        $file = $null
        if ($null -eq $Resolved.Path) {
            $status = if ($Resolved.Problem -eq 'Link') { 'Link' } else { 'Outside' }
            $detail = $Resolved.Detail
        }
        elseif (-not (Test-Path -LiteralPath $Resolved.Path -PathType Leaf)) {
            $status = 'Missing'
            $detail = 'The file is not in the package.'
        }
        else {
            $file = Get-SPSAssemblyFileInfo -Path $Resolved.Path -MaximumMegabyte $dllLimit
            $detail = $file.Detail
            # A genuine native DLL is a normal case. A DLL that was skipped or could not be read was not assessed.
            $status = switch ($file.ReadStatus) {
                'Read' { 'Read' }
                'Partial' { 'Partial' }
                'Native' { 'NotManaged' }
                'Skipped' { 'Skipped' }
                default { 'Failed' }
            }
        }
        $managed = ($null -ne $file -and $file.IsManaged)
        $tokenValue = if ($null -ne $file) { $file.PublicKeyToken } else { '' }
        $culture = if ($null -ne $file) { $file.Culture } else { '' }
        $signature = if ($null -ne $file) { $file.SignatureStatus } else { '' }
        $hasMicrosoftToken = ($tokenValue.Length -gt 0 -and $token -contains $tokenValue)
        # The token is only a hash of the key that the assembly declares: it counts when the signature is valid.
        $isMicrosoft = ($hasMicrosoftToken -and $signature -eq 'Valid')
        $isSatellite = ($managed -and $culture.Length -gt 0)
        $runtime = if ($managed) { $file.RuntimeVersion } else { '' }
        $framework = if ($managed) { $file.TargetFramework } else { '' }
        $legacy = $false
        if ($managed) {
            $legacy = ($runtime -match '^v[0-3]\.')
            if ($framework -match '^\.NETFramework,Version=v([0-9]+)\.' -and [System.Int32]$Matches[1] -lt 4) {
                $legacy = $true
            }
        }
        $assembly.Add([PSCustomObject]@{
                Location                = $Location
                DeploymentTarget        = $Target
                Status                  = $status
                Detail                  = $detail
                Name                    = if ($null -ne $file) { $file.Name } else { '' }
                Version                 = if ($null -ne $file) { $file.Version } else { '' }
                Culture                 = $culture
                PublicKeyToken          = $tokenValue
                IsSigned                = ($tokenValue.Length -gt 0)
                SignatureStatus         = $signature
                HasMicrosoftToken       = $hasMicrosoftToken
                IsManaged               = $managed
                IsMicrosoft             = $isMicrosoft
                IsSatellite             = $isSatellite
                IsCustom                = ($null -ne $file -and -not $isMicrosoft -and -not $isSatellite)
                RuntimeVersion          = $runtime
                TargetFramework         = $framework
                Architecture            = if ($managed) { $file.Architecture } else { '' }
                BuiltForLegacyFramework = $legacy
                SafeControlCount        = $SafeControl
            })
        if ($status -in @('Outside', 'Link', 'Missing', 'Partial', 'Skipped', 'Failed')) {
            $problem.Add("Assembly '$Location': $detail")
        }
        if ($hasMicrosoftToken -and -not $isMicrosoft -and -not $isSatellite -and $managed) {
            $problem.Add("Assembly '$Location' has the public key token of a Microsoft key ($tokenValue) but is not signed with it ($signature), so it counts as custom: $($file.SignatureDetail)")
        }
    }

    $assemblyNode = @($manifest.SelectNodes("/*[local-name()='Solution']/*[local-name()='Assemblies']/*[local-name()='Assembly']"))
    $safeControlCount = 0
    foreach ($node in $assemblyNode) {
        $location = $node.GetAttribute('Location')
        $target = $node.GetAttribute('DeploymentTarget')
        if ([System.String]::IsNullOrEmpty($target)) {
            $target = 'GlobalAssemblyCache'
        }
        $safe = @($node.SelectNodes("./*[local-name()='SafeControls']/*[local-name()='SafeControl']")).Count
        $safeControlCount += $safe
        $resolved = & $resolveInside $Root $location
        if ($null -ne $resolved.Path) {
            $null = $seen.Add($resolved.Path)
        }
        & $addAssembly $location $target $resolved $safe
    }

    # Every file is listed, the hidden ones too, and a link is left alone: it can lead anywhere.
    $package = Get-SPSPackageFile -Root $Root
    if ($package.Link.Count -gt 0) {
        $shown = @($package.Link | Select-Object -First 3 | ForEach-Object { $_.Substring($rootFull.Length) -replace '[\\/]', '\' })
        $problem.Add("The package has $($package.Link.Count) link(s) (symbolic links or junctions), which are not followed: $($shown -join ', ')$(if ($package.Link.Count -gt 3) { ', ...' }).")
    }
    foreach ($dll in @($package.File | Where-Object { $_.Extension -ieq '.dll' } | Sort-Object -Property FullName)) {
        if ($seen.Contains($dll.FullName)) {
            continue
        }
        $relative = $dll.FullName.Substring($rootFull.Length) -replace '[\\/]', '\'
        & $addAssembly $relative 'Other' ([PSCustomObject]@{ Path = $dll.FullName; Problem = ''; Detail = '' }) 0
    }

    # The features of the manifest, read from their own files.
    $feature = [System.Collections.Generic.List[object]]::new()
    $element = @{}
    $featureNode = @($manifest.SelectNodes("/*[local-name()='Solution']/*[local-name()='FeatureManifests']/*[local-name()='FeatureManifest']"))
    foreach ($node in $featureNode) {
        $location = $node.GetAttribute('Location')
        $record = [ordered]@{
            Location           = $location
            Status             = 'Read'
            Id                 = ''
            Scope              = ''
            Title              = ''
            Version            = ''
            Hidden             = $false
            ActivateOnDefault  = $false
            AlwaysForceInstall = $false
            ReceiverAssembly   = ''
            ReceiverClass      = ''
            Receiver           = @()
        }
        $resolved = & $resolveInside $Root $location
        $full = $resolved.Path
        if ($null -eq $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
            $record['Status'] = 'Missing'
            $reason = if ($resolved.Problem -eq 'Link') { 'goes through a link, which is not followed' } else { 'is not in the package' }
            $problem.Add("Feature manifest '$location' $reason.")
            $feature.Add([PSCustomObject]$record)
            continue
        }
        try {
            $featureDocument = Read-SPSPackageXml -Path $full
            $featureRoot = $featureDocument.DocumentElement
            if ($featureRoot.LocalName -ne 'Feature') {
                throw "its root element is '$($featureRoot.LocalName)', not Feature."
            }
        }
        catch {
            $record['Status'] = 'Unreadable'
            $problem.Add("Feature manifest '$location' could not be read: $($_.Exception.Message)")
            $feature.Add([PSCustomObject]$record)
            continue
        }

        $record['Id'] = & $normalizeGuid $featureRoot.GetAttribute('Id')
        $record['Scope'] = $featureRoot.GetAttribute('Scope')
        $record['Title'] = $featureRoot.GetAttribute('Title')
        $record['Version'] = $featureRoot.GetAttribute('Version')
        $record['Hidden'] = & $isTrue $featureRoot.GetAttribute('Hidden')
        $record['ActivateOnDefault'] = & $isTrue $featureRoot.GetAttribute('ActivateOnDefault')
        $record['AlwaysForceInstall'] = & $isTrue $featureRoot.GetAttribute('AlwaysForceInstall')
        $record['ReceiverAssembly'] = $featureRoot.GetAttribute('ReceiverAssembly')
        $record['ReceiverClass'] = $featureRoot.GetAttribute('ReceiverClass')

        $receiver = [System.Collections.Generic.List[string]]::new()
        $folder = Split-Path -Path $full -Parent
        foreach ($elementNode in @($featureRoot.SelectNodes("./*[local-name()='ElementManifests']/*[local-name()='ElementManifest']"))) {
            $elementLocation = $elementNode.GetAttribute('Location')
            $elementResolved = & $resolveInside $folder $elementLocation
            $elementFull = $elementResolved.Path
            if ($null -eq $elementFull -or -not (Test-Path -LiteralPath $elementFull -PathType Leaf)) {
                $reason = if ($elementResolved.Problem -eq 'Link') { 'goes through a link, which is not followed' } else { 'is not in the package' }
                $problem.Add("Element manifest '$elementLocation' of the feature '$location' $reason.")
                continue
            }
            try {
                $elementDocument = Read-SPSPackageXml -Path $elementFull
            }
            catch {
                $problem.Add("Element manifest '$elementLocation' of the feature '$location' could not be read: $($_.Exception.Message)")
                continue
            }
            foreach ($child in $elementDocument.DocumentElement.ChildNodes) {
                if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) {
                    continue
                }
                if ($child.LocalName -eq 'Receivers') {
                    foreach ($item in $child.ChildNodes) {
                        if ($item.NodeType -ne [System.Xml.XmlNodeType]::Element) {
                            continue
                        }
                        $element['Receiver'] = 1 + [System.Int32]$element['Receiver']
                        # The assembly of a receiver is a child element in an element manifest, and an attribute in some files.
                        $receiverAssembly = $item.GetAttribute('Assembly')
                        if (-not $receiverAssembly) {
                            $assemblyChild = $item.SelectSingleNode("./*[local-name()='Assembly']")
                            if ($null -ne $assemblyChild) {
                                $receiverAssembly = $assemblyChild.InnerText.Trim()
                            }
                        }
                        if ($receiverAssembly) {
                            $receiver.Add($receiverAssembly)
                        }
                    }
                }
                else {
                    $element[$child.LocalName] = 1 + [System.Int32]$element[$child.LocalName]
                }
            }
        }
        $record['Receiver'] = @($receiver | Sort-Object -Unique)
        $feature.Add([PSCustomObject]$record)
    }

    $codeAccessSecurity = @($manifest.SelectNodes("/*[local-name()='Solution']/*[local-name()='CodeAccessSecurity']/*[local-name()='PolicyItem']")).Count -gt 0
    $applicationResource = (& $count 'ApplicationResourceFiles' 'ApplicationResourceFile') -gt 0
    $globalAssembly = @($assembly | Where-Object { $_.DeploymentTarget -eq 'GlobalAssemblyCache' -and $_.Status -notin @('Outside', 'Link') }).Count -gt 0
    $webApplicationAssembly = @($assembly | Where-Object { $_.DeploymentTarget -eq 'WebApplication' -and $_.Status -notin @('Outside', 'Link') }).Count -gt 0

    $fileCount = 0
    $fileBytes = [System.Int64]0
    foreach ($file in $package.File) {
        $fileCount++
        $fileBytes += $file.Length
    }

    $featureId = @($feature | Where-Object { $_.Id } | ForEach-Object { $_.Id })
    $featureScope = @($feature | Where-Object { $_.Scope } | ForEach-Object { $_.Scope } | Sort-Object -Unique)
    $summary = (@($element.Keys | Sort-Object | ForEach-Object { '{0}={1}' -f $_, $element[$_] }) -join '; ')
    $framework = @($assembly | Where-Object { $_.TargetFramework } | ForEach-Object { $_.TargetFramework } | Sort-Object -Unique)

    return [PSCustomObject]@{
        SolutionId                     = & $normalizeGuid $solution.GetAttribute('SolutionId')
        SharePointProductVersion       = $solution.GetAttribute('SharePointProductVersion')
        DeploymentServerType           = $solution.GetAttribute('DeploymentServerType')
        ResetWebServer                 = & $isTrue $solution.GetAttribute('ResetWebServer')
        ContainsGlobalAssembly         = $globalAssembly
        ContainsWebApplicationAssembly = $webApplicationAssembly
        ContainsCasPolicy              = $codeAccessSecurity
        ContainsWebApplicationResource = ($applicationResource -or $webApplicationAssembly)
        SafeControlCount               = $safeControlCount
        TemplateFileCount              = & $count 'TemplateFiles' 'TemplateFile'
        RootFileCount                  = & $count 'RootFiles' 'RootFile'
        DwpFileCount                   = & $count 'DwpFiles' 'DwpFile'
        SiteDefinitionCount            = & $count 'SiteDefinitionManifests' 'SiteDefinitionManifest'
        FeatureCount                   = $feature.Count
        FeatureIds                     = $featureId
        FeatureScopes                  = $featureScope
        FeatureReceiverCount           = @($feature | Where-Object { $_.ReceiverAssembly -or @($_.Receiver).Count -gt 0 }).Count
        ElementSummary                 = $summary
        TargetFrameworks               = $framework
        FileCount                      = $fileCount
        ExpandedSizeBytes              = $fileBytes
        Assemblies                     = $assembly.ToArray()
        Features                       = $feature.ToArray()
        Problems                       = $problem.ToArray()
    }
}
