#requires -Version 7.3

[CmdletBinding()]
Param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$upstreamUrl = 'https://github.com/zed-industries/zed.git'
$innoSetupPaths = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)

$visualStudioRoots = @(
    "$env:ProgramFiles\Microsoft Visual Studio",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio"
) | Where-Object { Test-Path -LiteralPath $_ }
$vsDevShell = $visualStudioRoots |
    ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter 'Launch-VsDevShell.ps1' -File -Recurse -ErrorAction SilentlyContinue } |
    Select-Object -First 1
if (-not $vsDevShell) {
    throw 'Required Windows build dependency is missing: Visual Studio C++ build tools'
}

$windowsKitsBin = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
$makeAppx = if (Test-Path -LiteralPath $windowsKitsBin) {
    Get-ChildItem -LiteralPath $windowsKitsBin -Filter 'makeAppx.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
if (-not $makeAppx) {
    throw 'Required Windows build dependency is missing: Windows SDK makeAppx.exe'
}

if (-not ($innoSetupPaths | Where-Object { Test-Path -LiteralPath $_ })) {
    throw 'Required Windows build dependency is missing: Inno Setup 6'
}

if (Get-Process -Name Zed -ErrorAction SilentlyContinue) {
    throw 'Close all Zed windows and run this script from an external PowerShell terminal.'
}

Push-Location $repoRoot
try {
    if ((git branch --show-current) -ne 'neovide-cursor') {
        throw 'Switch to the neovide-cursor branch before updating.'
    }

    if (@(git status --porcelain).Count -gt 0) {
        throw 'The working tree must be clean before updating.'
    }

    if (@(git remote) -contains 'upstream') {
        if ((git remote get-url upstream) -ne $upstreamUrl) {
            throw 'The upstream remote points to an unexpected repository.'
        }
    }
    else {
        git remote add upstream $upstreamUrl
    }

    $previousHead = git rev-parse HEAD
    git fetch upstream main

    try {
        git rebase upstream/main
    }
    catch {
        Write-Host "Rebase failed. Resolve conflicts and run 'git rebase --continue'." -ForegroundColor Red
        Write-Host "Previous HEAD: $previousHead" -ForegroundColor Red
        throw
    }

    cargo check -p editor
    cargo test -p editor cursor_animation
    & "$PSScriptRoot\bundle-windows.ps1" -Install
}
finally {
    Pop-Location
}
