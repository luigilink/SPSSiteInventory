BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $repoRoot 'src/Modules/SPSSiteInventory.Common/SPSSiteInventory.Common.psd1') -Force
}

Describe 'Get-SPSWorkflowRunningInstanceCount' {
    It 'returns null when Workflow Manager is disconnected' {
        $result = InModuleScope SPSSiteInventory.Common {
            $manager = [PSCustomObject]@{
                IsConnected = $false
            }

            Get-SPSWorkflowRunningInstanceCount -Web ([PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/team' }) -WorkflowManager $manager
        }

        $result | Should -BeNullOrEmpty
    }

    It 'enumerates instances by subscription and counts only active statuses' {
        $result = InModuleScope SPSSiteInventory.Common {
            $subscriptions = @(
                [PSCustomObject]@{ Id = [guid]::NewGuid() },
                [PSCustomObject]@{ Id = [guid]::NewGuid() }
            )

            $subscriptionService = [PSCustomObject]@{}
            $subscriptionService | Add-Member -MemberType ScriptMethod -Name EnumerateSubscriptions -Value {
                return $subscriptions
            }

            $instanceService = [PSCustomObject]@{}
            $instanceService | Add-Member -MemberType ScriptMethod -Name Enumerate -Value {
                param ($subscription)
                if ($subscription.Id -eq $subscriptions[0].Id) {
                    return @(
                        [PSCustomObject]@{ Status = 'Started' },
                        [PSCustomObject]@{ Status = 'NotStarted' },
                        [PSCustomObject]@{ Status = 'Canceling' }
                    )
                }

                return @(
                    [PSCustomObject]@{ InstanceStatus = 'Running' },
                    [PSCustomObject]@{ Status = 'Completed' }
                )
            }

            $manager = [PSCustomObject]@{
                IsConnected = $true
            }
            $manager | Add-Member -MemberType ScriptMethod -Name GetWorkflowSubscriptionService -Value {
                return $subscriptionService
            }
            $manager | Add-Member -MemberType ScriptMethod -Name GetWorkflowInstanceService -Value {
                return $instanceService
            }

            Get-SPSWorkflowRunningInstanceCount -Web ([PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/team' }) -WorkflowManager $manager
        }

        $result | Should -Be 3
    }

    It 'falls back to subscription-id enumeration when direct enumeration is unavailable' {
        $result = InModuleScope SPSSiteInventory.Common {
            $subscriptions = @(
                [PSCustomObject]@{ Id = [guid]::NewGuid() },
                [PSCustomObject]@{ Id = [guid]::NewGuid() }
            )

            $subscriptionService = [PSCustomObject]@{}
            $subscriptionService | Add-Member -MemberType ScriptMethod -Name EnumerateSubscriptions -Value {
                return $subscriptions
            }

            $instanceService = [PSCustomObject]@{}
            $instanceService | Add-Member -MemberType ScriptMethod -Name Enumerate -Value {
                throw 'Cannot find an overload for "Enumerate" and the argument count: "1".'
            }
            $instanceService | Add-Member -MemberType ScriptMethod -Name EnumerateInstancesForSubscription -Value {
                param ($subscriptionId)
                if ($subscriptionId -eq $subscriptions[0].Id) {
                    return @([PSCustomObject]@{ Status = 'Started' })
                }

                return @([PSCustomObject]@{ Status = 'CancelRequested' })
            }

            $manager = [PSCustomObject]@{
                IsConnected = $true
            }
            $manager | Add-Member -MemberType ScriptMethod -Name GetWorkflowSubscriptionService -Value {
                return $subscriptionService
            }
            $manager | Add-Member -MemberType ScriptMethod -Name GetWorkflowInstanceService -Value {
                return $instanceService
            }

            Get-SPSWorkflowRunningInstanceCount -Web ([PSCustomObject]@{ Url = 'https://intranet.contoso.com/sites/team' }) -WorkflowManager $manager
        }

        $result | Should -Be 2
    }
}
