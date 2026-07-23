$ErrorActionPreference = 'Stop'

Describe 'Windows Sandbox Test Runner Coordinator' {
    BeforeAll {
        $script:SandboxRunnerPath = Join-Path $PSScriptRoot "run-sandbox-test.ps1"
        $script:TempDir = Join-Path $TestDrive "sandbox_test_temp"
        New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    }

    It 'generates configuration and WSB file successfully for Clean scenario' {
        # Run runner in dry-run mode
        & $script:SandboxRunnerPath -Scenario Clean -NoLaunch | Out-Null
        
        $sharedDir = Join-Path $PSScriptRoot "shared"
        $configPath = Join-Path $sharedDir "config.json"
        $wsbPath = Join-Path $PSScriptRoot "course-toolchain-test.wsb"

        # Check config exists and has correct content
        Test-Path $configPath | Should -BeTrue
        $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $config.scenario | Should -Be 'Clean'

        # Check wsb exists and has correct paths
        Test-Path $wsbPath | Should -BeTrue
        $wsbContent = Get-Content -Raw -Path $wsbPath
        $wsbContent | Should -Match '<SandboxFolder>C:\\ag-course-index</SandboxFolder>'
        $wsbContent | Should -Match '<SandboxFolder>C:\\shared</SandboxFolder>'
        $wsbContent | Should -Match '<Command>powershell.exe -ExecutionPolicy Bypass -File C:\\ag-course-index\\tests\\sandbox\\sandbox-init.ps1</Command>'
    }

    It 'generates configuration for NvmInstalled scenario' {
        & $script:SandboxRunnerPath -Scenario NvmInstalled -NoLaunch | Out-Null
        
        $sharedDir = Join-Path $PSScriptRoot "shared"
        $configPath = Join-Path $sharedDir "config.json"

        $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $config.scenario | Should -Be 'NvmInstalled'
    }

    It 'generates configuration for DockerStopped scenario' {
        & $script:SandboxRunnerPath -Scenario DockerStopped -NoLaunch | Out-Null
        
        $sharedDir = Join-Path $PSScriptRoot "shared"
        $configPath = Join-Path $sharedDir "config.json"

        $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $config.scenario | Should -Be 'DockerStopped'
    }
}
