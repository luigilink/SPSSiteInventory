BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'tools/lab/SPSInventoryLab.psm1') -Force
    $script:ModuleName = 'SPSInventoryLab'

    # The SharePoint commands, as stubs, so that they can be mocked. A real farm is never touched here.
    function global:New-SPSite { [CmdletBinding()] param ($Url, $OwnerAlias, $Template, $Name, $Language) throw 'Unmocked SharePoint call: New-SPSite' }
    function global:Get-SPSite { [CmdletBinding()] param ($Identity, $WebApplication, $Limit) throw 'Unmocked SharePoint call: Get-SPSite' }
    function global:Get-SPWebApplication { [CmdletBinding()] param ($Identity) throw 'Unmocked SharePoint call: Get-SPWebApplication' }
    function global:Set-SPSite { [CmdletBinding(SupportsShouldProcess = $true)] param ($Identity, $LockState) throw 'Unmocked SharePoint call: Set-SPSite' }
    function global:Remove-SPSite { [CmdletBinding(SupportsShouldProcess = $true)] param ($Identity) throw 'Unmocked SharePoint call: Remove-SPSite' }
    function global:Get-SPDeletedSite { [CmdletBinding()] param ($WebApplication) throw 'Unmocked SharePoint call: Get-SPDeletedSite' }
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

    It 'prints a line before each creation and a result line with the status and the elapsed seconds after it' {
        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Confirm:$false -InformationVariable progress

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

        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'ok' -Confirm:$false -InformationVariable progress

        [System.String]@($progress)[1].MessageData | Should -Match '^\[1/1\] Failed in \d+ s: The URL is already in use\.$'
    }

    It 'prints that a site collection that already exists is skipped, without announcing a creation' {
        Mock -ModuleName $script:ModuleName Get-SPSite { if ($Identity -eq 'https://lab/sites/spslab-ok') { New-LabFakeSite -Url $Identity } }

        $null = New-SPSLabFixture -WebApplicationUrl 'https://lab' -ManifestPath $script:ManifestPath -Scenario 'ok' -Confirm:$false -InformationVariable progress

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
