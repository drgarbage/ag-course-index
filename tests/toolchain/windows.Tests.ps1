BeforeAll {
    $script:PlannerPath = Join-Path $PSScriptRoot '../../scripts/course-toolchain-windows.ps1'
    $script:InstallerPath = Join-Path $PSScriptRoot '../../scripts/toolchain/windows.ps1'
    $script:WindowsToolsFixturePath = Join-Path $PSScriptRoot 'fixtures/windows-tools.json'
    $script:WindowsDockerFixturePath = Join-Path $PSScriptRoot 'fixtures/docker-windows.json'
    . $script:PlannerPath
}

Describe 'Course toolchain profile planner' {
    It 'expands full without forcing GUI tools' {
        (Get-CourseToolchainPlan -Profile full -GuiTools @()).tool_id |
            Should -Be @('git_gh', 'node_lts', 'cloudflared', 'docker_desktop')
    }

    It 'appends explicitly selected GUI tools' {
        (Get-CourseToolchainPlan -Profile base -GuiTools @('vscode', 'browser')).tool_id |
            Should -Be @('git_gh', 'node_lts', 'vscode', 'browser')
    }

    It 'rejects unknown profiles before any action' {
        { Get-CourseToolchainPlan -Profile 'evil' } | Should -Throw '*Unknown profile*'
    }

    It 'catalog contains no executable fields' {
        Get-Content (Join-Path $PSScriptRoot '../../scripts/toolchain/catalog.json') -Raw |
            Should -Not -Match '(?i)command|executable|arguments|url|package_id'
    }

    It 'rejects an unsupported catalog schema version' {
        $path = Join-Path $TestDrive 'unsupported-schema.json'
        Set-Content -Path $path -NoNewline -Value '{"schema_version":2}'

        { Get-CourseToolchainCatalog -CatalogPath $path } |
            Should -Throw '*Unsupported catalog schema version*'
    }

    It 'rejects catalog tool IDs outside the allowlist' {
        $path = Join-Path $TestDrive 'unknown-tool.json'
        Set-Content -Path $path -NoNewline -Value '{"schema_version":1,"node_lts_major":24,"profiles":{"base":["evil"]},"gui_tools":["antigravity","vscode","browser"]}'

        { Get-CourseToolchainCatalog -CatalogPath $path } |
            Should -Throw '*Unknown tool ID*'
    }

    It 'rejects duplicate catalog tool IDs' {
        $path = Join-Path $TestDrive 'duplicate-tool.json'
        Set-Content -Path $path -NoNewline -Value '{"schema_version":1,"node_lts_major":24,"profiles":{"base":["git_gh","git_gh"]},"gui_tools":["antigravity","vscode","browser"]}'

        { Get-CourseToolchainCatalog -CatalogPath $path } |
            Should -Throw '*Duplicate tool ID*'
    }

    It 'rejects GUI tool IDs outside the allowlist' {
        $path = Join-Path $TestDrive 'unknown-gui.json'
        Set-Content -Path $path -NoNewline -Value '{"schema_version":1,"node_lts_major":24,"profiles":{"base":["git_gh","node_lts"]},"gui_tools":["antigravity","vscode","evil"]}'

        { Get-CourseToolchainCatalog -CatalogPath $path } |
            Should -Throw '*Unknown GUI tool ID*'
    }
}

Describe 'Windows Node.js and Cloudflare toolchain installer' {
    It 'detects a compliant Node LTS and skips installation' {
        $fixture = Get-Content $script:WindowsToolsFixturePath -Raw | ConvertFrom-Json
        $state = Get-WindowsToolState -ToolId node_lts -CommandLookup { $true } -VersionRunner { $fixture.node_lts.version }

        $state.status | Should -Be 'ready'
    }

    It 'rejects a Node version below the local minimum' {
        $state = Get-WindowsToolState -ToolId node_lts -CommandLookup { $true } -VersionRunner { 'v24.3.9' }

        $state.status | Should -Be 'outdated'
    }

    It 'accepts a Node version equal to the local minimum' {
        $state = Get-WindowsToolState -ToolId node_lts -CommandLookup { $true } -VersionRunner { 'v24.4.0' }

        $state.status | Should -Be 'ready'
    }

    It 'rejects a Node version with trailing garbage' {
        $state = Get-WindowsToolState -ToolId node_lts -CommandLookup { $true } -VersionRunner { 'v24.4.0-not-semver' }

        $state.status | Should -Be 'failed'
    }

    It 'never installs cloudflared without confirmation' {
        $script:calls = 0
        $result = Invoke-WindowsToolInstall -ToolId cloudflared -Confirmed:$false -PackageRunner { $script:calls++ }

        $result.status | Should -Be 'skipped'
        $script:calls | Should -Be 0
    }

    It 'uses the fixed WinGet argv for the Node LTS package' {
        $script:packageCalls = [System.Collections.Generic.List[object]]::new()
        $result = Invoke-WindowsToolInstall -ToolId node_lts -Confirmed:$true -CommandLookup { $false } -PackageRunner {
            param($command, $arguments)
            $script:packageCalls.Add([pscustomobject]@{ command = $command; arguments = @($arguments) })
            @{ exit_code = 0; stdout = 'ok'; stderr = '' }
        }

        $script:packageCalls.Count | Should -Be 2
        $script:packageCalls[0].command | Should -Be 'winget'
        $script:packageCalls[0].arguments | Should -Be @('--version')
        $script:packageCalls[1].command | Should -Be 'winget'
        $script:packageCalls[1].arguments | Should -Be @(
            'install', '--id', 'OpenJS.NodeJS.LTS', '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements'
        )
        $result.status | Should -Be 'needs_restart'
    }

    It 'uses the fixed WinGet argv for the cloudflared package' {
        $script:packageCalls = [System.Collections.Generic.List[object]]::new()
        $result = Invoke-WindowsToolInstall -ToolId cloudflared -Confirmed:$true -CommandLookup { $false } -PackageRunner {
            param($command, $arguments)
            $script:packageCalls.Add([pscustomobject]@{ command = $command; arguments = @($arguments) })
            @{ exit_code = 0; stdout = 'ok'; stderr = '' }
        }

        $script:packageCalls.Count | Should -Be 2
        $script:packageCalls[0].command | Should -Be 'winget'
        $script:packageCalls[0].arguments | Should -Be @('--version')
        $script:packageCalls[1].command | Should -Be 'winget'
        $script:packageCalls[1].arguments | Should -Be @(
            'install', '--id', 'Cloudflare.cloudflared', '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements'
        )
        $result.status | Should -Be 'needs_restart'
    }

    It 'does not expose a generic native package command runner' {
        Get-Command Invoke-WindowsNativePackageCommand -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'rejects arbitrary WinGet argv before native execution' {
        { Invoke-WindowsWingetCommand -Arguments @('install', '--id', 'evil.invalid') } |
            Should -Throw '*Unknown WinGet arguments*'
    }

    It 'ignores external package ids and commands' {
        { Invoke-WindowsToolInstall -ToolId RUN_COMMAND -Confirmed:$true } | Should -Throw
        (Get-Content $script:InstallerPath -Raw) | Should -Not -Match 'Invoke-Expression|\biex\b'
    }
}

Describe 'Windows Docker Desktop installer' {
    It 'reports only Docker prerequisites without changing the host' {
        $fixture = Get-Content $script:WindowsDockerFixturePath -Raw | ConvertFrom-Json
        $result = Get-WindowsDockerPrerequisites -OsProbe { $fixture.os } -VirtualizationProbe { $fixture.virtualization } -WslProbe { $fixture.wsl2 }

        @($result.PSObject.Properties.Name) | Should -Be @('os', 'virtualization', 'wsl2')
        $result.os | Should -Be 'Windows 11'
        $result.virtualization | Should -BeTrue
        $result.wsl2 | Should -BeTrue
    }

    It 'recognizes a localized WSL2 default-version status' {
        $result = Get-WindowsDockerPrerequisites -OsProbe { 'Windows 11' } -VirtualizationProbe { $true } -WslProbe { "預設版本: 2" }

        $result.wsl2 | Should -BeTrue
    }

    It 'does not treat a localized WSL1 status as WSL2' {
        $result = Get-WindowsDockerPrerequisites -OsProbe { 'Windows 11' } -VirtualizationProbe { $true } -WslProbe { "預設版本: 1" }

        $result.wsl2 | Should -BeFalse
    }

    It 'returns needs_restart without forcing reboot when WSL changed' {
        $r = Install-WindowsDockerDesktop -Confirmed -PrerequisiteProvider { @{ wsl2 = $false; change_requires_restart = $true } }

        $r.status | Should -Be 'needs_restart'
    }

    It 'does not install Docker Desktop without Docker confirmation' {
        $script:dockerPackageCalls = 0
        $result = Install-WindowsDockerDesktop -Confirmed:$false -PackageRunner { $script:dockerPackageCalls++ }

        $result.status | Should -Be 'skipped'
        $script:dockerPackageCalls | Should -Be 0
    }

    It 'stops before package installation when Windows is not the host OS' {
        $script:dockerPackageCalls = 0
        $result = Install-WindowsDockerDesktop -Confirmed -PrerequisiteProvider { @{ os = 'Linux'; virtualization = $true; wsl2 = $true } } -PackageRunner {
            $script:dockerPackageCalls++
            @{ exit_code = 0 }
        } -AppStarter { $true } -ReadyWaiter { @{ status = 'ready' } }

        $result.status | Should -Be 'failed'
        $result.reason | Should -Be 'unsupported_os'
        $script:dockerPackageCalls | Should -Be 0
    }

    It 'does not change WSL without separate WSL confirmation' {
        $script:wslCalls = 0
        $result = Install-WindowsDockerDesktop -Confirmed -PrerequisiteProvider { @{ os = 'Windows 11'; virtualization = $true; wsl2 = $false } } -WslInstaller {
            param($arguments)
            $script:wslCalls++
            @{ exit_code = 0 }
        }

        $result.status | Should -Be 'needs_wsl_confirmation'
        $script:wslCalls | Should -Be 0
    }

    It 'uses the fixed WSL argv only after WSL confirmation' {
        $script:wslCalls = [System.Collections.Generic.List[object]]::new()
        $result = Install-WindowsDockerDesktop -Confirmed -WslChangeConfirmed -PrerequisiteProvider { @{ os = 'Windows 11'; virtualization = $true; wsl2 = $false } } -WslInstaller {
            param($arguments)
            $script:wslCalls.Add(@($arguments))
            @{ exit_code = 0 }
        }

        $script:wslCalls.Count | Should -Be 1
        $script:wslCalls[0] | Should -Be @('--install', '--no-distribution')
        $result.status | Should -Be 'needs_restart'
    }

    It 'uses the fixed WinGet Docker Desktop argv after prerequisites are ready' {
        $script:dockerPackageCalls = [System.Collections.Generic.List[object]]::new()
        $result = Install-WindowsDockerDesktop -Confirmed -PrerequisiteProvider { @{ os = 'Windows 11'; virtualization = $true; wsl2 = $true } } -PackageRunner {
            param($command, $arguments)
            $script:dockerPackageCalls.Add([pscustomobject]@{ command = $command; arguments = @($arguments) })
            @{ exit_code = 0; stdout = 'ok'; stderr = '' }
        } -AppStarter { param($path) $true } -ReadyWaiter { @{ status = 'ready' } }

        $script:dockerPackageCalls.Count | Should -Be 2
        $script:dockerPackageCalls[0].command | Should -Be 'winget'
        $script:dockerPackageCalls[0].arguments | Should -Be @('--version')
        $script:dockerPackageCalls[1].command | Should -Be 'winget'
        $script:dockerPackageCalls[1].arguments | Should -Be @(
            'install', '--id', 'Docker.DockerDesktop', '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements'
        )
        $result.status | Should -Be 'ready'
    }

    It 'starts the fixed Docker Desktop application path before waiting for the engine' {
        $script:startedPath = $null
        $result = Install-WindowsDockerDesktop -Confirmed -PrerequisiteProvider { @{ os = 'Windows 11'; virtualization = $true; wsl2 = $true } } -PackageRunner {
            @{ exit_code = 0 }
        } -AppStarter {
            param($path)
            $script:startedPath = $path
            $true
        } -ReadyWaiter { @{ status = 'ready' } }

        $script:startedPath | Should -Be 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
        $result.status | Should -Be 'ready'
    }

    It 'does not accept legacy docker-compose as Compose v2' {
        $r = Test-WindowsDockerReady -DockerProbe { 0 } -ComposeProbe { param($args) if ($args -eq 'compose version') { 1 } }

        $r.status | Should -Be 'failed'
    }

    It 'times out with truthful status' {
        (Wait-WindowsDockerReady -TimeoutSeconds 1 -Probe { $false }).status | Should -Be 'failed'
    }

    It 'does not exceed the timeout when a probe blocks' {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Wait-WindowsDockerReady -TimeoutSeconds 1 -Probe { Start-Sleep -Seconds 2; $false }
        $stopwatch.Stop()

        $result.status | Should -Be 'failed'
        $stopwatch.Elapsed.TotalSeconds | Should -BeLessOrEqual 1.5
    }

    It 'does not expose a restart command or the legacy Compose executable' {
        Get-Content $script:InstallerPath -Raw | Should -Not -Match '(?i)Restart-Computer|shutdown\.exe|\bdocker-compose\b'
    }
}
