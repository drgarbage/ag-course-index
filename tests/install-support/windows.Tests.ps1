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

Describe 'Optional Windows AI recovery flow' {
    It 'is connected to the existing static failure handler' {
        $source = Get-Content $script:InstallerPath -Raw
        $source | Should -Match '(?s)function Stop-Zh.*Invoke-OptionalInstallSupport'
    }

    It 'does not create a session when the user declines' {
        $script:sessionCalls = 0
        $result = Invoke-OptionalInstallSupport `
            -Step 'github_auth' -Diagnostics @{} `
            -ConsentProvider { 'n' } `
            -SessionFactory { $script:sessionCalls++ }

        $result.status | Should -Be 'declined'
        $script:sessionCalls | Should -Be 0
    }

    It 'keeps the static fallback when the API is offline' {
        $result = Invoke-OptionalInstallSupport `
            -Step 'github_auth' -Diagnostics @{} `
            -ConsentProvider { 'y' } `
            -SessionFactory { @{ session_id = 'is_fake'; session_token = 'signed-fake' } } `
            -DiagnosisProvider { throw 'offline' }

        $result.status | Should -Be 'fallback'
        $result.support_code | Should -BeNullOrEmpty
    }

    It 'requires confirmation and returns action feedback on the next request' {
        $script:requests = [System.Collections.Generic.List[object]]::new()
        $script:actionCalls = 0
        $result = Invoke-OptionalInstallSupport `
            -Step 'github_auth' -Diagnostics @{} `
            -ConsentProvider { 'y' } `
            -ConfirmationProvider { 'y' } `
            -SessionFactory { @{ session_id = 'is_fake'; session_token = 'signed-fake' } } `
            -DiagnosisProvider {
                param($session, $step, $attempt, $diagnostics, $previousAction)
                $script:requests.Add([pscustomobject]@{ attempt = $attempt; previous = $previousAction })
                if ($attempt -eq 1) {
                    return @{ action = @{ id = 'GH_AUTH_SETUP_GIT'; requires_confirmation = $true }; resolved = $false; support_code = 'SUP-FAKE03' }
                }
                return @{ action = @{ id = 'CONTACT_INSTRUCTOR'; requires_confirmation = $false }; resolved = $true; support_code = 'SUP-FAKE03' }
            } `
            -ActionRunner {
                param($actionId, $confirmed)
                $script:actionCalls++
                @{ action_id = $actionId; exit_code = 0; stdout = ''; stderr = '' }
            }

        $script:actionCalls | Should -Be 1
        $script:requests.Count | Should -Be 2
        $script:requests[1].previous.action_id | Should -Be 'GH_AUTH_SETUP_GIT'
        $script:requests[1].previous.succeeded | Should -BeTrue
        $result.status | Should -Be 'resolved'
    }

    It 'stops after fifteen diagnosis requests' {
        $script:diagnosisCalls = 0
        $result = Invoke-OptionalInstallSupport `
            -Step 'github_auth' -Diagnostics @{} `
            -ConsentProvider { 'y' } `
            -SessionFactory { @{ session_id = 'is_fake'; session_token = 'signed-fake' } } `
            -DiagnosisProvider {
                $script:diagnosisCalls++
                @{ action = @{ id = 'CHECK_GH_VERSION'; requires_confirmation = $false }; resolved = $false; support_code = 'SUP-LIMIT1' }
            } `
            -ActionRunner { param($actionId, $confirmed) @{ action_id = $actionId; exit_code = 1; stdout = ''; stderr = 'still failing' } }

        $script:diagnosisCalls | Should -Be 15
        $result.status | Should -Be 'limit'
        $result.support_code | Should -Be 'SUP-LIMIT1'
    }
}
