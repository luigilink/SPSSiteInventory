# =====================================================================================
# SPSInventoryLab - lab scripts to test SPSSiteInventory on a SharePoint farm
#
# WARNING: unlike the toolkit, which is read-only, these functions WRITE to the farm:
# they create and remove site collections. Use them on a lab farm only.
#
# The functions are used by Invoke-SPSLabTest.ps1, which runs them in order:
#
#   New-SPSLabFixture      creates small, labeled site collections, one per scenario
#   New-SPSLabSettings     writes lab settings from the example configuration of the toolkit
#   Test-SPSLabResult      checks the reports against what each scenario must produce
#   Remove-SPSLabFixture   removes the lab site collections, and only those
#
# A scenario is built to trigger known signals. It is best effort: one that cannot be built
# on the farm (no incoming e-mail, no IRM, no 2010 workflow engine) is reported as skipped
# and does not stop the others. An expectation marked Info is reported but never fails the run.
# =====================================================================================

$script:LabMarkerName = 'SPSInventoryLab'

function Get-SPSLabThreshold {
    <#
        .SYNOPSIS
        Returns the large-content thresholds that the lab settings use.

        .DESCRIPTION
        The thresholds of the example configuration are made for production farms (a list of
        5000 items). The lab lowers them so that small fixtures trigger the signals, but not
        below what the system lists of a new site (the Master Page Gallery, for example)
        reach, so that an empty site does not look large. The cap of the alert rows that are
        exported per site collection is lowered as well, so that a small fixture reaches it and
        the assessment is partial.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param ()

    return [ordered]@{
        LargeListItemCount    = 200
        LargeListViewRowLimit = 100
        CheckedOutFileCount   = 1
        FileVersionCount      = 5
        # The alerts scenario has two alerts, which the cap lets through; partial-simple has three.
        MaxAlertRowsPerSite   = 2
    }
}

function Get-SPSLabExpectation {
    <#
        .SYNOPSIS
        Creates the expectation of a scenario: a property of the inventory record, or an alert.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Position = 0)]
        [System.String]
        $Property,

        [Parameter(Position = 1)]
        [ValidateSet('eq', 'ne', 'ge', 'gt', 'le', 'lt', 'like', 'match')]
        [System.String]
        $Operator = 'eq',

        [Parameter(Position = 2)]
        [AllowNull()]
        [System.Object]
        $Value,

        [Parameter()]
        [System.String]
        $Alert,

        [Parameter()]
        [switch]
        $Info
    )

    $expectation = @{ Info = [bool]$Info }
    if ($PSBoundParameters.ContainsKey('Alert')) {
        $expectation['Alert'] = $Alert
    }
    else {
        $expectation['Property'] = $Property
        $expectation['Operator'] = $Operator
        $expectation['Value'] = $Value
    }
    return $expectation
}

function Add-SPSLabList {
    <#
        .SYNOPSIS
        Adds a list to a web and returns it.
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Web,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Title,

        [Parameter()]
        [System.String]
        $Template = 'GenericList'
    )

    $id = $Web.Lists.Add($Title, 'Created by the SPSSiteInventory lab', [Microsoft.SharePoint.SPListTemplateType]$Template)
    return $Web.Lists[$id]
}

function Test-SPSLabAssemblyLoadFailure {
    <#
        .SYNOPSIS
        Tells whether an error is a failure to load an assembly.

        .DESCRIPTION
        SharePoint loads the assembly of an event receiver when the receiver is registered. A
        missing assembly shows up as a FileNotFoundException or a FileLoadException, usually
        wrapped in the exception of the method call, with "Could not load file or assembly" as
        message. Any other error is not a load failure.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]
        $ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception -is [System.IO.FileNotFoundException] -or
            $exception -is [System.IO.FileLoadException] -or
            $exception.Message -like '*Could not load file or assembly*') {
            return $true
        }
        $exception = $exception.InnerException
    }
    return $false
}

function Write-SPSLabProgress {
    <#
        .SYNOPSIS
        Writes one progress line, "[position/total] text", while the lab is built or removed.

        .DESCRIPTION
        Creating and Removing announce the work on a site collection (the detail is its URL). Any
        other status is the outcome: the status, the elapsed seconds when they are given, and the
        detail, on one line. -Quiet prints nothing, for -WhatIf.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'This is operator-facing progress whose purpose is colored console output.')]
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Int32]
        $Position,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $Total,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Status,

        [Parameter()]
        [System.String]
        $Detail,

        [Parameter()]
        [System.Double]
        $Seconds = -1,

        [Parameter()]
        [switch]
        $Quiet
    )

    if ($Quiet) {
        return
    }
    if ($Status -in @('Creating', 'Removing')) {
        $text = '{0} {1} ...' -f $Status, $Detail
    }
    else {
        $text = $Status
        if ($Seconds -ge 0) {
            $text += ' in {0} s' -f [System.Math]::Round($Seconds)
        }
        if (-not [System.String]::IsNullOrWhiteSpace($Detail)) {
            # A message can span several lines: keep the progress on one.
            $text += ': ' + (($Detail -replace '\s+', ' ').Trim())
        }
    }
    $color = switch ($Status) {
        'Created' { 'Green' }
        'Removed' { 'Green' }
        'Failed' { 'Red' }
        'Skipped' { 'DarkGray' }
        'Absent' { 'DarkGray' }
        'Refused' { 'Yellow' }
        'NotRemoved' { 'Yellow' }
        default { 'Cyan' }
    }
    Write-Host ('[{0}/{1}] {2}' -f $Position, $Total, $text) -ForegroundColor $color
}

function Get-SPSLabScenario {
    <#
        .SYNOPSIS
        Returns the lab scenarios: what to build, and what the inventory must report for it.

        .DESCRIPTION
        Every scenario gets its own site collection (https://<web application>/sites/<prefix>-<name>).
        A scenario has:

        - Name, Description and Template (the site template of the site collection);
        - Provision, a script block that receives a context (Url, Site, Web, WebApplication,
          Owner, Threshold) and builds the content. It throws a message that starts with
          'SKIP:' when the scenario cannot be built on this farm;
        - Expect, the expectations on the inventory record of the site collection and on the
          alerts raised for it.

        .PARAMETER Name
        Returns only the scenarios with these names.

        .EXAMPLE
        Get-SPSLabScenario -Name subsites
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param
    (
        [Parameter()]
        [System.String[]]
        $Name
    )

    $scenario = [System.Collections.Generic.List[object]]::new()

    $scenario.Add([PSCustomObject]@{
            Name        = 'baseline'
            Description = 'An empty team site: nothing must be flagged, and the assessment must be complete.'
            Template    = 'STS#0'
            Provision   = { param ($Context) $null = $Context }
            Expect      = @(
                (Get-SPSLabExpectation AssessmentStatus eq 'Complete')
                (Get-SPSLabExpectation SubsiteCount eq 0)
                (Get-SPSLabExpectation MaxSubsiteDepth eq 0)
                (Get-SPSLabExpectation SubWebCount eq 1)
                (Get-SPSLabExpectation SiteLockState eq 'Unlock')
                (Get-SPSLabExpectation IsLockedSite eq $false)
                (Get-SPSLabExpectation InfoPathFormCount eq 0)
                (Get-SPSLabExpectation Workflow2010Count eq 0)
                (Get-SPSLabExpectation SharePointAlertCount eq 0)
                (Get-SPSLabExpectation UsesFullTrustCode eq $false)
                (Get-SPSLabExpectation Category eq 1)
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'subsites'
            Description = 'Five subsites, three levels deep: a, a/b, a/b/c, d and e.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $created = [System.Collections.Generic.List[object]]::new()
                try {
                    $a = $Context.Web.Webs.Add('a', 'Subsite A', 'Created by the SPSSiteInventory lab', [System.UInt32]1033, 'STS#0', $false, $false)
                    $created.Add($a)
                    $b = $a.Webs.Add('b', 'Subsite B', 'Created by the SPSSiteInventory lab', [System.UInt32]1033, 'STS#0', $false, $false)
                    $created.Add($b)
                    $c = $b.Webs.Add('c', 'Subsite C', 'Created by the SPSSiteInventory lab', [System.UInt32]1033, 'STS#0', $false, $false)
                    $created.Add($c)
                    foreach ($name in @('d', 'e')) {
                        $created.Add($Context.Web.Webs.Add($name, "Subsite $name", 'Created by the SPSSiteInventory lab', [System.UInt32]1033, 'STS#0', $false, $false))
                    }
                }
                finally {
                    foreach ($web in $created) {
                        $web.Dispose()
                    }
                }
            }
            Expect      = @(
                (Get-SPSLabExpectation SubsiteCount eq 5)
                (Get-SPSLabExpectation MaxSubsiteDepth eq 3)
                (Get-SPSLabExpectation SubWebCount eq 6)
                (Get-SPSLabExpectation SubsiteExamples like 'a/b/c (level 3)*')
                (Get-SPSLabExpectation -Alert 'Subsites')
            )
        })

    foreach ($state in @('ReadOnly', 'NoAdditions', 'NoAccess')) {
        $lockState = $state
        $isNoAccess = ($state -eq 'NoAccess')
        $expectation = @(
            (Get-SPSLabExpectation SiteLockState eq $lockState)
            (Get-SPSLabExpectation IsLockedSite eq $true)
            (Get-SPSLabExpectation HasNoAccessLock eq $isNoAccess)
            (Get-SPSLabExpectation -Alert $(if ($isNoAccess) { 'NoAccessSite' } else { 'LockedSite' }))
        )
        if ($isNoAccess) {
            $expectation += (Get-SPSLabExpectation Category eq 4)
        }
        $description = if ($isNoAccess) {
            'A NoAccess lock. The site cannot be read, so its assessment stays partial, but the lock must be recognized and reported as a blocker.'
        }
        else {
            "A $state lock: the site is reported as locked but not as a blocker."
        }
        $scenario.Add([PSCustomObject]@{
                Name        = 'lock-' + $state.ToLowerInvariant()
                Description = $description
                Template    = 'STS#0'
                Provision   = { param ($Context) Set-SPSite -Identity $Context.Url -LockState $lockState -ErrorAction Stop }.GetNewClosure()
                Expect      = $expectation
            })
    }

    $scenario.Add([PSCustomObject]@{
            Name        = 'large-content'
            Description = 'A list above the large-list threshold with a view that has a high row limit, a document with several versions and a checked-out document.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $web = $Context.Web
                $library = Add-SPSLabList -Web $web -Title 'LabDocs' -Template 'DocumentLibrary'
                $library.EnableVersioning = $true
                $library.Update()
                $encoding = [System.Text.Encoding]::UTF8
                $versionCount = [System.Int32]$Context.Threshold.FileVersionCount + 1
                for ($version = 1; $version -le $versionCount; $version++) {
                    $null = $library.RootFolder.Files.Add('versions.txt', $encoding.GetBytes("version $version"), $true)
                }
                $null = $library.RootFolder.Files.Add('checked-out.txt', $encoding.GetBytes('checked out'), $true)
                $web.GetFile($library.RootFolder.ServerRelativeUrl + '/checked-out.txt').CheckOut()

                $list = Add-SPSLabList -Web $web -Title 'LabLarge'
                $itemCount = [System.Int32]$Context.Threshold.LargeListItemCount + 5
                for ($index = 1; $index -le $itemCount; $index++) {
                    $item = $list.Items.Add()
                    $item['Title'] = "Item $index"
                    $item.Update()
                }
                $field = New-Object -TypeName System.Collections.Specialized.StringCollection
                $null = $field.Add('Title')
                $rowLimit = [System.UInt32]($Context.Threshold.LargeListViewRowLimit + 100)
                $null = $list.Views.Add('LabBigView', $field, '', $rowLimit, $true, $false)
            }
            Expect      = @(
                (Get-SPSLabExpectation LargeListCount ge 1)
                (Get-SPSLabExpectation LargeListViewCount ge 1)
                (Get-SPSLabExpectation CheckedOutFileCount ge 1)
                (Get-SPSLabExpectation FileVersionCount ge 1)
                (Get-SPSLabExpectation -Alert 'LargeLists')
                (Get-SPSLabExpectation -Alert 'LargeListViews')
                (Get-SPSLabExpectation -Alert 'CheckedOutFiles')
                (Get-SPSLabExpectation -Alert 'FileVersions')
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'permissions'
            Description = 'A custom permission level.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $role = New-Object -TypeName Microsoft.SharePoint.SPRoleDefinition
                $role.Name = 'Lab Custom Level'
                $role.Description = 'Created by the SPSSiteInventory lab'
                $role.BasePermissions = [Microsoft.SharePoint.SPBasePermissions]'Open, ViewPages, ViewListItems, OpenItems'
                $Context.Web.RoleDefinitions.Add($role)
            }
            Expect      = @(
                (Get-SPSLabExpectation CustomPermissionLevelCount ge 1)
                (Get-SPSLabExpectation -Alert 'CustomPermissionLevels')
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'alerts'
            Description = 'Two SharePoint alerts ("Alert Me" subscriptions) of the owner of the site on a list.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $list = Add-SPSLabList -Web $Context.Web -Title 'LabAlerts'
                $user = $Context.Web.EnsureUser($Context.Owner)
                if ([System.String]::IsNullOrEmpty($user.Email)) {
                    $user.Email = 'lab@example.invalid'
                    $user.Update()
                }
                $null = $user.Alerts.Add($list, [Microsoft.SharePoint.SPEventType]::All, [Microsoft.SharePoint.SPAlertFrequency]::Immediate)
                $null = $user.Alerts.Add($list, [Microsoft.SharePoint.SPEventType]::Add, [Microsoft.SharePoint.SPAlertFrequency]::Daily)
            }
            Expect      = @(
                (Get-SPSLabExpectation SharePointAlertCount ge 2)
                (Get-SPSLabExpectation -Alert 'AlertSubscriptions')
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'partial-simple'
            Description = 'Three SharePoint alerts, one more than the lab lets the inventory export (MaxAlertRowsPerSite): the assessment is partial and nothing else is flagged, so the site is Simple and waits in the Needs review wave, not in the quick wins.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $list = Add-SPSLabList -Web $Context.Web -Title 'LabAlerts'
                $user = $Context.Web.EnsureUser($Context.Owner)
                if ([System.String]::IsNullOrEmpty($user.Email)) {
                    $user.Email = 'lab@example.invalid'
                    $user.Update()
                }
                $null = $user.Alerts.Add($list, [Microsoft.SharePoint.SPEventType]::All, [Microsoft.SharePoint.SPAlertFrequency]::Immediate)
                $null = $user.Alerts.Add($list, [Microsoft.SharePoint.SPEventType]::Add, [Microsoft.SharePoint.SPAlertFrequency]::Daily)
                $null = $user.Alerts.Add($list, [Microsoft.SharePoint.SPEventType]::Delete, [Microsoft.SharePoint.SPAlertFrequency]::Weekly)
            }
            Expect      = @(
                (Get-SPSLabExpectation AssessmentStatus eq 'Partial')
                (Get-SPSLabExpectation SharePointAlertCount ge 3)
                (Get-SPSLabExpectation Category eq 1)
                (Get-SPSLabExpectation Wave eq 0)
                (Get-SPSLabExpectation WaveName eq 'Needs review')
                (Get-SPSLabExpectation -Alert 'AssessmentPartial')
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'publishing'
            Description = 'The SharePoint Server Publishing features, and a page when the publishing API allows it.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                Enable-SPFeature -Identity 'PublishingSite' -Url $Context.Url -ErrorAction Stop
                Enable-SPFeature -Identity 'PublishingWeb' -Url $Context.Url -ErrorAction Stop
                $freshSite = $null
                $freshWeb = $null
                try {
                    $null = [System.Reflection.Assembly]::Load('Microsoft.SharePoint.Publishing, Version=16.0.0.0, Culture=neutral, PublicKeyToken=71e9bce111e9429c')
                    $freshSite = Get-SPSite -Identity $Context.Url -ErrorAction Stop
                    $freshWeb = $freshSite.OpenWeb()
                    $publishingWeb = [Microsoft.SharePoint.Publishing.PublishingWeb]::GetPublishingWeb($freshWeb)
                    $layout = @($publishingWeb.GetAvailablePageLayouts()) | Select-Object -First 1
                    $page = $publishingWeb.GetPublishingPages().Add('lab-page.aspx', $layout)
                    $page.Update()
                }
                catch {
                    Write-Verbose -Message "The publishing page could not be created: $($_.Exception.Message)"
                }
                finally {
                    if ($null -ne $freshWeb) { $freshWeb.Dispose() }
                    if ($null -ne $freshSite) { $freshSite.Dispose() }
                }
            }
            Expect      = @(
                (Get-SPSLabExpectation PublishingInfrastructureEnabled eq $true)
                (Get-SPSLabExpectation PublishingWebCount ge 1)
                (Get-SPSLabExpectation PublishingPageCount ge 1 -Info)
                (Get-SPSLabExpectation -Alert 'PublishingSite')
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'template-blog'
            Description = 'A blog site: its template is mapped to Review.'
            Template    = 'BLOG#0'
            Provision   = { param ($Context) $null = $Context }
            Expect      = @(
                (Get-SPSLabExpectation TemplateCompatibility eq 'Review')
                (Get-SPSLabExpectation -Alert 'TemplateCompatibilityReview')
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'infopath'
            Description = 'An InfoPath form library: a blocker in the example configuration.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $null = Add-SPSLabList -Web $Context.Web -Title 'LabForms' -Template 'XMLForm'
            }
            Expect      = @(
                (Get-SPSLabExpectation InfoPathFormCount ge 1)
                (Get-SPSLabExpectation Category eq 4)
                (Get-SPSLabExpectation -Alert 'InfoPath')
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'event-receiver'
            Description = 'A list with an event receiver registered from the assembly Contoso.Lab.Receivers. SharePoint loads the assembly to register a receiver, so the scenario is skipped unless an assembly of that name is deployed on the farm. The receiver never fires: it is only registered.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $list = Add-SPSLabList -Web $Context.Web -Title 'LabReceivers'
                $assembly = 'Contoso.Lab.Receivers, Version=1.0.0.0, Culture=neutral, PublicKeyToken=0123456789abcdef'
                try {
                    $list.EventReceivers.Add([Microsoft.SharePoint.SPEventReceiverType]::ItemDeleting, $assembly, 'Contoso.Lab.Receivers.ItemReceiver')
                }
                catch {
                    if (Test-SPSLabAssemblyLoadFailure -ErrorRecord $_) {
                        throw 'SKIP: SharePoint loads the assembly to register an event receiver: deploy one to test this signal.'
                    }
                    throw
                }
            }
            Expect      = @(
                (Get-SPSLabExpectation EventReceivers ge 1)
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'custom-master'
            Description = 'A custom master page, set as the master page of the site.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $web = $Context.Web
                $source = $web.GetFile($web.CustomMasterUrl)
                if (-not $source.Exists) {
                    throw 'SKIP: the master page of the site cannot be read.'
                }
                $gallery = $web.GetFolder('_catalogs/masterpage')
                $file = $gallery.Files.Add('lab.master', $source.OpenBinary(), $true)
                $web.CustomMasterUrl = $file.ServerRelativeUrl
                $web.Update()
            }
            Expect      = @(
                (Get-SPSLabExpectation CustomMasterPage eq $true)
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'customized-page'
            Description = 'The default page of the root web, edited. The inventory ignores edits of the System Account, which is the farm account: run the lab with another account for this one.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $file = $Context.Web.GetFile('default.aspx')
                if (-not $file.Exists) {
                    throw 'SKIP: the root web has no default.aspx page.'
                }
                $text = [System.Text.Encoding]::UTF8.GetString($file.OpenBinary()) + [System.Environment]::NewLine + '<!-- SPSSiteInventory lab -->'
                $file.SaveBinary([System.Text.Encoding]::UTF8.GetBytes($text))
            }
            Expect      = @(
                (Get-SPSLabExpectation CustomizedPageCount ge 1 -Info)
                (Get-SPSLabExpectation -Alert 'CustomizedPages' -Info)
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'workflow-2010'
            Description = 'A SharePoint 2010 workflow association on a list, from an out-of-the-box template.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $web = $Context.Web
                $template = @($web.WorkflowTemplates | Where-Object { $_.Name -like '*Approval*' }) | Select-Object -First 1
                if ($null -eq $template) {
                    throw 'SKIP: no out-of-the-box SharePoint 2010 workflow template is available on this farm.'
                }
                $list = Add-SPSLabList -Web $web -Title 'LabWorkflowList'
                $tasks = Add-SPSLabList -Web $web -Title 'LabWorkflowTasks' -Template 'Tasks'
                $history = Add-SPSLabList -Web $web -Title 'LabWorkflowHistory' -Template 'WorkflowHistory'
                $association = [Microsoft.SharePoint.Workflow.SPWorkflowAssociation]::CreateListAssociation($template, 'Lab approval', $tasks, $history)
                $list.AddWorkflowAssociation($association)
            }
            Expect      = @(
                (Get-SPSLabExpectation Workflow2010Count ge 1)
                (Get-SPSLabExpectation -Alert 'Workflow2010')
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'email-enabled'
            Description = 'A list with an incoming e-mail address. Needs the incoming e-mail service of the farm.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $list = Add-SPSLabList -Web $Context.Web -Title 'LabMail' -Template 'DocumentLibrary'
                try {
                    $list.EmailAlias = 'spslabmail'
                    $list.Update()
                }
                catch {
                    throw "SKIP: incoming e-mail is not available on this farm ($($_.Exception.Message))"
                }
            }
            Expect      = @(
                (Get-SPSLabExpectation EmailEnabledListCount ge 1 -Info)
                (Get-SPSLabExpectation -Alert 'EmailEnabledLists' -Info)
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'irm'
            Description = 'A list with Information Rights Management enabled. Needs IRM to be configured on the farm.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                $list = Add-SPSLabList -Web $Context.Web -Title 'LabIrm' -Template 'DocumentLibrary'
                try {
                    $list.IrmEnabled = $true
                    $list.Update()
                }
                catch {
                    throw "SKIP: IRM is not available on this farm ($($_.Exception.Message))"
                }
            }
            Expect      = @(
                (Get-SPSLabExpectation IrmEnabledListCount ge 1 -Info)
                (Get-SPSLabExpectation -Alert 'IrmEnabledLists' -Info)
            )
        })

    $scenario.Add([PSCustomObject]@{
            Name        = 'html-files'
            Description = 'An .html file in a library. Only counted where the web application uses Permissive browser file handling.'
            Template    = 'STS#0'
            Provision   = {
                param ($Context)
                if ([System.String]$Context.WebApplication.BrowserFileHandling -ne 'Permissive') {
                    throw 'SKIP: the web application uses Strict browser file handling, so .html files are not counted.'
                }
                $library = Add-SPSLabList -Web $Context.Web -Title 'LabHtml' -Template 'DocumentLibrary'
                $null = $library.RootFolder.Files.Add('lab.html', [System.Text.Encoding]::UTF8.GetBytes('<html><body>lab</body></html>'), $true)
            }
            Expect      = @(
                (Get-SPSLabExpectation HtmlFileCount ge 1)
                (Get-SPSLabExpectation -Alert 'HtmlFiles')
            )
        })

    if ($PSBoundParameters.ContainsKey('Name') -and $Name.Count -gt 0) {
        return @($scenario | Where-Object { $Name -contains $_.Name })
    }
    return $scenario.ToArray()
}

function New-SPSLabSettings {
    <#
        .SYNOPSIS
        Writes the lab settings file from the example configuration of the toolkit.

        .DESCRIPTION
        Takes the example configuration of the toolkit being tested, so that the lab exercises
        its real scoring, and changes only what the lab needs: the environment name, the web
        application to scan, the report folder and the large-content thresholds (see
        Get-SPSLabThreshold). It fails when the example no longer has one of those settings,
        instead of writing a file that does not do what the lab expects.

        .PARAMETER ExamplePath
        The example settings file of the toolkit (config\inventory-settings.example.psd1).

        .PARAMETER OutputPath
        Where to write the lab settings file.

        .PARAMETER WebApplicationUrl
        The lab web application: the only one the inventory scans.

        .PARAMETER ReportFolder
        The folder the inventory writes its reports to.

        .EXAMPLE
        New-SPSLabSettings -ExamplePath .\config\inventory-settings.example.psd1 -OutputPath .\lab.psd1 -WebApplicationUrl https://lab -ReportFolder .\Reports
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ExamplePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WebApplicationUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ReportFolder
    )

    if (-not (Test-Path -LiteralPath $ExamplePath -PathType Leaf)) {
        throw "The example settings file '$ExamplePath' does not exist."
    }
    $text = [System.IO.File]::ReadAllText($ExamplePath)

    $replace = {
        param ([System.String] $Text, [System.String] $Pattern, [System.String] $Replacement, [System.String] $Setting)

        $regex = [System.Text.RegularExpressions.Regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if (-not $regex.IsMatch($Text)) {
            throw "The example settings file no longer has the '$Setting' setting that the lab changes; update the lab scripts."
        }
        return $regex.Replace($Text, '${1}' + $Replacement.Replace('$', '$$'), 1)
    }

    $quotedFolder = "'" + $ReportFolder.Replace("'", "''") + "'"
    $quotedUrl = "@('" + $WebApplicationUrl.Replace("'", "''") + "')"
    $text = & $replace $text "^(\s*EnvName\s*=\s*)'[^']*'" "'LAB'" 'EnvName'
    $text = & $replace $text '^(\s*WebApplicationUrl\s*=\s*)@\([^)]*\)' $quotedUrl 'WebApplicationUrl'
    $text = & $replace $text "^(\s*OutputFolder\s*=\s*)'[^']*'" $quotedFolder 'OutputFolder'

    # The thresholds share their names with some weights, so change them inside their own block only.
    $block = [System.Text.RegularExpressions.Regex]::Match($text, '(?s)LargeContentThresholds\s*=\s*@\{.*?\r?\n    \}')
    if (-not $block.Success) {
        throw "The example settings file no longer has the 'LargeContentThresholds' section that the lab changes; update the lab scripts."
    }
    $changed = $block.Value
    foreach ($threshold in (Get-SPSLabThreshold).GetEnumerator()) {
        $changed = & $replace $changed ('^(\s*{0}\s*=\s*)[0-9.]+' -f $threshold.Key) ([System.String]$threshold.Value) ('LargeContentThresholds.' + $threshold.Key)
    }
    $text = $text.Substring(0, $block.Index) + $changed + $text.Substring($block.Index + $block.Length)

    $header = "# SPSSiteInventory lab settings, generated from the example configuration of the toolkit.`r`n# Do not use this file outside the lab: it scans '$WebApplicationUrl' only and lowers the large-content thresholds.`r`n"
    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write the lab settings file')) {
        $folder = Split-Path -Path $OutputPath -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) {
            $null = New-Item -Path $folder -ItemType Directory -Force
        }
        [System.IO.File]::WriteAllText($OutputPath, $header + $text, [System.Text.UTF8Encoding]::new($true))
    }
    return $OutputPath
}

function New-SPSLabFixture {
    <#
        .SYNOPSIS
        Creates the lab site collections, one per scenario, and writes a manifest of them.

        .DESCRIPTION
        WRITES TO THE FARM. For every scenario it creates the site collection
        <web application>/sites/<prefix>-<scenario>, marks it as a lab site (a property of its
        root web) and runs the scenario to build its content. A scenario that cannot be built is
        reported as Skipped (the farm lacks something it needs) or Failed, and the others go on.
        A site collection that already exists is left alone: remove the lab first.

        The manifest lists what was created, so that Test-SPSLabResult and Remove-SPSLabFixture
        know the lab sites. Confirmation is asked before anything is created.

        .PARAMETER WebApplicationUrl
        The URL of the lab web application. There is no default: name it on purpose.

        .PARAMETER ManifestPath
        Where to write the manifest.

        .PARAMETER Prefix
        The prefix of the site collection names. Lowercase letters and digits.

        .PARAMETER Owner
        The owner (primary site collection administrator) of the site collections. Defaults to
        the current account.

        .PARAMETER Scenario
        The scenarios to build. Defaults to all of them (see Get-SPSLabScenario).

        .EXAMPLE
        New-SPSLabFixture -WebApplicationUrl https://lab.contoso.local -ManifestPath .\lab-manifest.json
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $WebApplicationUrl,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ManifestPath,

        [Parameter()]
        [ValidatePattern('^[a-z][a-z0-9]{2,15}$')]
        [System.String]
        $Prefix = 'spslab',

        [Parameter()]
        [System.String]
        $Owner = ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME),

        [Parameter()]
        [System.String[]]
        $Scenario
    )

    if ($null -eq (Get-Command -Name 'New-SPSite' -ErrorAction SilentlyContinue)) {
        throw 'The SharePoint commands are not available. Run this from the SharePoint Management Shell, or load the snap-in, on a farm server.'
    }

    $scenarioList = @(Get-SPSLabScenario -Name $Scenario)
    if ($scenarioList.Count -eq 0) {
        throw 'No scenario matches. See Get-SPSLabScenario for the names.'
    }

    $webApplication = Get-SPWebApplication -Identity $WebApplicationUrl -ErrorAction Stop
    $baseUrl = $webApplication.Url.TrimEnd('/')
    $threshold = Get-SPSLabThreshold
    $entry = [System.Collections.Generic.List[object]]::new()
    $total = $scenarioList.Count
    $position = 0

    foreach ($item in $scenarioList) {
        $position++
        $url = '{0}/sites/{1}-{2}' -f $baseUrl, $Prefix, $item.Name
        $status = 'Created'
        $detail = ''

        if (-not $PSCmdlet.ShouldProcess($url, "Create the lab site collection for scenario '$($item.Name)'")) {
            $entry.Add([PSCustomObject]@{ Name = $item.Name; Url = $url; Status = 'NotCreated'; Detail = 'Not confirmed.' })
            continue
        }

        $existing = Get-SPSite -Identity $url -ErrorAction SilentlyContinue
        if ($null -ne $existing) {
            $existing.Dispose()
            $entry.Add([PSCustomObject]@{ Name = $item.Name; Url = $url; Status = 'Skipped'; Detail = 'The site collection already exists: remove the lab first.' })
            Write-SPSLabProgress -Position $position -Total $total -Status 'Skipped' -Detail 'The site collection already exists: remove the lab first.'
            continue
        }

        $site = $null
        $web = $null
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-SPSLabProgress -Position $position -Total $total -Status 'Creating' -Detail $url
        try {
            $site = New-SPSite -Url $url -OwnerAlias $Owner -Template $item.Template -Name ('SPS lab: ' + $item.Name) -Language 1033 -ErrorAction Stop
            $web = $site.RootWeb
            $web.AllProperties[$script:LabMarkerName] = 'true'
            $web.Update()

            $context = [PSCustomObject]@{
                Url            = $url
                Site           = $site
                Web            = $web
                WebApplication = $webApplication
                Owner          = $Owner
                Threshold      = $threshold
            }
            $null = & $item.Provision $context
        }
        catch {
            $message = $_.Exception.Message
            if ($message.StartsWith('SKIP:')) {
                $status = 'Skipped'
                $detail = $message.Substring(5).Trim()
            }
            else {
                $status = 'Failed'
                $detail = $message
            }
        }
        finally {
            if ($null -ne $web) { $web.Dispose() }
            if ($null -ne $site) { $site.Dispose() }
        }

        if ($null -eq $site) {
            $status = 'Failed'
        }
        $entry.Add([PSCustomObject]@{ Name = $item.Name; Url = $url; Status = $status; Detail = $detail })
        Write-SPSLabProgress -Position $position -Total $total -Status $status -Detail $detail -Seconds $timer.Elapsed.TotalSeconds
    }

    $manifest = [PSCustomObject]@{
        ManifestVersion   = 1
        CreatedOn         = (Get-Date).ToString('o')
        WebApplicationUrl = $baseUrl
        Prefix            = $Prefix
        Owner             = $Owner
        Scenario          = $entry.ToArray()
    }
    $folder = Split-Path -Path $ManifestPath -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -Path $folder -ItemType Directory -Force
    }
    ConvertTo-Json -InputObject $manifest -Depth 5 | Set-Content -Path $ManifestPath -Encoding UTF8
    return $manifest
}

function Test-SPSLabExpectation {
    <#
        .SYNOPSIS
        Evaluates one expectation against the inventory record and the alerts of a site collection.

        .DESCRIPTION
        Returns a result with Check, Expected, Actual, Kind (Must or Info) and Status:

        - PASS: the expectation is met;
        - FAIL: it is not met (a Must expectation);
        - INFO: it is not met, but it is only informational;
        - SKIP: it cannot be evaluated (for example no alerts report).

        .PARAMETER Expectation
        An expectation from Get-SPSLabScenario.

        .PARAMETER Record
        The inventory record of the site collection.

        .PARAMETER Alert
        The alert types raised for the site collection, or $null when there is no alerts report.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Expectation,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $Record,

        [Parameter()]
        [AllowNull()]
        [System.String[]]
        $Alert
    )

    $kind = if ([bool]$Expectation['Info']) { 'Info' } else { 'Must' }
    $notMet = if ($kind -eq 'Info') { 'INFO' } else { 'FAIL' }

    if ($Expectation.Contains('Alert')) {
        $type = [System.String]$Expectation['Alert']
        if ($null -eq $Alert) {
            return [PSCustomObject]@{ Check = "Alert $type"; Expected = 'raised'; Actual = 'no alerts report'; Kind = $kind; Status = 'SKIP' }
        }
        $raised = @($Alert) -contains $type
        return [PSCustomObject]@{ Check = "Alert $type"; Expected = 'raised'; Actual = $(if ($raised) { 'raised' } else { 'not raised' }); Kind = $kind; Status = $(if ($raised) { 'PASS' } else { $notMet }) }
    }

    $property = [System.String]$Expectation['Property']
    $operator = [System.String]$Expectation['Operator']
    $expected = $Expectation['Value']
    $label = '{0} {1} {2}' -f $property, $operator, $(if ($expected -is [System.Boolean]) { $expected.ToString().ToLowerInvariant() } else { $expected })
    if ($null -eq $Record -or $null -eq $Record.PSObject.Properties[$property]) {
        return [PSCustomObject]@{ Check = $label; Expected = $expected; Actual = '(not in the record)'; Kind = $kind; Status = $notMet }
    }

    $actual = $Record.$property
    $met = $false
    switch ($operator) {
        'like' { $met = ([System.String]$actual) -like ([System.String]$expected) }
        'match' { $met = ([System.String]$actual) -match ([System.String]$expected) }
        default {
            if ($null -eq $actual) {
                $met = ($operator -eq 'eq' -and $null -eq $expected) -or ($operator -eq 'ne' -and $null -ne $expected)
            }
            elseif ($actual -is [System.Boolean] -or $expected -is [System.Boolean]) {
                $left = [System.Boolean]$actual
                $right = [System.Boolean]$expected
                $met = if ($operator -eq 'eq') { $left -eq $right } elseif ($operator -eq 'ne') { $left -ne $right } else { $false }
            }
            else {
                $number = 0.0
                $isNumber = [System.Double]::TryParse([System.String]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $actual), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number) -and
                    ($expected -is [System.ValueType])
                if ($isNumber) {
                    $left = $number
                    $right = [System.Double]$expected
                    $met = switch ($operator) { 'eq' { $left -eq $right } 'ne' { $left -ne $right } 'ge' { $left -ge $right } 'gt' { $left -gt $right } 'le' { $left -le $right } 'lt' { $left -lt $right } }
                }
                else {
                    $left = [System.String]$actual
                    $right = [System.String]$expected
                    $met = switch ($operator) { 'eq' { $left -eq $right } 'ne' { $left -ne $right } default { $false } }
                }
            }
        }
    }

    return [PSCustomObject]@{ Check = $label; Expected = $expected; Actual = $actual; Kind = $kind; Status = $(if ($met) { 'PASS' } else { $notMet }) }
}

function Read-SPSLabJson {
    <#
        .SYNOPSIS
        Reads a JSON report as a flat list of records, in Windows PowerShell 5.1 and in PowerShell 7.

        .DESCRIPTION
        Windows PowerShell 5.1 returns a JSON array as one object, PowerShell 7 as many.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $parsed = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $record = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $parsed) {
        if ($item -is [System.Array]) {
            foreach ($inner in $item) { $record.Add($inner) }
        }
        elseif ($null -ne $item) {
            $record.Add($item)
        }
    }
    return $record.ToArray()
}

function Test-SPSLabResult {
    <#
        .SYNOPSIS
        Checks the reports of an inventory run against what each lab scenario must produce.

        .DESCRIPTION
        Reads the lab manifest, the newest sites report (and the newest alerts report, if there is
        one) of the report folder, and evaluates the expectations of every scenario that was
        created. It returns one result per check, with Scenario, Url, Check, Expected, Actual,
        Kind and Status (PASS, FAIL, INFO or SKIP). A scenario that was not created is skipped.
        Every lab site also gets an Assessment result: a site whose assessment is Partial or
        Failed is how a problem with a real farm shows up, so its warnings are listed.

        The alerts report is the one that the same run wrote next to the sites report (same name and
        time stamp), never an older or newer one: an alerts report that is missing is a skipped check,
        and one that is there but empty means that the run raised no alert.

        .PARAMETER ManifestPath
        The manifest written by New-SPSLabFixture.

        .PARAMETER ReportFolder
        The folder the inventory wrote its reports to.

        .PARAMETER Scenario
        Checks only these scenarios of the manifest. It is an error when none of them is in it.

        .EXAMPLE
        Test-SPSLabResult -ManifestPath .\lab-manifest.json -ReportFolder .\Reports
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ManifestPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ReportFolder,

        [Parameter()]
        [System.String[]]
        $Scenario
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "The lab manifest '$ManifestPath' does not exist: run the Provision step first."
    }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $entryList = @($manifest.Scenario)
    if ($PSBoundParameters.ContainsKey('Scenario') -and @($Scenario).Count -gt 0) {
        $entryList = @($entryList | Where-Object { @($Scenario) -contains [System.String]$_.Name })
        if ($entryList.Count -eq 0) {
            throw ("None of the scenarios '{0}' is in the lab manifest." -f (@($Scenario) -join "', '"))
        }
    }
    $sitesFile = Get-ChildItem -LiteralPath $ReportFolder -Filter '*-sites-*.json' -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $sitesFile) {
        throw "No '*-sites-*.json' report in '$ReportFolder': run the inventory first."
    }
    # The alerts report of the run that wrote this sites report: same name, same time stamp.
    $alertsPath = Join-Path -Path $ReportFolder -ChildPath ([System.Text.RegularExpressions.Regex]::Replace($sitesFile.Name, '^(.*)-sites-(.*)$', '${1}-alerts-${2}'))
    $hasAlerts = Test-Path -LiteralPath $alertsPath -PathType Leaf

    $records = Read-SPSLabJson -Path $sitesFile.FullName
    $alerts = @()
    if ($hasAlerts) {
        $alerts = @(Read-SPSLabJson -Path $alertsPath)
    }
    $catalog = @(Get-SPSLabScenario)
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($entry in $entryList) {
        $definition = $catalog | Where-Object { $_.Name -eq $entry.Name } | Select-Object -First 1
        if ($null -eq $definition) {
            continue
        }
        $add = {
            param ($Result)
            $results.Add([PSCustomObject]@{
                    Scenario = $entry.Name
                    Url      = $entry.Url
                    Check    = $Result.Check
                    Expected = $Result.Expected
                    Actual   = $Result.Actual
                    Kind     = $Result.Kind
                    Status   = $Result.Status
                })
        }

        if ([System.String]$entry.Status -ne 'Created') {
            $built = [System.String]$entry.Status -eq 'Failed'
            & $add ([PSCustomObject]@{ Check = 'Scenario built'; Expected = 'created'; Actual = ('{0}: {1}' -f $entry.Status, $entry.Detail); Kind = 'Must'; Status = $(if ($built) { 'FAIL' } else { 'SKIP' }) })
            continue
        }

        $record = $records | Where-Object { [System.String]$_.Url -eq [System.String]$entry.Url } | Select-Object -First 1
        if ($null -eq $record) {
            & $add ([PSCustomObject]@{ Check = 'Site in the inventory'; Expected = 'present'; Actual = 'missing'; Kind = 'Must'; Status = 'FAIL' })
            continue
        }
        $raisedType = $null
        if ($hasAlerts) {
            $raisedType = @($alerts | Where-Object { [System.String]$_.Url -eq [System.String]$entry.Url } | ForEach-Object { [System.String]$_.AlertType })
        }

        foreach ($expectation in @($definition.Expect)) {
            & $add (Test-SPSLabExpectation -Expectation $expectation -Record $record -Alert $raisedType)
        }

        $status = [System.String]$record.AssessmentStatus
        $warning = [System.String]$record.AssessmentWarnings
        & $add ([PSCustomObject]@{
                Check    = 'Assessment'
                Expected = 'Complete'
                Actual   = $(if ($warning) { '{0}: {1}' -f $status, $warning } else { $status })
                Kind     = 'Info'
                Status   = $(if ($status -eq 'Complete') { 'PASS' } else { 'INFO' })
            })
    }
    return $results.ToArray()
}

function Write-SPSLabReport {
    <#
        .SYNOPSIS
        Writes the results of Test-SPSLabResult as a colored report and returns the counts.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'This is an operator-facing report whose purpose is colored console output.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Object[]]
        $Result
    )

    $style = @{
        PASS = @{ Mark = '[PASS]'; Color = 'Green' }
        FAIL = @{ Mark = '[FAIL]'; Color = 'Red' }
        INFO = @{ Mark = '[INFO]'; Color = 'Yellow' }
        SKIP = @{ Mark = '[SKIP]'; Color = 'DarkGray' }
    }
    $current = $null
    foreach ($item in $Result) {
        if ($item.Scenario -ne $current) {
            Write-Host ''
            Write-Host ('== {0} ({1}) ==' -f $item.Scenario, $item.Url) -ForegroundColor Cyan
            $current = $item.Scenario
        }
        $mark = $style[[System.String]$item.Status]
        $line = '{0}  {1}' -f $mark.Mark, $item.Check
        if ($item.Status -ne 'PASS' -or $item.Check -eq 'Assessment') {
            $line += ' - actual: {0}' -f $item.Actual
        }
        Write-Host $line -ForegroundColor $mark.Color
    }
    $count = [PSCustomObject]@{
        Pass = @($Result | Where-Object { $_.Status -eq 'PASS' }).Count
        Fail = @($Result | Where-Object { $_.Status -eq 'FAIL' }).Count
        Info = @($Result | Where-Object { $_.Status -eq 'INFO' }).Count
        Skip = @($Result | Where-Object { $_.Status -eq 'SKIP' }).Count
    }
    Write-Host ''
    Write-Host ('Summary: {0} passed, {1} failed, {2} informational, {3} skipped' -f $count.Pass, $count.Fail, $count.Info, $count.Skip) -ForegroundColor Cyan
    return $count
}

function Get-SPSLabMarker {
    <#
        .SYNOPSIS
        Tells whether a site collection carries the lab marker that New-SPSLabFixture sets.

        .DESCRIPTION
        Returns $true or $false, and $null when the site collection does not exist. It throws when the
        site collection cannot be read, which is what a NoAccess lock does, instead of reporting a site
        that it could not read as one without a marker.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Url
    )

    $site = Get-SPSite -Identity $Url -ErrorAction SilentlyContinue
    if ($null -eq $site) {
        return $null
    }
    try {
        # PowerShell turns an exception thrown by a property getter into $null: a locked site must not read as unmarked.
        $web = $site.RootWeb
        if ($null -eq $web) {
            throw 'The root web of the site collection cannot be read.'
        }
        try {
            $property = $web.AllProperties
            if ($null -eq $property) {
                throw 'The properties of the root web cannot be read.'
            }
            return ([System.String]$property[$script:LabMarkerName]) -eq 'true'
        }
        finally {
            $web.Dispose()
        }
    }
    finally {
        $site.Dispose()
    }
}

function Remove-SPSLabFixture {
    <#
        .SYNOPSIS
        Removes the lab site collections, and only those.

        .DESCRIPTION
        WRITES TO THE FARM. Removes the site collections of the manifest, or, without a manifest,
        those named <web application>/sites/<prefix>-*. Nothing is removed unless its URL starts
        with that prefix AND its root web carries the lab marker that New-SPSLabFixture sets, so a
        site that merely looks like a lab site is left alone. A locked site is unlocked first.
        Confirmation is asked before each removal.

        With a manifest, -WebApplicationUrl and -Prefix, when they are given, must be those of the
        manifest: a manifest that is left in a work folder cannot be used to remove the lab of another
        web application.

        A removed site collection stays in the deleted sites, which blocks its URL. The deleted sites
        that this run removed, and those of the manifest that were removed before, are purged, after a
        confirmation, so that the lab can be built again. Nothing else is purged, a lookalike that was
        refused included.

        .PARAMETER ManifestPath
        The manifest written by New-SPSLabFixture.

        .PARAMETER WebApplicationUrl
        Without a manifest, the lab web application. With a manifest, the web application that the
        manifest must be for.

        .PARAMETER Prefix
        Without a manifest, the prefix of the lab site collections. With a manifest, the prefix that
        the manifest must have, when it is given.

        .EXAMPLE
        Remove-SPSLabFixture -ManifestPath .\lab-manifest.json
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'Prefix')]
    [OutputType([System.Management.Automation.PSObject[]])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Manifest')]
        [System.String]
        $ManifestPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Prefix')]
        [Parameter(ParameterSetName = 'Manifest')]
        [System.String]
        $WebApplicationUrl,

        [Parameter(ParameterSetName = 'Prefix')]
        [Parameter(ParameterSetName = 'Manifest')]
        [ValidatePattern('^[a-z][a-z0-9]{2,15}$')]
        [System.String]
        $Prefix = 'spslab'
    )

    if ($PSCmdlet.ParameterSetName -eq 'Manifest') {
        if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
            throw "The lab manifest '$ManifestPath' does not exist. Give -WebApplicationUrl and -Prefix to find the lab sites without it."
        }
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        $baseUrl = [System.String]$manifest.WebApplicationUrl
        $prefixValue = [System.String]$manifest.Prefix
        if ($PSBoundParameters.ContainsKey('WebApplicationUrl')) {
            $requestedUrl = (Get-SPWebApplication -Identity $WebApplicationUrl -ErrorAction Stop).Url.TrimEnd('/')
            if (-not [System.String]::Equals($requestedUrl, $baseUrl, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "The lab manifest '$ManifestPath' is for the web application '$baseUrl', not for '$requestedUrl': nothing was removed. Use the work folder of the lab you want to remove."
            }
        }
        if ($PSBoundParameters.ContainsKey('Prefix') -and $Prefix -cne $prefixValue) {
            throw "The lab manifest '$ManifestPath' is for the prefix '$prefixValue', not for '$Prefix': nothing was removed. Use the work folder of the lab you want to remove."
        }
        $urlList = @($manifest.Scenario | ForEach-Object { [System.String]$_.Url })
    }
    else {
        $baseUrl = (Get-SPWebApplication -Identity $WebApplicationUrl -ErrorAction Stop).Url.TrimEnd('/')
        $prefixValue = $Prefix
        $urlList = @(Get-SPSite -WebApplication $baseUrl -Limit All | ForEach-Object { $_.Url } | Where-Object { $_ -like ('{0}/sites/{1}-*' -f $baseUrl, $prefixValue) })
    }
    $required = '{0}/sites/{1}-' -f $baseUrl, $prefixValue
    $result = [System.Collections.Generic.List[object]]::new()
    $purgeable = [System.Collections.Generic.List[string]]::new()

    $total = $urlList.Count
    $position = 0
    # Nothing is printed with -WhatIf beyond what ShouldProcess prints.
    $quiet = [bool]$WhatIfPreference

    foreach ($url in $urlList) {
        $position++
        if (-not $url.StartsWith($required, [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.Add([PSCustomObject]@{ Url = $url; Status = 'Refused'; Detail = "The URL does not start with '$required'." })
            Write-SPSLabProgress -Position $position -Total $total -Quiet:$quiet -Status 'Refused' -Detail "The URL does not start with '$required'."
            continue
        }
        $marked = $null
        try {
            $marked = Get-SPSLabMarker -Url $url
        }
        catch {
            # A NoAccess lock makes the site unreadable. The name says it is a lab site: unlock it to read its marker.
            if (-not $PSCmdlet.ShouldProcess($url, 'Unlock the locked lab site collection to read its marker')) {
                $result.Add([PSCustomObject]@{ Url = $url; Status = 'NotRemoved'; Detail = 'The site is locked and cannot be read: not confirmed.' })
                Write-SPSLabProgress -Position $position -Total $total -Quiet:$quiet -Status 'NotRemoved' -Detail 'The site is locked and cannot be read: not confirmed.'
                continue
            }
            Set-SPSite -Identity $url -LockState Unlock -ErrorAction SilentlyContinue
            try {
                $marked = Get-SPSLabMarker -Url $url
            }
            catch {
                $result.Add([PSCustomObject]@{ Url = $url; Status = 'Refused'; Detail = "The site cannot be read, so its lab marker cannot be checked: $($_.Exception.Message)" })
                Write-SPSLabProgress -Position $position -Total $total -Quiet:$quiet -Status 'Refused' -Detail "The site cannot be read, so its lab marker cannot be checked: $($_.Exception.Message)"
                continue
            }
        }
        if ($null -eq $marked) {
            $result.Add([PSCustomObject]@{ Url = $url; Status = 'Absent'; Detail = 'The site collection does not exist.' })
            Write-SPSLabProgress -Position $position -Total $total -Quiet:$quiet -Status 'Absent' -Detail 'The site collection does not exist.'
            if ($PSCmdlet.ParameterSetName -eq 'Manifest') {
                # It is a lab site of the manifest that was removed before: its entry in the deleted sites may still be there.
                $purgeable.Add(([System.Uri]$url).AbsolutePath)
            }
            continue
        }
        if (-not $marked) {
            $result.Add([PSCustomObject]@{ Url = $url; Status = 'Refused'; Detail = 'The root web does not carry the lab marker: this is not a lab site.' })
            Write-SPSLabProgress -Position $position -Total $total -Quiet:$quiet -Status 'Refused' -Detail 'The root web does not carry the lab marker: this is not a lab site.'
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($url, 'Remove the lab site collection')) {
            $result.Add([PSCustomObject]@{ Url = $url; Status = 'NotRemoved'; Detail = 'Not confirmed.' })
            Write-SPSLabProgress -Position $position -Total $total -Quiet:$quiet -Status 'NotRemoved' -Detail 'Not confirmed.'
            continue
        }
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        Write-SPSLabProgress -Position $position -Total $total -Quiet:$quiet -Status 'Removing' -Detail $url
        try {
            Set-SPSite -Identity $url -LockState Unlock -ErrorAction SilentlyContinue
            Remove-SPSite -Identity $url -Confirm:$false -ErrorAction Stop
            $result.Add([PSCustomObject]@{ Url = $url; Status = 'Removed'; Detail = '' })
            $purgeable.Add(([System.Uri]$url).AbsolutePath)
            Write-SPSLabProgress -Position $position -Total $total -Quiet:$quiet -Status 'Removed' -Seconds $timer.Elapsed.TotalSeconds
        }
        catch {
            $result.Add([PSCustomObject]@{ Url = $url; Status = 'Failed'; Detail = $_.Exception.Message })
            Write-SPSLabProgress -Position $position -Total $total -Quiet:$quiet -Status 'Failed' -Detail $_.Exception.Message -Seconds $timer.Elapsed.TotalSeconds
        }
    }

    if ($purgeable.Count -gt 0) {
        foreach ($deleted in @(Get-SPDeletedSite -WebApplication $baseUrl -ErrorAction SilentlyContinue)) {
            if ($purgeable -notcontains [System.String]$deleted.Path) {
                continue
            }
            if (-not $PSCmdlet.ShouldProcess([System.String]$deleted.Path, 'Purge the deleted lab site collection')) {
                continue
            }
            try {
                Remove-SPDeletedSite -Identity $deleted.SiteId -Confirm:$false -ErrorAction Stop
            }
            catch {
                Write-Verbose -Message "The deleted site '$($deleted.Path)' could not be purged: $($_.Exception.Message)"
            }
        }
    }
    return $result.ToArray()
}

Export-ModuleMember -Function @(
    'Get-SPSLabScenario'
    'Get-SPSLabThreshold'
    'New-SPSLabSettings'
    'New-SPSLabFixture'
    'Test-SPSLabExpectation'
    'Test-SPSLabResult'
    'Write-SPSLabReport'
    'Remove-SPSLabFixture'
)
