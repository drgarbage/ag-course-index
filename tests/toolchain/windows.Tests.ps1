BeforeAll {
    $script:PlannerPath = Join-Path $PSScriptRoot '../../scripts/course-toolchain-windows.ps1'
    $script:InstallerPath = Join-Path $PSScriptRoot '../../scripts/toolchain/windows.ps1'
    $script:ReportPath = Join-Path $PSScriptRoot '../../scripts/toolchain/report.ps1'
    $script:WindowsToolsFixturePath = Join-Path $PSScriptRoot 'fixtures/windows-tools.json'
    $script:WindowsDockerFixturePath = Join-Path $PSScriptRoot 'fixtures/docker-windows.json'
    . $script:PlannerPath
    . $script:ReportPath
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

    It 'rejects uppercase profile and selected GUI identifiers' {
        { Get-CourseToolchainPlan -Profile 'BASE' } | Should -Throw '*Unknown profile*'
        { Get-CourseToolchainPlan -Profile base -GuiTools @('VSCODE') } | Should -Throw '*Unknown GUI tool*'
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

    It 'rejects an uppercase catalog tool ID' {
        $path = Join-Path $TestDrive 'uppercase-tool.json'
        Set-Content -Path $path -NoNewline -Value '{"schema_version":1,"node_lts_major":24,"profiles":{"base":["GIT_GH","node_lts"],"line":["git_gh","node_lts","cloudflared"],"data":["git_gh","node_lts","docker_desktop"],"full":["git_gh","node_lts","cloudflared","docker_desktop"]},"gui_tools":["antigravity","vscode","browser"]}'

        { Get-CourseToolchainCatalog -CatalogPath $path } | Should -Throw '*Unknown tool ID*'
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

Describe 'Course toolchain GUI and readiness report' {
    It 'does not install GUI tools unless selected' {
        (Get-CourseToolchainPlan -Profile full).tool_id | Should -Not -Contain 'vscode'
    }

    It 'requires confirmation before installing a GUI tool' {
        $script:guiPackageCalls = 0
        $result = Invoke-WindowsGuiToolInstall -ToolId vscode -Confirmed:$false -PackageRunner { $script:guiPackageCalls++ }

        $result.status | Should -Be 'skipped'
        $script:guiPackageCalls | Should -Be 0
    }

    It 'uses the fixed WinGet argv for VS Code' {
        $script:guiPackageCalls = [System.Collections.Generic.List[object]]::new()
        $result = Invoke-WindowsGuiToolInstall -ToolId vscode -Confirmed:$true -AppProbe { $false } -PackageRunner {
            param($command, $arguments)
            $script:guiPackageCalls.Add([pscustomobject]@{ command = $command; arguments = @($arguments) })
            @{ exit_code = 0; stdout = 'ok'; stderr = '' }
        }

        $script:guiPackageCalls[1].command | Should -Be 'winget'
        $script:guiPackageCalls[1].arguments | Should -Be @(
            'install', '--id', 'Microsoft.VisualStudioCode', '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements'
        )
        $result.status | Should -Be 'needs_restart'
    }

    It 'marks a profile unready when one required tool fails' {
        (New-ToolchainReport -Profile line -Results @(@{ tool_id = 'cloudflared'; status = 'failed' })).ready |
            Should -BeFalse
    }

    It 'rejects uppercase report profiles and ignores uppercase result tool IDs' {
        { New-ToolchainReport -Profile BASE -Results @() } | Should -Throw
        $report = New-ToolchainReport -Profile base -Results @(
            @{ tool_id = 'GIT_GH'; status = 'installed' },
            @{ tool_id = 'node_lts'; status = 'installed' }
        )

        $report.tools.status | Should -Be @('failed', 'installed')
    }

    It 'rejects uppercase GUI installer identifiers' {
        { Get-WindowsGuiToolDefinition -ToolId VSCODE } | Should -Throw '*Unknown Windows GUI tool*'
        { Test-WindowsGuiToolInstalled -ToolId VSCODE } | Should -Throw '*Unknown Windows GUI tool*'
    }

    It 'does not expose tokens or personal paths' {
        (New-ToolchainReport -Profile base -Results @(@{ tool_id = 'git_gh'; status = 'failed'; safe_message = 'token ghp_fake at C:\Users\Alice Smith\Desktop\secret.txt' })) |
            ConvertTo-Json -Depth 8 | Should -Not -Match 'ghp_fake|Alice|Smith'
    }

    It 'normalizes ready to installed and marks a complete base profile ready' {
        $report = New-ToolchainReport -Profile base -FreeBytes 2147483648 -Results @(
            @{ tool_id = 'git_gh'; status = 'ready'; version = '2.76.0' },
            @{ tool_id = 'node_lts'; status = 'updated'; version = 'v24.4.0' }
        )

        $report.ready | Should -BeTrue
        $report.tools.status | Should -Be @('installed', 'updated')
        $report.disk | ConvertTo-Json -Compress | Should -Be '{"free_bytes":2147483648,"required_bytes":2147483648,"status":"enough"}'
    }

    It 'uses the restart next step for a required tool that needs restart' {
        $report = New-ToolchainReport -Profile base -FreeBytes 2147483648 -Results @(
            @{ tool_id = 'git_gh'; status = 'installed' },
            @{ tool_id = 'node_lts'; status = 'needs_restart' }
        )

        $report.ready | Should -BeFalse
        $report.restart_required | Should -BeTrue
        $report.next_step | Should -Be '請重新啟動電腦後重新執行 readiness report。'
    }

    It 'marks an otherwise ready profile unready when free disk is insufficient' {
        $report = New-ToolchainReport -Profile base -FreeBytes 1 -Results @(
            @{ tool_id = 'git_gh'; status = 'installed' },
            @{ tool_id = 'node_lts'; status = 'installed' }
        )

        $report.ready | Should -BeFalse
        $report.disk.status | Should -Be 'insufficient'
        $report.next_step | Should -Be '可用磁碟空間不足；請釋放空間後重新執行 readiness report。'
    }

    It 'reports unknown disk state when free bytes are not injected' {
        (New-ToolchainReport -Profile base -Results @()).disk.status | Should -Be 'unknown'
    }

    It 'treats malformed injected free bytes as unknown' {
        (New-ToolchainReport -Profile base -Results @() -FreeBytes 'not-a-number').disk.status | Should -Be 'unknown'
    }

    It 'uses fixed required bytes for every profile' {
        (New-ToolchainReport -Profile base -Results @()).disk.required_bytes | Should -Be 2147483648
        (New-ToolchainReport -Profile line -Results @()).disk.required_bytes | Should -Be 3221225472
        (New-ToolchainReport -Profile data -Results @()).disk.required_bytes | Should -Be 12884901888
        (New-ToolchainReport -Profile full -Results @()).disk.required_bytes | Should -Be 13958643712
    }

    It 'preserves every canonical status while mapping ready to installed' {
        $report = New-ToolchainReport -Profile base -Results @(
            @{ tool_id = 'git_gh'; status = 'ready' },
            @{ tool_id = 'node_lts'; status = 'updated' },
            @{ tool_id = 'antigravity'; status = 'needs_restart' },
            @{ tool_id = 'browser'; status = 'failed' },
            @{ tool_id = 'vscode'; status = 'skipped' }
        )

        $report.tools.status | Should -Be @('installed', 'updated', 'needs_restart', 'failed', 'skipped')
    }

    It 'rejects mixed-case statuses instead of accepting PowerShell casing' {
        $report = New-ToolchainReport -Profile base -Results @(
            @{ tool_id = 'git_gh'; status = 'INSTALLED' },
            @{ tool_id = 'node_lts'; status = 'READY' }
        )

        $report.tools.status | Should -Be @('failed', 'failed')
    }

    It 'redacts quoted Windows profile names through the end of the safe line' {
        $singleQuote = New-ToolchainReport -Profile base -Results @(
            @{ tool_id = 'git_gh'; status = 'failed'; safe_message = "at C:\Users\O'Connor\Desktop\secret.txt suffix O'Connor" }
        )
        $doubleQuote = New-ToolchainReport -Profile base -Results @(
            @{ tool_id = 'git_gh'; status = 'failed'; safe_message = 'at C:\Users\A"B\Desktop\secret.txt suffix A"B' }
        )

        $singleQuote.tools[0].safe_message | Should -Be 'at [USER_PATH]'
        $doubleQuote.tools[0].safe_message | Should -Be 'at [USER_PATH]'
    }

    It 'forwards injected free bytes through the Windows course wrapper' {
        $report = Get-CourseToolchainWindowsReadinessReport -Profile base -FreeBytes 1 -Results @(
            @{ tool_id = 'git_gh'; status = 'installed' },
            @{ tool_id = 'node_lts'; status = 'installed' }
        )

        $report.disk.free_bytes | Should -Be 1
        $report.disk.status | Should -Be 'insufficient'
    }

    It 'fails closed for non-string tool IDs and statuses' {
        $report = New-ToolchainReport -Profile base -Results @(
            @{ tool_id = @('git_gh'); status = 'ready' },
            @{ tool_id = 'node_lts'; status = @{ value = 'ready' } }
        )

        $report.tools.status | Should -Be @('failed', 'failed')
    }

    It 'contains all fixed Windows GUI package IDs' {
        (Get-WindowsGuiToolDefinition antigravity).id | Should -Be 'Google.Antigravity'
        (Get-WindowsGuiToolDefinition vscode).id | Should -Be 'Microsoft.VisualStudioCode'
        (Get-WindowsGuiToolDefinition browser).id | Should -Be 'Google.Chrome'
    }

    It 'accepts either Chrome or Edge as browser ready' {
        Test-WindowsGuiToolInstalled -ToolId browser -PathProbe { param($path) $path -like '*Google\Chrome*' } -CommandLookup { $false } |
            Should -BeTrue
        Test-WindowsGuiToolInstalled -ToolId browser -PathProbe { param($path) $path -like '*Microsoft\Edge*' } -CommandLookup { $false } |
            Should -BeTrue
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

Describe 'Windows course toolchain optional AI diagnostics' {
    It 'does not create an AI session for a ready or skipped tool' {
        $script:aiCalls = 0
        $supportInvoker = {
            param($step, $diagnostics)
            $script:aiCalls++
            @{ status = 'resolved' }
        }

        (Resolve-CourseToolchainWindowsFailure -Profile base -Result @{ tool_id = 'node_lts'; status = 'ready' } -SupportInvoker $supportInvoker).status |
            Should -Be 'not_applicable'
        (Resolve-CourseToolchainWindowsFailure -Profile base -Result @{ tool_id = 'node_lts'; status = 'skipped' } -SupportInvoker $supportInvoker).status |
            Should -Be 'not_applicable'
        $script:aiCalls | Should -Be 0
    }

    It 'keeps AI offline when the user declines after the local fallback' {
        $script:aiCalls = 0
        $messages = [System.Collections.Generic.List[string]]::new()

        $result = Resolve-CourseToolchainWindowsFailure -Profile base -Result @{
            tool_id = 'git_gh'; status = 'failed'; error_kind = 'git_install';
            safe_message = 'git failed at C:\Users\Alice\.env with token ghp_fake'
        } -ConsentProvider { 'n' } -FallbackWriter { param($message) $messages.Add($message) } -SupportInvoker {
            param($step, $diagnostics)
            $script:aiCalls++
            @{ status = 'resolved' }
        }

        $result.status | Should -Be 'declined'
        $messages.Count | Should -BeGreaterThan 0
        ($messages -join "`n") | Should -Not -Match 'ghp_fake|Alice|\.env'
        $script:aiCalls | Should -Be 0
    }

    It 'sends only the toolchain-safe diagnostic schema to support' {
        $script:captured = $null

        Resolve-CourseToolchainWindowsFailure -Profile base -Result @{
            tool_id = 'git_gh'; status = 'failed'; error_kind = 'network'; found = $false
            version = 'ghp_fake'; exit_code = 17; restart_required = $true; engine_running = $false
            safe_message = 'token ghp_fake at C:\\Users\\Alice\\workspace\\.env'
            env = @{ SECRET = 'nope' }; authorization = 'Bearer nope'; command = 'evil'; url = 'https://evil.invalid'
        } -ConsentProvider { 'y' } -FallbackWriter {} -SupportInvoker {
            param($step, $diagnostics)
            $script:captured = @{ step = $step; diagnostics = $diagnostics }
            @{ status = 'fallback' }
        } | Out-Null

        $script:captured.step | Should -Be 'network'
        @($script:captured.diagnostics.PSObject.Properties.Name) | Should -Be @(
            'platform', 'step', 'tool_id', 'found', 'version', 'exit_code', 'error_kind', 'restart_required', 'engine_running'
        )
        ($script:captured.diagnostics | ConvertTo-Json -Compress) | Should -Not -Match 'ghp_fake|Alice|\.env|SECRET|authorization|evil|url'
    }

    It 'keeps Node, Docker, and cloudflared on the fixed contact-instructor fallback' {
        $script:aiCalls = 0
        foreach ($toolId in @('node_lts', 'cloudflared', 'docker_desktop')) {
            $result = Resolve-CourseToolchainWindowsFailure -Profile full -Result @{ tool_id = $toolId; status = 'failed'; error_kind = 'unknown' } `
                -FallbackWriter {} -ConsentProvider { 'y' } -SupportInvoker { $script:aiCalls++; @{ status = 'resolved' } }

            $result.status | Should -Be 'contact_instructor'
            $result.action_id | Should -Be 'CONTACT_INSTRUCTOR'
        }
        $script:aiCalls | Should -Be 0
    }

    It 'falls back immediately when the existing dispatcher rejects a remote action' {
        $script:actionCalls = 0
        $result = Resolve-CourseToolchainWindowsFailure -Profile base -Result @{ tool_id = 'git_gh'; status = 'failed'; error_kind = 'gh_install' } `
            -ConsentProvider { 'y' } -FallbackWriter {} -SupportInvoker {
                param($step, $diagnostics)
                $script:actionCalls++
                @{ status = 'fallback'; remote_action = @{ id = 'RUN_ARBITRARY_COMMAND'; command = 'evil'; url = 'https://evil.invalid' } }
            }

        $result.status | Should -Be 'fallback'
        $script:actionCalls | Should -Be 1
    }
}
