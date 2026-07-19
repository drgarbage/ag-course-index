BeforeAll {
    $script:PlannerPath = Join-Path $PSScriptRoot '../../scripts/course-toolchain-windows.ps1'
    $script:InstallerPath = Join-Path $PSScriptRoot '../../scripts/toolchain/windows.ps1'
    $script:WindowsToolsFixturePath = Join-Path $PSScriptRoot 'fixtures/windows-tools.json'
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

    It 'ignores external package ids and commands' {
        { Invoke-WindowsToolInstall -ToolId RUN_COMMAND -Confirmed:$true } | Should -Throw
        (Get-Content $script:InstallerPath -Raw) | Should -Not -Match 'Invoke-Expression|\biex\b'
    }
}
