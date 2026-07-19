BeforeAll {
    $script:PlannerPath = Join-Path $PSScriptRoot '../../scripts/course-toolchain-windows.ps1'
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
