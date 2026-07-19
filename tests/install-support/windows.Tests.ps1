BeforeAll {
    $script:InstallerPath = Join-Path $PSScriptRoot '../../scripts/install-git-gh-windows.ps1'
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:InstallerPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ($errors | Out-String) }
    $functionSource = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true).Extent.Text -join "`n"
    . ([scriptblock]::Create($functionSource))
}

Describe 'Install support diagnostics' {
    It 'collects only allowlisted fields and truncates stderr' {
        $diagnostics = Get-InstallDiagnostics -Step 'github_auth' -LastError ('x' * 5000) -CommandLookup { param($name) $name -eq 'git' }
        $diagnostics.PSObject.Properties.Name | Should -Not -Contain 'env'
        $diagnostics.PSObject.Properties.Name | Should -Not -Contain 'token'
        $diagnostics.stderr.Length | Should -BeLessOrEqual 4000
        $diagnostics.git_found | Should -BeTrue
        $diagnostics.gh_found | Should -BeFalse
    }

    It 'redacts Windows user paths from stderr' {
        $diagnostics = Get-InstallDiagnostics -Step 'github_auth' -LastError 'failed at C:\Users\alice\project' -CommandLookup { param($name) $false }
        $diagnostics.stderr | Should -Be 'failed at C:\Users\<USER>\project'
    }

    It 'creates a session without Authorization and diagnoses with the signed token' {
        $script:calls = [System.Collections.Generic.List[object]]::new()
        $transport = {
            param($request)
            $script:calls.Add($request)
            if ($request.Uri -like '*/sessions') {
                return @{ session_id = 'is_fake'; session_token = 'signed-fake'; expires_at = '2026-07-19T12:30:00Z' }
            }
            return @{ action = @{ id = 'CHECK_GH_VERSION'; requires_confirmation = $false }; resolved = $false }
        }
        $session = New-InstallSupportSession -InstallerVersion '1.0.0' -Transport $transport
        $result = Invoke-InstallDiagnosis -Session $session -Step 'github_auth' -Attempt 1 -Diagnostics @{} -Transport $transport
        $script:calls.Count | Should -Be 2
        $script:calls[0].Headers.ContainsKey('Authorization') | Should -BeFalse
        $script:calls[0].TimeoutSec | Should -Be 20
        $script:calls[1].Headers.Authorization | Should -Be 'Bearer signed-fake'
        $script:calls[1].TimeoutSec | Should -Be 20
        $result.action.id | Should -Be 'CHECK_GH_VERSION'
    }
}

Describe 'Windows install action allowlist' {
    It 'rejects unknown actions without invoking a command' {
        $script:commandCalls = 0
        {
            Invoke-AllowlistedInstallAction `
                -ActionId 'RUN_ARBITRARY_COMMAND' `
                -Confirmed:$true `
                -CommandRunner { param($command, $arguments) $script:commandCalls++ }
        } | Should -Throw '*Unknown install support action*'
        $script:commandCalls | Should -Be 0
    }

    It 'does not run a state-changing action without confirmation' {
        $script:commandCalls = 0
        $result = Invoke-AllowlistedInstallAction `
            -ActionId 'INSTALL_GH_WINDOWS' `
            -Confirmed:$false `
            -CommandRunner { param($command, $arguments) $script:commandCalls++ }

        $result.action_id | Should -Be 'INSTALL_GH_WINDOWS'
        $result.exit_code | Should -Be -1
        $result.stderr | Should -Match 'confirmation'
        $script:commandCalls | Should -Be 0
    }

    It 'maps an allowed action to fixed argv and ignores executable response fields' {
        $script:capturedCommand = $null
        $script:capturedArguments = $null
        $response = @{ action = @{ id = 'CHECK_GH_VERSION'; command = 'touch /tmp/command-ran'; url = 'https://evil.invalid' } }

        $result = Invoke-AllowlistedInstallAction `
            -ActionId $response.action.id `
            -CommandRunner {
                param($command, $arguments)
                $script:capturedCommand = $command
                $script:capturedArguments = $arguments
                @{ exit_code = 0; stdout = 'gh version fake'; stderr = '' }
            }

        $script:capturedCommand | Should -Be 'gh'
        $script:capturedArguments | Should -Be @('--version')
        $result.exit_code | Should -Be 0
        $result.stdout | Should -Be 'gh version fake'
    }

    It 'contains no dynamic expression execution' {
        $source = Get-Content $script:InstallerPath -Raw
        $source | Should -Not -Match '(?im)\bInvoke-Expression\b|\biex\b'
    }
}
