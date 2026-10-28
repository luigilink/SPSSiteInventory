BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'tools/lab/SPSInventoryLab.psm1') -Force
    $script:ModuleName = 'SPSInventoryLab'

    # The SharePoint commands, as stubs, so that they can be mocked. A real farm is never touched here.
    function global:New-SPSite { [CmdletBinding()] param ($Url, $OwnerAlias, $Template, $Name, $Language, $ContentDatabase) throw 'Unmocked SharePoint call: New-SPSite' }
    function global:Get-SPSite { [CmdletBinding()] param ($Identity, $WebApplication, $ContentDatabase, $Limit) throw 'Unmocked SharePoint call: Get-SPSite' }
    function global:Get-SPWebApplication { [CmdletBinding()] param ($Identity) throw 'Unmocked SharePoint call: Get-SPWebApplication' }
    function global:Set-SPSite { [CmdletBinding(SupportsShouldProcess = $true)] param ($Identity, $LockState) throw 'Unmocked SharePoint call: Set-SPSite' }
    function global:Remove-SPSite { [CmdletBinding(SupportsShouldProcess = $true)] param ($Identity) throw 'Unmocked SharePoint call: Remove-SPSite' }
    function global:Get-SPDeletedSite { [CmdletBinding()] param ($WebApplication, $ContentDatabase, $Limit) throw 'Unmocked SharePoint call: Get-SPDeletedSite' }
    function global:Remove-SPDeletedSite { [CmdletBinding(SupportsShouldProcess = $true)] param ($Identity) throw 'Unmocked SharePoint call: Remove-SPDeletedSite' }

    function global:New-LabFakeSite {
        param ([System.String] $Url, [System.Boolean] $Marked = $true)

        $properties = @{}
        if ($Marked) { $properties['SPSInventoryLab'] = 'true' }
        $web = [PSCustomObject]@{ AllProperties = $properties }
        $web | Add-Member -MemberType ScriptMethod -Name Update -Value { }
        $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $global:LabDisposed++ }
        $site = [PSCustomObject]@{ Url = $Url; RootWeb = $web }
        $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $global:LabDisposed++ }
        return $site
    }
}

AfterAll {
    foreach ($name in @('New-SPSite', 'Get-SPSite', 'Get-SPWebApplication', 'Set-SPSite', 'Remove-SPSite', 'Get-SPDeletedSite', 'Remove-SPDeletedSite', 'New-LabFakeSite')) {
        Remove-Item -Path "function:global:$name" -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name LabDisposed, LabCreated, LabContext -Scope Global -ErrorAction SilentlyContinue
}

Describe 'New-SPSLabFixture' {
    BeforeEach {
        $global:LabDisposed = 0
        $global:LabCreated = [System.Collections.Generic.List[object]]::new()
        $global:LabContext = $null
        $script:ManifestPath = Join-Path -Path $TestDrive -ChildPath ('manifest-{0}.json' -f [guid]::NewGuid())

        Mock -ModuleName $script:ModuleName Get-SPWebApplication { [PSCustomObject]@{ Url = 'https://lab/' } }
        Mock -ModuleName $script:ModuleName Get-SPSite { $null }
        Mock -ModuleName $script:ModuleName New-SPSite {
            $site = New-LabFakeSite -Url $Url -Marked $false
            $global:LabCreated.Add([PSCustomObject]@{ Url = $Url; Owner = $OwnerAlias; Template = $Template; Name = $Name; Language = $Language; Site = $site })
            $site
        }
        Mock -ModuleName $script:ModuleName Get-SPSLabScenario {
            @(
                [PSCustomObject]@{ Name = 'ok'; Description = 'ok'; Template = 'STS#0'; Expect = @(); Provision = { param ($Context) $global:LabContext = $Context } }
                [PSCustomObject]@{ Name = 'needs-engine'; Description = 'skip'; Template = 'STS#0'; Expect = @(); Provision = { param ($Context) throw 'SKIP: no 2010 engine on this farm.' } }
                [PSCustomObject]@{ Name = 'broken'; Description = 'boom'; Template = 'BLOG#0'; Expect = @(); Provision = { param ($Context) throw 'The list could not be created.' } }
            ) | Where-Object { -not $Name -or $Name -contains $_.Name }
        }
    }

    It 'creates one site collection per scenario under /sites, with the prefix, the owner and the template' {
        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Owner 'CONTOSO\jc' -Confirm:$false

        $global:LabCreated.Count | Should -Be 3
        $global:LabCreated[0].Url | Should -Be 'https://lab/sites/spslab-ok'
        $global:LabCreated[0].Owner | Should -Be 'CONTOSO\jc'
        $global:LabCreated[0].Template | Should -Be 'STS#0'
        $global:LabCreated[0].Language | Should -Be 1033
        $global:LabCreated[2].Template | Should -Be 'BLOG#0'
        $global:LabCreated[2].Url | Should -Be 'https://lab/sites/spslab-broken'
    }

    It 'marks every site collection as a lab site before the scenario runs' {
        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false

        foreach ($created in $global:LabCreated) {
            $created.Site.RootWeb.AllProperties['SPSInventoryLab'] | Should -Be 'true'
        }
    }

    It 'gives the scenario its context: the URL, the web, the thresholds and the owner' {
        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Owner 'CONTOSO\jc' -Scenario 'ok' -Confirm:$false

        $global:LabContext.Url | Should -Be 'https://lab/sites/spslab-ok'
        $global:LabContext.Owner | Should -Be 'CONTOSO\jc'
        $global:LabContext.Web | Should -Not -BeNullOrEmpty
        $global:LabContext.Threshold.LargeListItemCount | Should -BeGreaterThan 0
    }

    It 'reports a scenario as Skipped or Failed without stopping the others, and writes the manifest' {
        $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false

        $manifest.Scenario | ForEach-Object { $_.Status } | Should -Be @('Created', 'Skipped', 'Failed')
        $manifest.Scenario[1].Detail | Should -Be 'no 2010 engine on this farm.'
        $manifest.Scenario[2].Detail | Should -Be 'The list could not be created.'
        $written = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
        $written.WebApplicationUrl | Should -Be 'https://lab'
        $written.Prefix | Should -Be 'spslab'
        @($written.Scenario).Count | Should -Be 3
        $written.Scenario[0].Url | Should -Be 'https://lab/sites/spslab-ok'
    }

    It 'disposes the site and its root web, even when the scenario fails' {
        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false

        $global:LabDisposed | Should -Be 6
    }

    It 'records the site collection of a scenario that fails after it was created, so that it can be removed' {
        $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'broken' -Confirm:$false

        $manifest.Scenario[0].Status | Should -Be 'Failed'
        $manifest.Scenario[0].Url | Should -Be 'https://lab/sites/spslab-broken'
    }

    It 'reports a failure to create the site collection, and goes on' {
        Mock -ModuleName $script:ModuleName New-SPSite { throw 'The URL is already in use.' }

        $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'ok', 'broken' -Confirm:$false

        $manifest.Scenario | ForEach-Object { $_.Status } | Should -Be @('Failed', 'Failed')
        $manifest.Scenario[0].Detail | Should -Be 'The URL is already in use.'
    }

    It 'leaves an existing site collection alone and says to remove the lab first' {
        Mock -ModuleName $script:ModuleName Get-SPSite { if ($Identity -eq 'https://lab/sites/spslab-ok') { New-LabFakeSite -Url $Identity } }

        $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false

        $manifest.Scenario[0].Status | Should -Be 'Skipped'
        $manifest.Scenario[0].Detail | Should -Match 'remove the lab first'
        $global:LabCreated.Count | Should -Be 2
    }

    It 'builds only the scenarios that are asked for' {
        $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'ok' -Prefix 'lab42' -Confirm:$false

        @($manifest.Scenario).Count | Should -Be 1
        $global:LabCreated[0].Url | Should -Be 'https://lab/sites/lab42-ok'
    }

    It 'keeps the lab in the content database of the web application, and says why, when the commands of the content database are not available' {
        $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable shown

        $manifest.ContentDatabase | Should -BeNullOrEmpty
        $manifest.ContentDatabaseCreated | Should -BeFalse
        $global:LabCreated.Count | Should -Be 3
        $note = @($shown | ForEach-Object { [System.String]$_.MessageData }) | Where-Object { $_ -like 'No content database*' }
        $note | Should -Match 'Get-SPContentDatabase is not available'
    }

    It 'prints a line before each creation and a result line with the status and the elapsed seconds after it' {
        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -NoContentDatabase -Confirm:$false -InformationVariable progress

        $line = @($progress | ForEach-Object { [System.String]$_.MessageData })
        $line | Should -HaveCount 6
        $line[0] | Should -Be '[1/3] Creating https://lab/sites/spslab-ok ...'
        $line[1] | Should -Match '^\[1/3\] Created in \d+ s$'
        $line[2] | Should -Be '[2/3] Creating https://lab/sites/spslab-needs-engine ...'
        $line[3] | Should -Match '^\[2/3\] Skipped in \d+ s: no 2010 engine on this farm\.$'
        $line[4] | Should -Be '[3/3] Creating https://lab/sites/spslab-broken ...'
        $line[5] | Should -Match '^\[3/3\] Failed in \d+ s: The list could not be created\.$'
    }

    It 'prints a failure to create the site collection on one line' {
        Mock -ModuleName $script:ModuleName New-SPSite { throw "The URL is`r`n  already in use." }

        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'ok' -NoContentDatabase -Confirm:$false -InformationVariable progress

        [System.String]@($progress)[1].MessageData | Should -Match '^\[1/1\] Failed in \d+ s: The URL is already in use\.$'
    }

    It 'prints that a site collection that already exists is skipped, without announcing a creation' {
        Mock -ModuleName $script:ModuleName Get-SPSite { if ($Identity -eq 'https://lab/sites/spslab-ok') { New-LabFakeSite -Url $Identity } }

        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'ok' -NoContentDatabase -Confirm:$false -InformationVariable progress

        @($progress) | Should -HaveCount 1
        [System.String]@($progress)[0].MessageData | Should -Be '[1/1] Skipped: The site collection already exists: remove the lab first.'
    }

    It 'prints nothing with -WhatIf, beyond what ShouldProcess prints' {
        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -WhatIf -InformationVariable progress

        @($progress) | Should -HaveCount 0
    }

    It 'creates nothing and writes no manifest with -WhatIf' {
        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -WhatIf

        $global:LabCreated.Count | Should -Be 0
        Test-Path -LiteralPath $script:ManifestPath | Should -BeFalse
    }

    It 'creates nothing for a scenario that is not confirmed' {
        $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false -Scenario 'ok'
        $global:LabCreated.Clear()

        $declined = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'ok' -WhatIf

        $manifest.Scenario[0].Status | Should -Be 'Created'
        $declined.Scenario[0].Status | Should -Be 'NotCreated'
        $global:LabCreated.Count | Should -Be 0
    }

    It 'refuses a prefix that is not lowercase letters and digits' {
        { New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Prefix 'Bad Prefix' -Confirm:$false } | Should -Throw
        { New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Prefix 'a' -Confirm:$false } | Should -Throw
        $global:LabCreated.Count | Should -Be 0
    }

    It 'fails, saying what to do, when no scenario matches' {
        { New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'nothing' -Confirm:$false } | Should -Throw '*No scenario matches*'
        $global:LabCreated.Count | Should -Be 0
    }

    It 'fails when the web application does not exist, before creating anything' {
        Mock -ModuleName $script:ModuleName Get-SPWebApplication { throw 'Cannot find the web application.' }

        { New-SPSLabFixture -WebApplicationUrl 'https://nope' -ManifestPath $script:ManifestPath -Confirm:$false } | Should -Throw '*Cannot find the web application*'
        $global:LabCreated.Count | Should -Be 0
    }

    It 'fails, saying what to do, when the SharePoint commands are not available' {
        Mock -ModuleName $script:ModuleName Get-Command { $null } -ParameterFilter { $Name -eq 'New-SPSite' }

        { New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false } | Should -Throw '*SharePoint Management Shell*'
        $global:LabCreated.Count | Should -Be 0
        Should -Invoke -ModuleName $script:ModuleName Get-SPWebApplication -Times 0 -Exactly
    }
}

Describe 'Remove-SPSLabFixture' {
    BeforeAll {
        $script:Sites = @{
            'https://lab/sites/spslab-ok'      = $true
            'https://lab/sites/spslab-locked'  = $true
            'https://lab/sites/spslab-lookalike' = $false
            'https://lab/sites/other-ok'       = $true
        }
    }

    BeforeEach {
        $global:LabDisposed = 0
        $global:LabRemoved = [System.Collections.Generic.List[string]]::new()
        $global:LabUnlocked = [System.Collections.Generic.List[string]]::new()
        $global:LabPurged = [System.Collections.Generic.List[string]]::new()
        $script:ManifestPath = Join-Path -Path $TestDrive -ChildPath ('manifest-{0}.json' -f [guid]::NewGuid())
        $manifest = [PSCustomObject]@{
            ManifestVersion = 1; WebApplicationUrl = 'https://lab'; Prefix = 'spslab'
            Scenario = @(
                [PSCustomObject]@{ Name = 'ok'; Url = 'https://lab/sites/spslab-ok'; Status = 'Created' }
                [PSCustomObject]@{ Name = 'locked'; Url = 'https://lab/sites/spslab-locked'; Status = 'Failed' }
                [PSCustomObject]@{ Name = 'lookalike'; Url = 'https://lab/sites/spslab-lookalike'; Status = 'Created' }
                [PSCustomObject]@{ Name = 'gone'; Url = 'https://lab/sites/spslab-gone'; Status = 'Created' }
                [PSCustomObject]@{ Name = 'other'; Url = 'https://lab/sites/other-ok'; Status = 'Created' }
            )
        }
        ConvertTo-Json -InputObject $manifest -Depth 5 | Set-Content -Path $script:ManifestPath -Encoding UTF8

        Mock -ModuleName $script:ModuleName Get-SPWebApplication { [PSCustomObject]@{ Url = 'https://lab/' } }
        Mock -ModuleName $script:ModuleName Get-SPSite {
            if ($null -ne $WebApplication) {
                return @($script:Sites.Keys | ForEach-Object { [PSCustomObject]@{ Url = $_ } })
            }
            if ($null -ne $Identity -and $script:Sites.ContainsKey([System.String]$Identity)) { New-LabFakeSite -Url $Identity -Marked $script:Sites[[System.String]$Identity] }
        }
        Mock -ModuleName $script:ModuleName Set-SPSite { $global:LabUnlocked.Add([System.String]$Identity + ':' + [System.String]$LockState) }
        Mock -ModuleName $script:ModuleName Remove-SPSite { $global:LabRemoved.Add([System.String]$Identity) }
        Mock -ModuleName $script:ModuleName Get-SPDeletedSite {
            @(
                [PSCustomObject]@{ Path = '/sites/spslab-ok'; SiteId = [guid]'11111111-1111-1111-1111-111111111111' }
                [PSCustomObject]@{ Path = '/sites/finance'; SiteId = [guid]'22222222-2222-2222-2222-222222222222' }
                [PSCustomObject]@{ Path = '/sites/spslab-gone'; SiteId = [guid]'33333333-3333-3333-3333-333333333333' }
                [PSCustomObject]@{ Path = '/sites/spslab-lookalike'; SiteId = [guid]'44444444-4444-4444-4444-444444444444' }
                [PSCustomObject]@{ Path = '/sites/spslab-other-run'; SiteId = [guid]'55555555-5555-5555-5555-555555555555' }
            )
        }
        Mock -ModuleName $script:ModuleName Remove-SPDeletedSite { $global:LabPurged.Add([System.String]$Identity) }
    }

    AfterAll {
        Remove-Variable -Name LabRemoved, LabUnlocked, LabPurged -Scope Global -ErrorAction SilentlyContinue
    }

    It 'says how to find the lab sites without a manifest when the manifest does not exist' {
        { Remove-SPSLabFixture -ManifestPath (Join-Path -Path $TestDrive -ChildPath 'no-manifest.json') -Confirm:$false } | Should -Throw '*-WebApplicationUrl and -Prefix*'
        $global:LabRemoved.Count | Should -Be 0
    }

    It 'removes the lab sites of the manifest, unlocking them first' {
        $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

        $global:LabRemoved | Should -Be @('https://lab/sites/spslab-ok', 'https://lab/sites/spslab-locked')
        $global:LabUnlocked | Should -Contain 'https://lab/sites/spslab-locked:Unlock'
        ($result | Where-Object { $_.Url -eq 'https://lab/sites/spslab-ok' }).Status | Should -Be 'Removed'
    }

    It 'refuses a site that has no lab marker, even with the right prefix' {
        $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

        $lookalike = $result | Where-Object { $_.Url -eq 'https://lab/sites/spslab-lookalike' }
        $lookalike.Status | Should -Be 'Refused'
        $lookalike.Detail | Should -Match 'lab marker'
        $global:LabRemoved | Should -Not -Contain 'https://lab/sites/spslab-lookalike'
    }

    It 'refuses a URL that does not start with the prefix, without even opening it' {
        $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

        $other = $result | Where-Object { $_.Url -eq 'https://lab/sites/other-ok' }
        $other.Status | Should -Be 'Refused'
        $other.Detail | Should -Match 'https://lab/sites/spslab-'
        $global:LabRemoved | Should -Not -Contain 'https://lab/sites/other-ok'
        Should -Invoke -ModuleName $script:ModuleName Get-SPSite -ParameterFilter { $Identity -eq 'https://lab/sites/other-ok' } -Times 0 -Exactly
    }

    It 'reports a site that is already gone' {
        $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

        ($result | Where-Object { $_.Url -eq 'https://lab/sites/spslab-gone' }).Status | Should -Be 'Absent'
    }

    It 'purges the deleted sites that it removed and those of the manifest that were removed before, so that the lab can be built again' {
        $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

        @($global:LabPurged | Sort-Object) | Should -Be @('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333')
    }

    It 'does not purge a lookalike that was refused, a lab site of another run, or a site that is not a lab site' {
        $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

        $global:LabPurged | Should -Not -Contain '44444444-4444-4444-4444-444444444444'
        $global:LabPurged | Should -Not -Contain '55555555-5555-5555-5555-555555555555'
        $global:LabPurged | Should -Not -Contain '22222222-2222-2222-2222-222222222222'
    }

    It 'purges nothing when no removal was approved' {
        $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -WhatIf

        $global:LabPurged.Count | Should -Be 0
        Should -Invoke -ModuleName $script:ModuleName Remove-SPDeletedSite -Times 0 -Exactly
    }

    It 'purges only what a removal of this run produced when the lab is found by prefix' {
        $null = Remove-SPSLabFixture -WebApplicationUrl 'https://lab' -Prefix 'spslab' -Confirm:$false

        $global:LabPurged | Should -Be @('11111111-1111-1111-1111-111111111111')
    }

    It 'asks before it purges a deleted site' {
        Mock -ModuleName $script:ModuleName Remove-SPDeletedSite { $global:LabPurged.Add([System.String]$Identity) }

        $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false -WhatIf

        Should -Invoke -ModuleName $script:ModuleName Remove-SPSite -Times 0 -Exactly
        $global:LabPurged.Count | Should -Be 0
    }

    It 'refuses a manifest that is for another web application, and removes nothing' {
        Mock -ModuleName $script:ModuleName Get-SPWebApplication { [PSCustomObject]@{ Url = 'https://lab-b/' } }

        { Remove-SPSLabFixture -ManifestPath $script:ManifestPath -WebApplicationUrl 'https://lab-b' -Confirm:$false } | Should -Throw "*is for the web application 'https://lab', not for 'https://lab-b'*"
        $global:LabRemoved.Count | Should -Be 0
        $global:LabUnlocked.Count | Should -Be 0
        Should -Invoke -ModuleName $script:ModuleName Get-SPSite -Times 0 -Exactly
    }

    It 'refuses a manifest that is for another prefix, and removes nothing' {
        { Remove-SPSLabFixture -ManifestPath $script:ManifestPath -WebApplicationUrl 'https://lab' -Prefix 'lab42' -Confirm:$false } | Should -Throw "*is for the prefix 'spslab', not for 'lab42'*"
        $global:LabRemoved.Count | Should -Be 0
    }

    It 'uses a manifest that is for the web application and the prefix that are asked for' {
        $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -WebApplicationUrl 'https://LAB' -Prefix 'spslab' -Confirm:$false

        ($result | Where-Object { $_.Status -eq 'Removed' }).Count | Should -Be 2
    }

    It 'removes nothing with -WhatIf' {
        $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -WhatIf

        $global:LabRemoved.Count | Should -Be 0
        $global:LabUnlocked.Count | Should -Be 0
        ($result | Where-Object { $_.Url -eq 'https://lab/sites/spslab-ok' }).Status | Should -Be 'NotRemoved'
    }

    It 'finds the lab sites by prefix when there is no manifest, and still requires the marker' {
        $result = Remove-SPSLabFixture -WebApplicationUrl 'https://lab' -Prefix 'spslab' -Confirm:$false

        @($result | Where-Object { $_.Status -eq 'Removed' } | ForEach-Object { $_.Url } | Sort-Object) | Should -Be @('https://lab/sites/spslab-locked', 'https://lab/sites/spslab-ok')
        ($result | Where-Object { $_.Url -eq 'https://lab/sites/spslab-lookalike' }).Status | Should -Be 'Refused'
        $result.Url | Should -Not -Contain 'https://lab/sites/other-ok'
    }

    It 'unlocks a lab site that a NoAccess lock made unreadable, reads its marker, then removes it' {
        $global:LabLockedUrls = [System.Collections.Generic.List[string]]::new()
        $global:LabLockedUrls.Add('https://lab/sites/spslab-ok')
        Mock -ModuleName $script:ModuleName Get-SPSite {
            if ($null -ne $WebApplication -or $Identity -ne 'https://lab/sites/spslab-ok') { return $null }
            $web = [PSCustomObject]@{ AllProperties = @{ SPSInventoryLab = 'true' } }
            $web | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            $site = [PSCustomObject]@{ Url = $Identity }
            $site | Add-Member -MemberType ScriptProperty -Name RootWeb -Value {
                if ($global:LabLockedUrls.Contains($this.Url)) { throw 'This site collection is locked.' }
                $web
            }.GetNewClosure()
            $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            $site
        }
        Mock -ModuleName $script:ModuleName Set-SPSite { $global:LabUnlocked.Add([System.String]$Identity + ':' + [System.String]$LockState); [void]$global:LabLockedUrls.Remove([System.String]$Identity) }
        $path = Join-Path -Path $TestDrive -ChildPath 'locked-manifest.json'
        $manifest = [PSCustomObject]@{ ManifestVersion = 1; WebApplicationUrl = 'https://lab'; Prefix = 'spslab'; Scenario = @([PSCustomObject]@{ Name = 'ok'; Url = 'https://lab/sites/spslab-ok'; Status = 'Created' }) }
        ConvertTo-Json -InputObject $manifest -Depth 5 | Set-Content -Path $path -Encoding UTF8

        $result = Remove-SPSLabFixture -ManifestPath $path -Confirm:$false

        $result[0].Status | Should -Be 'Removed'
        $global:LabUnlocked[0] | Should -Be 'https://lab/sites/spslab-ok:Unlock'
        $global:LabRemoved | Should -Contain 'https://lab/sites/spslab-ok'
    }

    It 'does not unlock a locked lab site with -WhatIf, and does not remove it' {
        $global:LabLockedUrls = [System.Collections.Generic.List[string]]::new()
        $global:LabLockedUrls.Add('https://lab/sites/spslab-ok')
        Mock -ModuleName $script:ModuleName Get-SPSite {
            $site = [PSCustomObject]@{ Url = $Identity }
            $site | Add-Member -MemberType ScriptProperty -Name RootWeb -Value { throw 'This site collection is locked.' }
            $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            $site
        }
        $path = Join-Path -Path $TestDrive -ChildPath 'locked-whatif-manifest.json'
        $manifest = [PSCustomObject]@{ ManifestVersion = 1; WebApplicationUrl = 'https://lab'; Prefix = 'spslab'; Scenario = @([PSCustomObject]@{ Name = 'ok'; Url = 'https://lab/sites/spslab-ok'; Status = 'Created' }) }
        ConvertTo-Json -InputObject $manifest -Depth 5 | Set-Content -Path $path -Encoding UTF8

        $result = Remove-SPSLabFixture -ManifestPath $path -WhatIf

        $result[0].Status | Should -Be 'NotRemoved'
        $global:LabUnlocked.Count | Should -Be 0
        $global:LabRemoved.Count | Should -Be 0
    }

    It 'refuses a site that is still unreadable after the unlock' {
        Mock -ModuleName $script:ModuleName Get-SPSite {
            $site = [PSCustomObject]@{ Url = $Identity }
            $site | Add-Member -MemberType ScriptProperty -Name RootWeb -Value { throw 'The content database is offline.' }
            $site | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            $site
        }
        $path = Join-Path -Path $TestDrive -ChildPath 'offline-manifest.json'
        $manifest = [PSCustomObject]@{ ManifestVersion = 1; WebApplicationUrl = 'https://lab'; Prefix = 'spslab'; Scenario = @([PSCustomObject]@{ Name = 'ok'; Url = 'https://lab/sites/spslab-ok'; Status = 'Created' }) }
        ConvertTo-Json -InputObject $manifest -Depth 5 | Set-Content -Path $path -Encoding UTF8

        $result = Remove-SPSLabFixture -ManifestPath $path -Confirm:$false

        $result[0].Status | Should -Be 'Refused'
        $result[0].Detail | Should -Match 'root web of the site collection cannot be read'
        $global:LabRemoved.Count | Should -Be 0
    }

    It 'prints a line before each removal and a result line with the elapsed seconds, and says what it does not remove' {
        $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable progress

        $line = @($progress | ForEach-Object { [System.String]$_.MessageData })
        $line | Should -Contain '[1/5] Removing https://lab/sites/spslab-ok ...'
        @($line | Where-Object { $_ -match '^\[1/5\] Removed in \d+ s$' }) | Should -HaveCount 1
        $line | Should -Contain '[2/5] Removing https://lab/sites/spslab-locked ...'
        $line | Should -Contain '[3/5] Refused: The root web does not carry the lab marker: this is not a lab site.'
        $line | Should -Contain '[4/5] Absent: The site collection does not exist.'
        $line | Should -Contain "[5/5] Refused: The URL does not start with 'https://lab/sites/spslab-'."
        $line | Should -Not -Contain '[3/5] Removing https://lab/sites/spslab-lookalike ...'
    }

    It 'prints a failed removal with the elapsed seconds' {
        Mock -ModuleName $script:ModuleName Remove-SPSite { throw 'The site is in use.' }

        $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable progress

        $line = @($progress | ForEach-Object { [System.String]$_.MessageData })
        @($line | Where-Object { $_ -match '^\[1/5\] Failed in \d+ s: The site is in use\.$' }) | Should -HaveCount 1
    }

    It 'prints nothing with -WhatIf, beyond what ShouldProcess prints' {
        $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -WhatIf -InformationVariable progress

        @($progress) | Should -HaveCount 0
    }

    It 'reports a failed removal and goes on' {
        Mock -ModuleName $script:ModuleName Remove-SPSite { if ($Identity -like '*-ok') { throw 'The site is in use.' } else { $global:LabRemoved.Add([System.String]$Identity) } }

        $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

        ($result | Where-Object { $_.Url -eq 'https://lab/sites/spslab-ok' }).Status | Should -Be 'Failed'
        ($result | Where-Object { $_.Url -eq 'https://lab/sites/spslab-ok' }).Detail | Should -Be 'The site is in use.'
        $global:LabRemoved | Should -Contain 'https://lab/sites/spslab-locked'
    }
}

Describe 'The content database of the lab' {
    BeforeAll {
        # Not defined for the other tests: without these commands, the lab stays in the content database of the web application.
        function global:Get-SPContentDatabase { [CmdletBinding()] param ($Identity) throw 'Unmocked SharePoint call: Get-SPContentDatabase' }
        function global:New-SPContentDatabase { [CmdletBinding(SupportsShouldProcess = $true)] param ($Name, $WebApplication, $MaxSiteCount, $WarningSiteCount) throw 'Unmocked SharePoint call: New-SPContentDatabase' }
        function global:Remove-SPContentDatabase { [CmdletBinding(SupportsShouldProcess = $true)] param ($Identity, [switch]$Force) throw 'Unmocked SharePoint call: Remove-SPContentDatabase' }
    }

    AfterAll {
        foreach ($name in @('Get-SPContentDatabase', 'New-SPContentDatabase', 'Remove-SPContentDatabase')) {
            Remove-Item -Path "function:global:$name" -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name LabCreated, LabDatabases, LabRemovedDatabase, LabRemoved, LabPurged -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'when the lab is created' {
        BeforeEach {
            $global:LabDisposed = 0
            $global:LabCreated = [System.Collections.Generic.List[object]]::new()
            $global:LabDatabases = [System.Collections.Generic.List[object]]::new()
            $script:ManifestPath = Join-Path -Path $TestDrive -ChildPath ('manifest-{0}.json' -f [guid]::NewGuid())

            Mock -ModuleName $script:ModuleName Get-SPWebApplication { [PSCustomObject]@{ Url = 'https://lab/' } }
            Mock -ModuleName $script:ModuleName Get-SPSite { $null }
            Mock -ModuleName $script:ModuleName Get-SPContentDatabase { $null }
            Mock -ModuleName $script:ModuleName New-SPContentDatabase {
                $global:LabDatabases.Add([PSCustomObject]@{ Name = $Name; WebApplication = $WebApplication; MaxSiteCount = $MaxSiteCount; WarningSiteCount = $WarningSiteCount })
            }
            Mock -ModuleName $script:ModuleName New-SPSite {
                $global:LabCreated.Add([PSCustomObject]@{ Url = $Url; ContentDatabase = $ContentDatabase })
                New-LabFakeSite -Url $Url -Marked $false
            }
            Mock -ModuleName $script:ModuleName Get-SPSLabScenario {
                @(
                    [PSCustomObject]@{ Name = 'one'; Description = 'one'; Template = 'STS#0'; Expect = @(); Provision = { param ($Context) $null = $Context } }
                    [PSCustomObject]@{ Name = 'two'; Description = 'two'; Template = 'STS#0'; Expect = @(); Provision = { param ($Context) $null = $Context } }
                    [PSCustomObject]@{ Name = 'three'; Description = 'three'; Template = 'STS#0'; Expect = @(); Provision = { param ($Context) $null = $Context } }
                ) | Where-Object { -not $Name -or $Name -contains $_.Name }
            }
        }

        It 'creates a content database with the prefix, attached to the web application, with room for just the scenarios, and creates the site collections in it' {
            $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabDatabases | Should -HaveCount 1
            $global:LabDatabases[0].Name | Should -Be 'spslab_Content'
            $global:LabDatabases[0].WebApplication.Url | Should -Be 'https://lab/'
            $global:LabDatabases[0].MaxSiteCount | Should -Be 5
            $global:LabDatabases[0].WarningSiteCount | Should -Be 0
            $global:LabCreated | Should -HaveCount 3
            foreach ($created in $global:LabCreated) { $created.ContentDatabase | Should -Be 'spslab_Content' }
            $manifest.ContentDatabase | Should -Be 'spslab_Content'
            $manifest.ContentDatabaseCreated | Should -BeTrue
        }

        It 'records the database in the manifest file' {
            $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Prefix 'labx' -Confirm:$false

            $written = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
            $written.ContentDatabase | Should -Be 'labx_Content'
            $written.ContentDatabaseCreated | Should -BeTrue
        }

        It 'takes the name that is asked for, when it starts with the prefix, and refuses one that does not' {
            $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -ContentDatabaseName 'spslab_Mine' -Confirm:$false

            $global:LabDatabases[0].Name | Should -Be 'spslab_Mine'
            { New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -ContentDatabaseName 'WSS_Content' -Confirm:$false } | Should -Throw "*must start with 'spslab_'*"
        }

        It 'sizes the database for the scenarios that are built' {
            $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'one' -Confirm:$false

            $global:LabDatabases[0].MaxSiteCount | Should -Be 3
        }

        It 'keeps the lab in the content database of the web application when the account cannot create a database, and says why' {
            Mock -ModuleName $script:ModuleName New-SPContentDatabase { throw 'CREATE DATABASE permission denied.' }

            $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable shown

            $global:LabCreated | Should -HaveCount 3
            foreach ($created in $global:LabCreated) { $created.ContentDatabase | Should -BeNullOrEmpty }
            $manifest.ContentDatabase | Should -BeNullOrEmpty
            $manifest.ContentDatabaseCreated | Should -BeFalse
            $note = @($shown | ForEach-Object { [System.String]$_.MessageData }) | Where-Object { $_ -like 'No content database*' }
            $note | Should -Match 'CREATE DATABASE permission denied'
            $note | Should -Match 'content database of the web application'
        }

        It 'creates no database with -NoContentDatabase, and calls none of its commands' {
            $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -NoContentDatabase -Confirm:$false

            Should -Invoke New-SPContentDatabase -ModuleName $script:ModuleName -Times 0 -Exactly
            Should -Invoke Get-SPContentDatabase -ModuleName $script:ModuleName -Times 0 -Exactly
            foreach ($created in $global:LabCreated) { $created.ContentDatabase | Should -BeNullOrEmpty }
            $manifest.ContentDatabase | Should -BeNullOrEmpty
            $manifest.ContentDatabaseCreated | Should -BeFalse
        }

        It 'uses a database of that name that already belongs to the web application, without reporting it as created' {
            Mock -ModuleName $script:ModuleName Get-SPContentDatabase { [PSCustomObject]@{ Name = $Identity; WebApplication = [PSCustomObject]@{ Url = 'https://lab/' } } }

            $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabDatabases | Should -HaveCount 0
            $manifest.ContentDatabase | Should -Be 'spslab_Content'
            $manifest.ContentDatabaseCreated | Should -BeFalse
            foreach ($created in $global:LabCreated) { $created.ContentDatabase | Should -Be 'spslab_Content' }
        }

        It 'does not use a database of that name that belongs to another web application' {
            Mock -ModuleName $script:ModuleName Get-SPContentDatabase { [PSCustomObject]@{ Name = $Identity; WebApplication = [PSCustomObject]@{ Url = 'https://other/' } } }

            $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable shown

            $global:LabDatabases | Should -HaveCount 0
            $manifest.ContentDatabase | Should -BeNullOrEmpty
            foreach ($created in $global:LabCreated) { $created.ContentDatabase | Should -BeNullOrEmpty }
            (@($shown | ForEach-Object { [System.String]$_.MessageData }) -join ' ') | Should -Match 'another web application|for the web application ''https://other'''
        }

        It 'creates no database with -WhatIf, and prints nothing beyond what ShouldProcess prints' {
            $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -WhatIf -InformationVariable shown

            $global:LabDatabases | Should -HaveCount 0
            @($shown) | Should -HaveCount 0
        }

        It 'goes on in the content database of the web application when the creation is not confirmed' {
            $manifest = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false -Scenario 'one'
            $global:LabDatabases.Clear()
            $global:LabCreated.Clear()

            $declined = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'one' -WhatIf

            $manifest.ContentDatabase | Should -Be 'spslab_Content'
            $declined.ContentDatabase | Should -BeNullOrEmpty
            $global:LabDatabases | Should -HaveCount 0
        }
    }

    Context 'when the lab is removed' {
        BeforeAll {
            $script:Urls = @('https://lab/sites/spslab-one', 'https://lab/sites/spslab-two', 'https://lab/sites/spslab-three')
        }

        BeforeEach {
            $global:LabDisposed = 0
            $global:LabRemoved = [System.Collections.Generic.List[string]]::new()
            $global:LabRemovedDatabase = [System.Collections.Generic.List[string]]::new()
            $global:LabPurged = [System.Collections.Generic.List[string]]::new()
            $script:InDatabase = @($script:Urls)
            $script:Exists = @($script:Urls)
            $script:Unmarked = @()
            $script:DeletedInDatabase = @()
            $script:DeletedInWebApplication = @()
            $script:DeletedListingFails = $false
            $script:DatabaseWebApplication = 'https://lab/'
            $script:DatabaseExists = $true
            $script:ManifestPath = Join-Path -Path $TestDrive -ChildPath ('manifest-{0}.json' -f [guid]::NewGuid())
            $script:WriteManifest = {
                param ($Database = 'spslab_Content', $Created = $true, $Prefix = 'spslab')
                $manifest = [ordered]@{
                    ManifestVersion = 1; WebApplicationUrl = 'https://lab'; Prefix = $Prefix
                    ContentDatabase = $Database; ContentDatabaseCreated = $Created
                    Scenario = @($script:Urls | ForEach-Object { [PSCustomObject]@{ Name = 'x'; Url = $_; Status = 'Created' } })
                }
                ConvertTo-Json -InputObject ([PSCustomObject]$manifest) -Depth 5 | Set-Content -Path $script:ManifestPath -Encoding UTF8
            }

            Mock -ModuleName $script:ModuleName Get-SPWebApplication { [PSCustomObject]@{ Url = 'https://lab/' } }
            Mock -ModuleName $script:ModuleName Get-SPContentDatabase {
                if ($script:DatabaseExists) { [PSCustomObject]@{ Name = $Identity; WebApplication = [PSCustomObject]@{ Url = $script:DatabaseWebApplication } } }
            }
            Mock -ModuleName $script:ModuleName Get-SPSite {
                if ($null -ne $ContentDatabase) { return @($script:InDatabase | ForEach-Object { New-LabFakeSite -Url $_ }) }
                if ($null -ne $Identity -and $script:Exists -contains [System.String]$Identity) { New-LabFakeSite -Url $Identity -Marked ($script:Unmarked -notcontains [System.String]$Identity) }
            }
            Mock -ModuleName $script:ModuleName Remove-SPContentDatabase { $global:LabRemovedDatabase.Add([System.String]$Identity) }
            Mock -ModuleName $script:ModuleName Remove-SPSite { $global:LabRemoved.Add([System.String]$Identity) }
            Mock -ModuleName $script:ModuleName Set-SPSite { }
            # The deleted site collections of the database, and those of the web application. The identity of a deleted site is its path, to know which one is purged.
            Mock -ModuleName $script:ModuleName Get-SPDeletedSite {
                if ($null -ne $ContentDatabase) {
                    if ($script:DeletedListingFails) { throw 'The deleted sites cannot be read.' }
                    return @($script:DeletedInDatabase | ForEach-Object { [PSCustomObject]@{ Path = $_; SiteId = $_ } })
                }
                @($script:DeletedInWebApplication | ForEach-Object { [PSCustomObject]@{ Path = $_; SiteId = $_ } })
            }
            Mock -ModuleName $script:ModuleName Remove-SPDeletedSite { $global:LabPurged.Add([System.String]$Identity) }
        }

        It 'removes the content database that the lab created, and the lab with it, without removing a site collection' {
            & $script:WriteManifest

            $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabRemovedDatabase | Should -Be @('spslab_Content')
            $global:LabRemoved | Should -HaveCount 0
            @($result | ForEach-Object { $_.Status }) | Should -Be @('Removed', 'Removed', 'Removed')
            $result[0].Detail | Should -Match "content database 'spslab_Content'"
            Should -Invoke Set-SPSite -ModuleName $script:ModuleName -Times 0 -Exactly
            Should -Invoke Remove-SPDeletedSite -ModuleName $script:ModuleName -Times 0 -Exactly
        }

        It 'removes a site collection of the manifest that is not in the database one by one, and the others with the database' {
            & $script:WriteManifest
            $script:InDatabase = @($script:Urls[0], $script:Urls[1])

            $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabRemovedDatabase | Should -Be @('spslab_Content')
            $global:LabRemoved | Should -Be @($script:Urls[2])
            @($result | ForEach-Object { $_.Url }) | Should -Be $script:Urls
            @($result | ForEach-Object { $_.Status }) | Should -Be @('Removed', 'Removed', 'Removed')
            $result[0].Detail | Should -Match "content database 'spslab_Content'"
            $result[1].Detail | Should -Match "content database 'spslab_Content'"
            $result[2].Detail | Should -BeNullOrEmpty
        }

        It 'purges the deleted entry of a site collection that it removed one by one, and no other' {
            & $script:WriteManifest
            $script:InDatabase = @($script:Urls[0], $script:Urls[1])
            $script:DeletedInWebApplication = @('/sites/spslab-three', '/sites/finance')

            $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabPurged | Should -Be @('/sites/spslab-three')
        }

        It 'reports as absent a site collection of the manifest that is not in the database and does not exist' {
            & $script:WriteManifest
            $script:InDatabase = @($script:Urls[0], $script:Urls[1])
            $script:Exists = @()

            $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabRemovedDatabase | Should -HaveCount 1
            $global:LabRemoved | Should -HaveCount 0
            ($result | Where-Object { $_.Url -eq $script:Urls[2] }).Status | Should -Be 'Absent'
            ($result | Where-Object { $_.Url -eq $script:Urls[0] }).Status | Should -Be 'Removed'
        }

        It 'refuses, outside the database, a site collection that has the name of the lab and no marker' {
            & $script:WriteManifest
            $script:InDatabase = @($script:Urls[0], $script:Urls[1])
            $script:Unmarked = @($script:Urls[2])

            $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabRemoved | Should -HaveCount 0
            ($result | Where-Object { $_.Url -eq $script:Urls[2] }).Status | Should -Be 'Refused'
            ($result | Where-Object { $_.Url -eq $script:Urls[2] }).Detail | Should -Match 'does not carry the lab marker'
        }

        It 'leaves the database, and removes the site collections one by one, when it holds a deleted site collection that is not in the manifest, which would be lost for good' {
            & $script:WriteManifest
            $script:DeletedInDatabase = @('/sites/spslab-one', '/sites/finance-old')
            $script:DeletedInWebApplication = @('/sites/finance-old')

            $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable shown

            $global:LabRemovedDatabase | Should -HaveCount 0
            $global:LabRemoved | Should -HaveCount 3
            (@($shown | ForEach-Object { [System.String]$_.MessageData }) -join ' ') | Should -Match 'deleted site collections that are not in the manifest, which would be lost for good: /sites/finance-old'
            $global:LabPurged | Should -HaveCount 0
            @($result | ForEach-Object { $_.Status }) | Should -Be @('Removed', 'Removed', 'Removed')
        }

        It 'does not count the deleted site collections of the lab itself, whatever the case of their path' {
            & $script:WriteManifest
            $script:DeletedInDatabase = @('/sites/spslab-one', '/sites/SPSLAB-two')

            $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabRemovedDatabase | Should -Be @('spslab_Content')
        }

        It 'treats a deleted site collection that has the name of the lab but is not in the manifest as foreign' {
            & $script:WriteManifest
            $script:DeletedInDatabase = @('/sites/spslab-other-run')

            $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabRemovedDatabase | Should -HaveCount 0
            $global:LabRemoved | Should -HaveCount 3
        }

        It 'lists all the deleted site collections of the database, not the first ones' {
            & $script:WriteManifest

            $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            Should -Invoke Get-SPDeletedSite -ModuleName $script:ModuleName -Times 1 -Exactly -ParameterFilter { $ContentDatabase -eq 'spslab_Content' -and $Limit -eq 'All' }
        }

        It 'leaves the database, and removes the site collections one by one, when its deleted site collections cannot be listed' {
            & $script:WriteManifest
            $script:DeletedListingFails = $true

            $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable shown

            $global:LabRemovedDatabase | Should -HaveCount 0
            $global:LabRemoved | Should -HaveCount 3
            (@($shown | ForEach-Object { [System.String]$_.MessageData }) -join ' ') | Should -Match 'deleted site collections could not be checked: The deleted sites cannot be read\.'
        }

        It 'leaves the database, and removes the site collections one by one, when it holds a site collection that is not in the manifest' {
            & $script:WriteManifest
            $script:InDatabase = @($script:Urls) + @('https://lab/sites/finance')

            $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable shown

            $global:LabRemovedDatabase | Should -HaveCount 0
            $global:LabRemoved | Should -HaveCount 3
            (@($shown | ForEach-Object { [System.String]$_.MessageData }) -join ' ') | Should -Match 'not in the manifest: https://lab/sites/finance'
            @($result | ForEach-Object { $_.Status }) | Should -Be @('Removed', 'Removed', 'Removed')
        }

        It 'does not remove a database that the lab did not create, or whose name does not start with the prefix, or that is not the one of the web application' {
            foreach ($case in @(
                    @{ Database = 'spslab_Content'; Created = $false; Reason = 'not-created' }
                    @{ Database = 'WSS_Content'; Created = $true; Reason = 'name' }
                )) {
                & $script:WriteManifest $case.Database $case.Created
                $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

                $global:LabRemovedDatabase | Should -HaveCount 0 -Because $case.Reason
            }
            & $script:WriteManifest
            $script:DatabaseWebApplication = 'https://other/'

            $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabRemovedDatabase | Should -HaveCount 0
        }

        It 'leaves the database, and removes the site collections one by one, when the site collections in it cannot be listed' {
            & $script:WriteManifest
            Mock -ModuleName $script:ModuleName Get-SPSite {
                if ($null -ne $ContentDatabase) { throw 'The database cannot be read.' }
                if ($null -ne $Identity -and $script:Urls -contains [System.String]$Identity) { New-LabFakeSite -Url $Identity -Marked $true }
            }

            $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable shown

            $global:LabRemovedDatabase | Should -HaveCount 0
            $global:LabRemoved | Should -HaveCount 3
            (@($shown | ForEach-Object { [System.String]$_.MessageData }) -join ' ') | Should -Match 'could not be listed: The database cannot be read\.'
            @($result | ForEach-Object { $_.Status }) | Should -Be @('Removed', 'Removed', 'Removed')
        }

        It 'removes the site collections one by one when the database does not exist any more, and when its removal fails' {
            & $script:WriteManifest
            $script:DatabaseExists = $false

            $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabRemovedDatabase | Should -HaveCount 0
            $global:LabRemoved | Should -HaveCount 3

            $global:LabRemoved.Clear()
            $script:DatabaseExists = $true
            Mock -ModuleName $script:ModuleName Remove-SPContentDatabase { throw 'The database is in use.' }

            $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable shown

            $global:LabRemoved | Should -HaveCount 3
            @($result) | Should -HaveCount 3
            (@($shown | ForEach-Object { [System.String]$_.MessageData }) -join ' ') | Should -Match 'could not be removed: The database is in use\.'
        }

        It 'removes nothing with -WhatIf' {
            & $script:WriteManifest

            $null = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -WhatIf

            $global:LabRemovedDatabase | Should -HaveCount 0
            $global:LabRemoved | Should -HaveCount 0
        }

        It 'works as before with a manifest that has no content database' {
            & $script:WriteManifest $null $false

            $result = Remove-SPSLabFixture -ManifestPath $script:ManifestPath -Confirm:$false

            $global:LabRemovedDatabase | Should -HaveCount 0
            $global:LabRemoved | Should -HaveCount 3
            @($result | ForEach-Object { $_.Status }) | Should -Be @('Removed', 'Removed', 'Removed')
        }
    }
}
