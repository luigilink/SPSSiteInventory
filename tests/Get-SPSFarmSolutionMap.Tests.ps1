# Behavior tests for Get-SPSFarmSolutionMap (the map of the farm solutions and of the features that each one registers). The farm is
# stand-ins: global functions for Get-SPSolution and Get-SPFeature that give objects with the members that SharePoint gives them, so that
# no farm is needed. A farm solution (SPSolution) has no property that lists its features, and the stand-ins have none either.
BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force

    function global:Get-SPSolution {
        [CmdletBinding()]
        param ()
        $global:SPSTestSolutions
    }

    # It fails as a cmdlet does, with a non-terminating error that only -ErrorAction Stop turns into an exception, and it gives the
    # definitions with no limit only when it is asked for.
    function global:Get-SPFeature {
        [CmdletBinding()]
        param ([System.String] $Limit)
        $global:SPSTestFeatureLimit.Add($Limit)
        if ($global:SPSTestFeatureFails) {
            Write-Error -Message 'The configuration database cannot be read.'
            return
        }
        $global:SPSTestFeatures
    }

    $script:NewSolution = {
        param ([System.String] $Name, [System.Guid] $Id, [System.Boolean] $Deployed = $true, [System.Boolean] $GlobalAssembly = $false)
        [PSCustomObject]@{
            Name                           = $Name
            Id                             = $Id
            Deployed                       = $Deployed
            DeploymentState                = $(if ($Deployed) { 'GlobalDeployed' } else { 'NotDeployed' })
            ContainsGlobalAssembly         = $GlobalAssembly
            ContainsCasPolicy              = $false
            ContainsWebApplicationResource = $false
            DeployedWebApplications        = @()
            DeployedServers                = @()
        }
    }

    $script:NewFeature = {
        param ([System.Guid] $Id, [System.Guid] $SolutionId, [System.String] $Scope = 'Web')
        [PSCustomObject]@{ Id = $Id; SolutionId = $SolutionId; Scope = $Scope; DisplayName = "Feature $Id" }
    }

    $script:IntranetId = [System.Guid]'6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'
    $script:ReportingId = [System.Guid]'0a0b0c0d-1111-2222-3333-444455556666'
    $script:Intranet = & $script:NewSolution 'contoso.intranet.wsp' $script:IntranetId -GlobalAssembly $true
    $script:Reporting = & $script:NewSolution 'contoso.reporting.wsp' $script:ReportingId
}

AfterAll {
    Remove-Item -Path Function:\Get-SPSolution, Function:\Get-SPFeature -ErrorAction SilentlyContinue
    Remove-Variable -Name SPSTestSolutions, SPSTestFeatures, SPSTestFeatureFails, SPSTestFeatureLimit -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-SPSFarmSolutionMap' {
    BeforeEach {
        $global:SPSTestFeatureLimit = [System.Collections.Generic.List[System.String]]::new()
        $global:SPSTestFeatureFails = $false
        $global:SPSTestFeatures = @()
        $global:SPSTestSolutions = @()
    }

    Context 'the features of a solution' {
        It 'gives the count, the ids and the scopes of the features that the farm registers for the solution' {
            $global:SPSTestSolutions = @($script:Intranet)
            $ids = 'f0000000-0000-0000-0000-000000000006', 'f0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000005',
            'f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000004', 'f0000000-0000-0000-0000-000000000003'
            $global:SPSTestFeatures = @($ids | ForEach-Object { & $script:NewFeature ([System.Guid]$_) $script:IntranetId $(if ($_ -like '*01') { 'Site' } else { 'Web' }) })

            $map = @(Get-SPSFarmSolutionMap)

            $map | Should -HaveCount 1
            $map[0].FeatureCount | Should -Be 6
            $map[0].FeatureIds | Should -HaveCount 6
            ($map[0].FeatureIds -join ' ') | Should -Be (($ids | Sort-Object) -join ' ')
            ($map[0].FeatureScopes -join ' ') | Should -Be 'Site Web'
        }

        It 'gives no feature to a solution that registers none, and not the one that an unread property would count' {
            $global:SPSTestSolutions = @($script:Intranet)
            $global:SPSTestFeatures = @(& $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000001') $script:ReportingId)
            @($script:Intranet.PSObject.Properties.Name -like '*Feature*') | Should -HaveCount 0

            $map = @(Get-SPSFarmSolutionMap)

            $map[0].FeatureCount | Should -Be 0
            $map[0].FeatureCount | Should -BeOfType [System.Int32]
            @($map[0].FeatureIds) | Should -HaveCount 0
            @($map[0].FeatureScopes) | Should -HaveCount 0
        }

        It 'gives each solution its own features and ignores the features that no solution registers' {
            $global:SPSTestSolutions = @($script:Intranet, $script:Reporting)
            $global:SPSTestFeatures = @(
                & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000001') $script:IntranetId 'Site'
                & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000002') $script:ReportingId 'Web'
                & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000003') $script:ReportingId 'WebApplication'
                & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000004') ([System.Guid]::Empty) 'Farm'
                & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000005') ([System.Guid]::Empty) 'Web'
            )

            $map = @(Get-SPSFarmSolutionMap)

            $map[0].SolutionName | Should -Be 'contoso.intranet.wsp'
            $map[0].FeatureCount | Should -Be 1
            ($map[0].FeatureIds -join ' ') | Should -Be 'f0000000-0000-0000-0000-000000000001'
            ($map[0].FeatureScopes -join ' ') | Should -Be 'Site'
            $map[1].SolutionName | Should -Be 'contoso.reporting.wsp'
            $map[1].FeatureCount | Should -Be 2
            ($map[1].FeatureIds -join ' ') | Should -Be 'f0000000-0000-0000-0000-000000000002 f0000000-0000-0000-0000-000000000003'
            ($map[1].FeatureScopes -join ' ') | Should -Be 'Web WebApplication'
        }

        It 'counts a feature once when the farm has its definition for more than one compatibility level' {
            $global:SPSTestSolutions = @($script:Intranet)
            $first = & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000001') $script:IntranetId 'Site'
            $second = & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000002') $script:IntranetId 'Web'
            $global:SPSTestFeatures = @($first, $first, $second, $first, $second)

            $map = @(Get-SPSFarmSolutionMap -WarningVariable warning -WarningAction SilentlyContinue)

            $map[0].FeatureCount | Should -Be 2
            @($map[0].FeatureIds) | Should -HaveCount 2
            @($warning) | Should -HaveCount 0
        }

        It 'counts a feature whose scope is not given, and does not list an empty scope' {
            $global:SPSTestSolutions = @($script:Intranet)
            $global:SPSTestFeatures = @(
                & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000001') $script:IntranetId ''
                & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000002') $script:IntranetId 'Site'
            )

            $map = @(Get-SPSFarmSolutionMap)

            $map[0].FeatureCount | Should -Be 2
            @($map[0].FeatureScopes) | Should -HaveCount 1
            $map[0].FeatureScopes[0] | Should -Be 'Site'
        }

        It 'gives no feature to a solution that is added and not deployed, as the farm registers none' {
            $notDeployed = & $script:NewSolution 'contoso.new.wsp' ([System.Guid]'99999999-9999-9999-9999-999999999999') -Deployed $false
            $global:SPSTestSolutions = @($script:Intranet, $notDeployed)
            $global:SPSTestFeatures = @(& $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000001') $script:IntranetId 'Site')

            $map = @(Get-SPSFarmSolutionMap)

            $map[1].Deployed | Should -BeFalse
            $map[1].DeploymentState | Should -Be 'NotDeployed'
            $map[1].FeatureCount | Should -Be 0
            @($map[1].FeatureIds) | Should -HaveCount 0
            $map[0].FeatureCount | Should -Be 1
        }

        It 'reads the definitions of the farm once, with no limit, for all the solutions' {
            $global:SPSTestSolutions = @($script:Intranet, $script:Reporting, (& $script:NewSolution 'contoso.third.wsp' ([System.Guid]'12345678-1234-1234-1234-123456789012')))

            $null = Get-SPSFarmSolutionMap

            $global:SPSTestFeatureLimit | Should -HaveCount 1
            $global:SPSTestFeatureLimit[0] | Should -Be 'All'
        }

        It 'skips a definition that cannot be read and keeps the others' {
            $global:SPSTestSolutions = @($script:Intranet)
            $unreadable = & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000002') $script:IntranetId
            $unreadable.PSObject.Properties.Remove('SolutionId')
            $unreadable | Add-Member -MemberType ScriptProperty -Name SolutionId -Value { throw 'The definition cannot be read.' }
            $global:SPSTestFeatures = @(
                & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000001') $script:IntranetId 'Site'
                $unreadable
                & $script:NewFeature ([System.Guid]'f0000000-0000-0000-0000-000000000003') $script:IntranetId 'Web'
            )

            $map = @(Get-SPSFarmSolutionMap -WarningVariable warning -WarningAction SilentlyContinue)

            $map[0].FeatureCount | Should -Be 2
            ($map[0].FeatureIds -join ' ') | Should -Be 'f0000000-0000-0000-0000-000000000001 f0000000-0000-0000-0000-000000000003'
            @($warning) | Should -HaveCount 0
        }

        It 'warns and keeps the map when the farm does not give its feature definitions' {
            $global:SPSTestSolutions = @($script:Intranet, $script:Reporting)
            $global:SPSTestFeatureFails = $true

            $map = @(Get-SPSFarmSolutionMap -WarningVariable warning -WarningAction SilentlyContinue)

            @($warning) | Should -HaveCount 1
            $warning[0].Message | Should -Match 'Could not read the feature definitions of the farm'
            $warning[0].Message | Should -Match 'UsesCustomFarmFeature'
            $warning[0].Message | Should -Match 'The configuration database cannot be read'
            $map | Should -HaveCount 2
            $map[0].ContainsGlobalAssembly | Should -BeTrue
            $map[0].IsFullTrustCode | Should -BeTrue
            $map[0].FeatureCount | Should -Be 0
            @($map[0].FeatureIds) | Should -HaveCount 0
            $map[1].FeatureCount | Should -Be 0
        }

        It 'gives the ids in the form that the farm uses, which is the one that the site features are matched on' {
            $global:SPSTestSolutions = @($script:Intranet)
            $global:SPSTestFeatures = @(& $script:NewFeature ([System.Guid]'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE') $script:IntranetId 'Site')

            $map = @(Get-SPSFarmSolutionMap)

            $map[0].FeatureIds[0] | Should -BeExactly 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            $map[0].SolutionId | Should -BeExactly '6f1a8b40-3c2d-4e5f-9a7b-1c2d3e4f5a6b'
        }
    }

    Context 'the rest of the map' {
        It 'gives nothing when the farm has no solution' {
            $global:SPSTestSolutions = @()

            @(Get-SPSFarmSolutionMap).Count | Should -Be 0
        }

        It 'gives the properties that the reports read' {
            $global:SPSTestSolutions = @($script:Intranet)

            $map = @(Get-SPSFarmSolutionMap)

            ($map[0].PSObject.Properties.Name -join ' ') | Should -Be ('SolutionName SolutionId Deployed DeploymentState IsCustom ContainsGlobalAssembly ContainsCasPolicy ' +
                'ContainsWebApplicationResource IsFullTrustCode DeployedWebApplicationCount DeployedServerCount FeatureCount FeatureScopes FeatureIds')
        }

        It 'flags a custom solution that deploys a global assembly as full-trust code, and only that one' {
            $microsoft = & $script:NewSolution 'microsoft.sharepoint.wsp' ([System.Guid]'11111111-1111-1111-1111-111111111111') -GlobalAssembly $true
            $declarative = & $script:NewSolution 'contoso.declarative.wsp' ([System.Guid]'22222222-2222-2222-2222-222222222222')
            $global:SPSTestSolutions = @($script:Intranet, $microsoft, $declarative)

            $map = @(Get-SPSFarmSolutionMap)

            $map[0].IsCustom | Should -BeTrue
            $map[0].IsFullTrustCode | Should -BeTrue
            $map[1].IsCustom | Should -BeFalse
            $map[1].IsFullTrustCode | Should -BeFalse
            $map[2].IsCustom | Should -BeTrue
            $map[2].IsFullTrustCode | Should -BeFalse
        }
    }
}
