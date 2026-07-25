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

    It 'collects a safe Raw GitHub network enum without response content' {
        $diagnostics = Get-InstallDiagnostics -Step 'network' -LastError 'blocked' `
            -CommandLookup { param($name) $false } -RawNetworkProbe { $false }
        $diagnostics.raw_github_network | Should -Be 'blocked'
        $diagnostics.PSObject.Properties.Name | Should -Not -Contain 'network_body'
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
    It 'uses only backend-allowlisted default steps' {
        $source = Get-Content $script:InstallerPath -Raw
        $source | Should -Not -Match "Step = 'final_verification'"
    }

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

    It 'uses local confirmation policy even when the response says false' {
        $script:unsafeActionCalls = 0
        $result = Invoke-OptionalInstallSupport `
            -Step 'gh_install' -Diagnostics @{} `
            -ConsentProvider { 'y' } -ConfirmationProvider { 'n' } `
            -LocalPatternProvider { $null } `
            -SessionFactory { @{ session_id = 'is_fake'; session_token = 'signed-fake' } } `
            -DiagnosisProvider { @{ action = @{ id = 'INSTALL_GH_WINDOWS'; requires_confirmation = $false }; resolved = $false; support_code = 'SUP-SAFE01' } } `
            -ActionRunner { $script:unsafeActionCalls++; @{ action_id = 'INSTALL_GH_WINDOWS'; exit_code = 0 } }
        $result.status | Should -Be 'action_declined'
        $script:unsafeActionCalls | Should -Be 0
    }

    It 'renders exact localized backend contract fields before confirmation' {
        $script:messages = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-OptionalInstallSupport `
            -Step 'github_auth' -Diagnostics @{} `
            -ConsentProvider { 'y' } -ConfirmationProvider { 'n' } `
            -LocalPatternProvider { $null } `
            -SessionFactory { @{ session_id = 'is_fake'; session_token = 'signed-fake' } } `
            -DiagnosisProvider { @{
                summary_zh_tw = '繁中摘要'; explanation_zh_tw = '繁中說明'
                action = @{ id = 'GH_AUTH_LOGIN_WEB'; title_zh_tw = '登入 GitHub'; impact_zh_tw = '會開啟瀏覽器'; requires_confirmation = $true }
                resolved = $false; support_code = 'SUP-CONTRACT'
            } } `
            -OutputWriter { param($message) $script:messages.Add($message) }
        $script:messages | Should -Be @('繁中摘要', '繁中說明', '登入 GitHub', '會開啟瀏覽器')
        $result.status | Should -Be 'action_declined'
    }

    It 'falls back on non-boolean resolved values' {
        $result = Invoke-OptionalInstallSupport `
            -Step 'network' -Diagnostics @{} -ConsentProvider { 'y' } `
            -LocalPatternProvider { $null } `
            -SessionFactory { @{ session_id = 'is_fake'; session_token = 'signed-fake' } } `
            -DiagnosisProvider { @{ action = @{ id = 'CONTACT_INSTRUCTOR'; requires_confirmation = $false }; resolved = 'false' } }
        $result.status | Should -Be 'fallback'
    }

    It 'treats local recovery as successful in the static failure handler' {
        $source = Get-Content $script:InstallerPath -Raw
        $source | Should -Match "status -in @\('resolved', 'local_resolved'\)"
    }
}

Describe 'Cross-platform acceptance matrix' {
    It 'documents all sixteen unique scenarios without ditto placeholders' {
        $matrixPath = Join-Path $PSScriptRoot 'acceptance-matrix.md'
        $matrix = Get-Content $matrixPath
        $scenarioIds = @($matrix | ForEach-Object {
            if ($_ -match '^\|\s*(\d+)\s*\|') { [int]$Matches[1] }
        })
        $scenarioIds | Should -Be (1..16)
        ($matrix -join "`n") | Should -Not -Match '同上|ditto'
    }

    It 'maps Windows scenario actions to the fixed dispatcher' -ForEach @(
        @{ Scenario = 1; Action = 'INSTALL_GIT_WINDOWS'; Confirmation = $true }
        @{ Scenario = 2; Action = 'INSTALL_GH_WINDOWS'; Confirmation = $true }
        @{ Scenario = 3; Action = 'GH_AUTH_SETUP_GIT'; Confirmation = $true }
        @{ Scenario = 4; Action = 'GH_AUTH_LOGIN_WEB'; Confirmation = $true }
        @{ Scenario = 5; Action = 'REFRESH_WINDOWS_PATH'; Confirmation = $true }
        @{ Scenario = 9; Action = 'CHECK_RAW_GITHUB_NETWORK'; Confirmation = $false }
        @{ Scenario = 10; Action = 'GH_AUTH_SWITCH'; Confirmation = $true }
        @{ Scenario = 11; Action = 'CLEAR_STALE_GITHUB_CREDENTIAL_WINDOWS'; Confirmation = $true }
        @{ Scenario = 13; Action = 'CHECK_GH_AUTH_STATUS'; Confirmation = $false }
    ) {
        $script:acceptanceCalls = 0
        $result = Invoke-AllowlistedInstallAction -ActionId $Action -Confirmed:$Confirmation -CommandRunner {
            param($command, $arguments)
            $script:acceptanceCalls++
            @{ exit_code = 0; stdout = ''; stderr = '' }
        }
        $result.action_id | Should -Be $Action
        if ($Action -notin @('REFRESH_WINDOWS_PATH')) { $script:acceptanceCalls | Should -Be 1 }
    }
}

Describe 'Versioned local install patterns' {
    It 'resolves a known pattern without creating an API session' {
        $script:sessionCalls = 0
        $script:localCalls = 0
        $result = Invoke-OptionalInstallSupport `
            -Step 'gh_install' `
            -Diagnostics @{ gh_found = $false; winget_available = $true } `
            -LocalPatternProvider {
                param($step, $diagnostics, $confirmationProvider, $actionRunner)
                $script:localCalls++
                @{ matched = $true; local_pattern_key = 'windows.gh_missing.v1'; succeeded = $true }
            } `
            -ConsentProvider { throw 'consent must not be requested' } `
            -SessionFactory { $script:sessionCalls++; throw 'session must not be created' }

        $result.status | Should -Be 'local_resolved'
        $result.local_pattern_key | Should -Be 'windows.gh_missing.v1'
        $script:localCalls | Should -Be 1
        $script:sessionCalls | Should -Be 0
    }

    It 'reports a failed local pattern as the first AI previous action' {
        $script:firstPreviousAction = $null
        $result = Invoke-OptionalInstallSupport `
            -Step 'gh_install' `
            -Diagnostics @{ gh_found = $false; winget_available = $true } `
            -LocalPatternProvider {
                @{ matched = $true; local_pattern_key = 'windows.gh_missing.v1'; action_id = 'INSTALL_GH_WINDOWS'; exit_code = 1; succeeded = $false }
            } `
            -ConsentProvider { 'y' } `
            -SessionFactory { @{ session_id = 'is_fake'; session_token = 'signed-fake' } } `
            -DiagnosisProvider {
                param($session, $step, $attempt, $diagnostics, $previousAction)
                $script:firstPreviousAction = $previousAction
                @{ action = @{ id = 'CONTACT_INSTRUCTOR'; requires_confirmation = $false }; resolved = $false; support_code = 'SUP-LOCAL1' }
            }

        $script:firstPreviousAction.local_pattern_key | Should -Be 'windows.gh_missing.v1'
        $script:firstPreviousAction.action_id | Should -Be 'INSTALL_GH_WINDOWS'
        $script:firstPreviousAction.succeeded | Should -BeFalse
        $result.status | Should -Be 'contact'
    }

    It 'loads only strict boolean enum and exit-code matchers' {
        $rulesPath = Join-Path $PSScriptRoot '../../scripts/install-support-patterns.json'
        $script:patternActions = 0
        $result = Invoke-LocalInstallPattern `
            -Step 'gh_install' `
            -Diagnostics @{ gh_found = $false; winget_available = $true } `
            -RulesPath $rulesPath `
            -ConfirmationProvider { 'y' } `
            -ActionRunner {
                param($actionId, $confirmed)
                $script:patternActions++
                @{ action_id = $actionId; exit_code = 0; stdout = ''; stderr = '' }
            }

        $result.local_pattern_key | Should -Be 'windows.gh_missing.v1'
        $result.succeeded | Should -BeTrue
        $script:patternActions | Should -Be 1
        $rules = Get-Content $rulesPath -Raw | ConvertFrom-Json
        foreach ($pattern in $rules.patterns) {
            $pattern.PSObject.Properties.Name | Should -Not -Contain 'command'
            $pattern.PSObject.Properties.Name | Should -Not -Contain 'script'
            $pattern.PSObject.Properties.Name | Should -Not -Contain 'url'
            $pattern.PSObject.Properties.Name | Should -Not -Contain 'regex'
            $pattern.PSObject.Properties.Name | Should -Not -Contain 'expression'
        }
    }
}

Describe 'PowerShell language mode gate' {
    It 'accepts FullLanguage' {
        $state = Get-LanguageModeState -LanguageModeProvider { 'FullLanguage' }
        $state.is_full | Should -BeTrue
        $state.mode | Should -Be 'FullLanguage'
    }

    It 'rejects ConstrainedLanguage and reports the mode for the student message' -ForEach @(
        @{ Mode = 'ConstrainedLanguage' }
        @{ Mode = 'RestrictedLanguage' }
        @{ Mode = 'NoLanguage' }
    ) {
        $state = Get-LanguageModeState -LanguageModeProvider { $Mode }
        $state.is_full | Should -BeFalse
        $state.mode | Should -Be $Mode
    }

    It 'degrades to Unknown instead of throwing when the mode cannot be read' {
        $state = Get-LanguageModeState -LanguageModeProvider { throw 'blocked by policy' }
        $state.is_full | Should -BeFalse
        $state.mode | Should -Be 'Unknown'
    }

    It 'does not route the language-mode failure through the .NET-dependent AI helper' {
        # ConstrainedLanguage 下 Get-InstallDiagnostics／Invoke-RestMethod 一定失敗，
        # 所以這一關必須自行結束，不能呼叫 Stop-Zh。
        $source = Get-Content $script:InstallerPath -Raw
        $gate = [regex]::Match($source,
            '(?s)if \(\$ExecutionContext\.SessionState\.LanguageMode -ne ''FullLanguage''\).*?\r?\n\}').Value
        $gate | Should -Not -BeNullOrEmpty
        $gate | Should -Not -Match 'Stop-Zh'
        $gate | Should -Match 'exit 1'
    }

    It 'gates the language mode before any property assignment can abort the script' {
        # 回歸測試：語言模式檢查原本放在步驟 0，但第 5 行的
        # $Host.UI.RawUI.WindowTitle = ... 是非核心型別的屬性設定，
        # 在 ConstrainedLanguage 下會先讓腳本中止，學生只看得到一行原始紅字。
        $lines = Get-Content $script:InstallerPath
        $gateLine = ($lines | Select-String -SimpleMatch '$ExecutionContext.SessionState.LanguageMode -ne' |
            Select-Object -First 1).LineNumber
        $gateLine | Should -Not -BeNullOrEmpty

        # 閘門之前不得出現任何屬性指派（形如 $a.b.c = ...）。
        $before = $lines[0..($gateLine - 2)]
        foreach ($line in $before) {
            $line | Should -Not -Match '^\s*\$[A-Za-z_]\w*(\.\w+)+\s*='
        }

        # 視窗標題設定必須在閘門之後，而且要被 try/catch 包住。
        $titleLine = ($lines | Select-String -SimpleMatch '$Host.UI.RawUI.WindowTitle' |
            Select-Object -First 1).LineNumber
        $titleLine | Should -BeGreaterThan $gateLine
        $lines[$titleLine - 1] | Should -Match 'try\s*\{.*catch'
    }
}

Describe 'Execution policy preflight' {
    It 'treats permissive effective policies as runnable' -ForEach @(
        @{ Policy = 'RemoteSigned' }
        @{ Policy = 'Unrestricted' }
        @{ Policy = 'Bypass' }
    ) {
        $state = Get-ExecutionPolicyState -EffectiveProvider { $Policy } -PolicyProvider { @() }
        $state.allows_local_script | Should -BeTrue
        $state.locked_by_group_policy | Should -BeFalse
    }

    It 'flags Restricted as needing a change' {
        $state = Get-ExecutionPolicyState -EffectiveProvider { 'Restricted' } -PolicyProvider {
            @([pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = 'Undefined' }
              [pscustomobject]@{ Scope = 'CurrentUser'; ExecutionPolicy = 'Undefined' })
        }
        $state.allows_local_script | Should -BeFalse
        $state.locked_by_group_policy | Should -BeFalse
    }

    It 'detects a group policy lock that Set-ExecutionPolicy -Scope CurrentUser cannot beat' -ForEach @(
        @{ Scope = 'MachinePolicy' }
        @{ Scope = 'UserPolicy' }
    ) {
        $state = Get-ExecutionPolicyState -EffectiveProvider { 'AllSigned' } -PolicyProvider {
            @([pscustomobject]@{ Scope = $Scope; ExecutionPolicy = 'AllSigned' })
        }
        $state.allows_local_script | Should -BeFalse
        $state.locked_by_group_policy | Should -BeTrue
    }

    It 'does not treat a permissive group policy as a lock' {
        $state = Get-ExecutionPolicyState -EffectiveProvider { 'RemoteSigned' } -PolicyProvider {
            @([pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = 'RemoteSigned' })
        }
        $state.locked_by_group_policy | Should -BeFalse
    }

    It 'reports failure instead of throwing when the policy cannot be set' {
        Set-CourseExecutionPolicy -PolicySetter { throw 'blocked by group policy' } | Should -BeFalse
        Set-CourseExecutionPolicy -PolicySetter { } | Should -BeTrue
    }
}

Describe 'Downloaded file unblocking' {
    It 'unblocks every PowerShell file in the installer folder' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("unblock-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $fixture | Out-Null
        try {
            'a' | Set-Content (Join-Path $fixture 'one.ps1')
            'b' | Set-Content (Join-Path $fixture 'two.ps1')
            'c' | Set-Content (Join-Path $fixture 'notes.txt')
            $script:unblocked = @()
            $count = Unblock-CourseScriptFile -Directory $fixture -Unblocker {
                param($path)
                $script:unblocked += [System.IO.Path]::GetFileName($path)
            }
            $count | Should -Be 2
            $script:unblocked | Should -Contain 'one.ps1'
            $script:unblocked | Should -Not -Contain 'notes.txt'
        } finally {
            Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns zero when the installer was loaded without a folder' {
        Unblock-CourseScriptFile -Directory '' | Should -Be 0
    }

    It 'keeps going when one file cannot be unblocked' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("unblock-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $fixture | Out-Null
        try {
            'a' | Set-Content (Join-Path $fixture 'bad.ps1')
            'b' | Set-Content (Join-Path $fixture 'good.ps1')
            $count = Unblock-CourseScriptFile -Directory $fixture -Unblocker {
                param($path)
                if ($path -like '*bad.ps1') { throw 'access denied' }
            }
            $count | Should -Be 1
        } finally {
            Remove-Item $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'GitHub login prerequisite gate' {
    It 'reports ready when network and browser are both usable' {
        $result = Test-GitHubLoginPrerequisite -NetworkProbe { $true } -BrowserProbe { $true }
        $result.ready | Should -BeTrue
        $result.blockers | Should -BeNullOrEmpty
    }

    It 'blocks on network before the student waits for a browser timeout' {
        $result = Test-GitHubLoginPrerequisite -NetworkProbe { $false } -BrowserProbe { $true }
        $result.ready | Should -BeFalse
        $result.blockers | Should -Be @('network')
    }

    It 'reports a missing browser association as a non-fatal blocker' {
        $result = Test-GitHubLoginPrerequisite -NetworkProbe { $true } -BrowserProbe { $false }
        $result.blockers | Should -Be @('browser')
    }

    It 'reports both blockers together' {
        $result = Test-GitHubLoginPrerequisite -NetworkProbe { $false } -BrowserProbe { $false }
        $result.blockers | Should -Be @('network', 'browser')
    }

    It 'treats elevation probe failure as not elevated' {
        Test-CourseElevation -IdentityProvider { throw 'denied' } | Should -BeFalse
        Test-CourseElevation -IdentityProvider { $true } | Should -BeTrue
    }

    It 'treats a missing URL association as no default browser' {
        Test-DefaultBrowserAssociation -AssociationProvider { throw 'no such key' } | Should -BeFalse
        Test-DefaultBrowserAssociation -AssociationProvider { '' } | Should -BeFalse
        Test-DefaultBrowserAssociation -AssociationProvider { 'ChromeHTML' } | Should -BeTrue
    }
}

Describe 'GitHub token scope detection' {
    It 'reports not_logged_in on a non-zero gh exit code' {
        $state = Get-GitHubAuthState -StatusProvider {
            [pscustomobject]@{ exit_code = 1; text = 'You are not logged into any GitHub hosts.' }
        }
        $state.state | Should -Be 'not_logged_in'
    }

    It 'reports the exact missing scopes when the token is too narrow' {
        $state = Get-GitHubAuthState -RequiredScopes @('repo', 'read:org', 'workflow') -StatusProvider {
            [pscustomobject]@{ exit_code = 0; text = "  - Token scopes: 'gist', 'read:org', 'repo'" }
        }
        $state.state | Should -Be 'insufficient_scope'
        $state.missing_scopes | Should -Be @('workflow')
    }

    It 'reports every missing scope, not just the first' {
        $state = Get-GitHubAuthState -RequiredScopes @('repo', 'read:org', 'workflow') -StatusProvider {
            [pscustomobject]@{ exit_code = 0; text = "  - Token scopes: 'gist'" }
        }
        $state.missing_scopes | Should -Be @('repo', 'read:org', 'workflow')
    }

    It 'accepts a token that covers every required scope' {
        $state = Get-GitHubAuthState -RequiredScopes @('repo', 'read:org', 'workflow') -StatusProvider {
            [pscustomobject]@{ exit_code = 0; text = "  - Token scopes: 'gist', 'read:org', 'repo', 'workflow'" }
        }
        $state.state | Should -Be 'authenticated'
        $state.missing_scopes | Should -BeNullOrEmpty
    }

    It 'does not lock out a working environment when gh reports no scope line' {
        $state = Get-GitHubAuthState -RequiredScopes @('repo') -StatusProvider {
            [pscustomobject]@{ exit_code = 0; text = "  - Logged in to github.com account someone (keyring)" }
        }
        $state.state | Should -Be 'authenticated'
    }

    It 'requests the course scopes at login so a fresh login is not immediately insufficient' {
        $source = Get-Content $script:InstallerPath -Raw
        $source | Should -Match 'gh auth login --hostname github\.com --git-protocol https --web -s'
        $source | Should -Match "\`$CourseGitHubScopes = @\('repo', 'read:org', 'workflow'\)"
    }
}

Describe 'Network-loaded installer' {
    It 'does not crash resolving the pattern file when loaded without a script folder' {
        # 一行安裝指令會讓 $PSScriptRoot 為空，Join-Path 會擲出終止性錯誤。
        $source = Get-Content $script:InstallerPath -Raw
        $source | Should -Match '(?s)IsNullOrWhiteSpace\(\$PSScriptRoot\).*?install-support-patterns\.json'
    }
}

