# Windows Course Toolchain Installer Loader
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Parse parameters manually from $args to allow Invoke-Expression execution without syntax errors
$Profile = 'full'
$NonInteractive = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '-Profile' -and $i + 1 -lt $args.Count) {
        $Profile = $args[$i+1]
        $i++
    } elseif ($args[$i] -eq '-NonInteractive') {
        $NonInteractive = $true
    }
}

$PSScriptRootVal = $PSScriptRoot
if (-not $PSScriptRootVal) {
    # Running in memory (e.g., via Invoke-Expression). Create a temp dir and copy or download dependencies.
    $tempDir = Join-Path $env:TEMP "course-toolchain-installer-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $PSScriptRootVal = $tempDir
    
    $localScriptsDir = Join-Path (Get-Location) "scripts"
    $useLocal = (Test-Path (Join-Path $localScriptsDir "course-toolchain-windows.ps1"))
    
    $baseUrl = "https://raw.githubusercontent.com/drgarbage/ag-course-index/main/scripts"
    
    # Base files
    $files = @(
        "course-toolchain-windows.ps1",
        "toolchain/windows.ps1",
        "toolchain/report.ps1",
        "toolchain/catalog.json",
        "toolchain/ui-windows.ps1",
        "install-git-gh-windows.ps1"
    )
    
    foreach ($file in $files) {
        $destPath = Join-Path $tempDir $file
        $destDir = Split-Path $destPath
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        
        if ($useLocal) {
            $srcPath = Join-Path $localScriptsDir $file
            Copy-Item -Path $srcPath -Destination $destPath -Force
        } else {
            $url = "$baseUrl/$file"
            Invoke-RestMethod -Uri $url -OutFile $destPath
        }
    }
    
    # Download or copy vendor localization manifest and dicts
    if ($useLocal) {
        $srcManifest = Join-Path $localScriptsDir "vendor/antigravity2-cn/manifest.json"
        $destManifest = Join-Path $tempDir "vendor/antigravity2-cn/manifest.json"
        $destDir = Split-Path $destManifest
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -Path $srcManifest -Destination $destManifest -Force
        
        $manifestContent = Get-Content -Raw -Path $destManifest | ConvertFrom-Json
        foreach ($fileObj in $manifestContent.files) {
            $filePath = $fileObj.path
            $srcFile = Join-Path $localScriptsDir "vendor/antigravity2-cn/$filePath"
            $destFile = Join-Path $tempDir "vendor/antigravity2-cn/$filePath"
            $destFileDir = Split-Path $destFile
            if (-not (Test-Path $destFileDir)) {
                New-Item -ItemType Directory -Path $destFileDir -Force | Out-Null
            }
            Copy-Item -Path $srcFile -Destination $destFile -Force
        }
    } else {
        $manifestUrl = "$baseUrl/vendor/antigravity2-cn/manifest.json"
        $manifestPath = Join-Path $tempDir "vendor/antigravity2-cn/manifest.json"
        $manifestDir = Split-Path $manifestPath
        if (-not (Test-Path $manifestDir)) {
            New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        }
        Invoke-RestMethod -Uri $manifestUrl -OutFile $manifestPath
        
        $manifestContent = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
        foreach ($fileObj in $manifestContent.files) {
            $filePath = $fileObj.path
            $fileUrl = "$baseUrl/vendor/antigravity2-cn/$filePath"
            $fileDest = Join-Path $tempDir "vendor/antigravity2-cn/$filePath"
            $fileDestDir = Split-Path $fileDest
            if (-not (Test-Path $fileDestDir)) {
                New-Item -ItemType Directory -Path $fileDestDir -Force | Out-Null
            }
            Invoke-RestMethod -Uri $fileUrl -OutFile $fileDest
        }
    }
}

# Dot-source the planner modules from the resolved path
$script:PlannerPath = Join-Path $PSScriptRootVal 'course-toolchain-windows.ps1'
if (-not (Test-Path -LiteralPath $script:PlannerPath -PathType Leaf)) {
    throw "Main planner package not found: $script:PlannerPath"
}
. $script:PlannerPath

# Dot-source the UI module from the resolved path
$script:UIPath = Join-Path $PSScriptRootVal 'toolchain/ui-windows.ps1'
if (-not (Test-Path -LiteralPath $script:UIPath -PathType Leaf)) {
    throw "Main UI package not found: $script:UIPath"
}
. $script:UIPath
