#requires -Version 5.1
<#
.SYNOPSIS
    Build, test, publish, and package the Display-Selector installer.
.DESCRIPTION
    Pipeline: unit tests -> publish (self-contained, loose files, win-x64) -> Inno Setup compile.
.PARAMETER IncludeIntegration
    Also run the Category=Integration tests (real Windows APIs; needs a desktop session).
.PARAMETER SkipTests
    Skip all tests and go straight to publish + package.
.PARAMETER Sign
    Authenticode-sign the published app exe and the installer with signtool. Requires a certificate,
    supplied either as a PFX (-CertPath/-CertPassword) or by store thumbprint (-CertThumbprint), or
    via the DS_SIGN_CERT_PATH / DS_SIGN_CERT_PASSWORD / DS_SIGN_CERT_THUMBPRINT env vars. Unsigned
    builds work exactly as before when this switch is omitted.

    To prove the pipeline with a throwaway self-signed cert, run build/new-selfsigned-cert.ps1 first,
    then pass -Sign with the thumbprint it prints. A real (CA or Azure Trusted Signing) certificate
    later is a drop-in: same switch, different cert source.
.PARAMETER CertPath
    Path to a PFX code-signing certificate. Defaults to $env:DS_SIGN_CERT_PATH.
.PARAMETER CertPassword
    Password for the PFX. Defaults to $env:DS_SIGN_CERT_PASSWORD.
.PARAMETER CertThumbprint
    SHA1 thumbprint of a code-signing cert already in a certificate store (takes precedence over
    -CertPath). Defaults to $env:DS_SIGN_CERT_THUMBPRINT.
.PARAMETER TimestampUrl
    RFC 3161 timestamp server. Defaults to DigiCert's.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CertPassword',
    Justification = 'signtool consumes the PFX password as a plain string on the command line; a SecureString would be converted straight back.')]
param(
    [switch]$IncludeIntegration,
    [switch]$SkipTests,
    [switch]$Sign,
    [string]$CertPath = $env:DS_SIGN_CERT_PATH,
    [string]$CertPassword = $env:DS_SIGN_CERT_PASSWORD,
    [string]$CertThumbprint = $env:DS_SIGN_CERT_THUMBPRINT,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$app = Join-Path $root 'src/DisplaySelector'
$tests = Join-Path $root 'tests/DisplaySelector.Tests'
$publishDir = Join-Path $root 'publish'
$iss = Join-Path $root 'installer/setup.iss'
$csproj = Join-Path $app 'DisplaySelector.csproj'

# Single source of truth for the version: the app .csproj <Version>. We pass it to the installer
# compiler (/DAppVersion=) so setup.iss never has to be edited on a version bump.
$version = ([xml](Get-Content $csproj)).Project.PropertyGroup.Version |
    Where-Object { $_ } | Select-Object -First 1
if (-not $version) { throw "Could not read <Version> from $csproj." }
Write-Host "==> Version $version (from $([System.IO.Path]::GetFileName($csproj)))" -ForegroundColor Cyan

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed (exit $LASTEXITCODE)."
    }
}

# Locate signtool: prefer the newest Windows SDK bin, then fall back to PATH.
function Get-SignTool {
    $roots = @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ }
    # Sort by the SDK version dir (the '*' between bin and x64) numerically, not lexically — a string
    # sort misorders build-number segments of differing lengths and could pick an older signtool.
    $tool = $roots |
        ForEach-Object { Get-ChildItem -Path (Join-Path $_ 'Windows Kits\10\bin\*\x64\signtool.exe') -ErrorAction SilentlyContinue } |
        Sort-Object { try { [version]$_.Directory.Parent.Name } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $tool) {
        $cmd = Get-Command signtool -ErrorAction SilentlyContinue
        if ($cmd) { $tool = $cmd.Source }
    }
    return $tool
}

# Authenticode-sign one file with the configured certificate source. The cert source is the only
# thing that changes between a self-signed proof and a real CA / Azure Trusted Signing cert.
function Invoke-Sign {
    param([string]$SignTool, [string]$File)

    $signArgs = @('sign', '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256')
    if ($CertThumbprint) {
        # Cert already installed in a store (e.g. CurrentUser\My) — used by the self-signed helper.
        $signArgs += @('/sha1', $CertThumbprint)
    }
    elseif ($CertPath) {
        $signArgs += @('/f', $CertPath)
        if ($CertPassword) { $signArgs += @('/p', $CertPassword) }
    }
    else {
        throw 'Signing requested (-Sign) but no certificate given. Provide -CertThumbprint or -CertPath (or the DS_SIGN_* env vars).'
    }
    $signArgs += $File

    & $SignTool @signArgs
    if ($LASTEXITCODE -ne 0) { throw "signtool failed for $File (exit $LASTEXITCODE)." }

    # Verify with the default authenticode policy. A self-signed cert only verifies if it (or its
    # root) is trusted on this machine — so treat a verify failure as a warning, not a hard stop.
    & $SignTool verify /pa $File
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Signature applied but not trusted by /pa verify for $File (expected for a self-signed cert not in a trusted root)."
    }
    # The verify above is advisory. Reset so its (expected) non-zero exit for a self-signed cert does
    # not leak out as build.ps1's overall exit code and falsely flag the build as failed.
    $global:LASTEXITCODE = 0
}

# Resolve signtool up front so a misconfigured -Sign fails before we spend time on tests/publish.
$signtool = $null
if ($Sign) {
    $signtool = Get-SignTool
    if (-not $signtool) {
        throw 'Signing requested (-Sign) but signtool.exe was not found. Install the Windows SDK signing tools, or drop -Sign.'
    }
    Write-Host "==> Signing enabled (signtool: $signtool)" -ForegroundColor Cyan
}

if (-not $SkipTests) {
    Invoke-Step 'Unit tests' {
        dotnet test $tests -c Release --filter 'Category!=Integration'
    }
    if ($IncludeIntegration) {
        Invoke-Step 'Integration tests' {
            dotnet test $tests -c Release --filter 'Category=Integration'
        }
    }
}

if (Test-Path $publishDir) {
    Remove-Item $publishDir -Recurse -Force
}

Invoke-Step 'Publish' {
    # Loose files (NOT single-file): a compressed single-file bundle gets extracted/memory-mapped at
    # runtime, which inflates and churns the Working Set. Publishing loose keeps the footprint lower
    # and steadier. Still fully self-contained (bundled runtime) — no prerequisite on the user's PC.
    # The installer's [Files] glob (publish\*) already ships whatever this produces.
    dotnet publish $app -c Release -r win-x64 --self-contained `
        -p:PublishSingleFile=false `
        -o $publishDir
}

# Sign the app exe before packaging so the installer ships a signed binary. Not wrapped in
# Invoke-Step: Invoke-Sign throws on real failure itself, and its last call (verify) can return
# non-zero for a self-signed cert without meaning the build failed.
if ($Sign) {
    Write-Host '==> Sign app' -ForegroundColor Cyan
    Invoke-Sign -SignTool $signtool -File (Join-Path $publishDir 'DisplaySelector.exe')
}

# Inno Setup is optional locally; warn rather than fail if the compiler is absent.
# Prefer the stable v6, then fall back to any installed edition (e.g. 7.x), then PATH.
$roots = @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ }
$iscc = $roots | ForEach-Object { Join-Path $_ 'Inno Setup 6\ISCC.exe' } |
    Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    $iscc = $roots |
        ForEach-Object { Get-ChildItem -Path (Join-Path $_ 'Inno Setup *\ISCC.exe') -ErrorAction SilentlyContinue } |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $iscc) {
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}

if ($iscc) {
    Invoke-Step 'Package installer' {
        & $iscc "/DAppVersion=$version" $iss
    }
    $installer = Join-Path $root 'installer/Output/DisplaySelectorSetup.exe'
    if (Test-Path $installer) {
        if ($Sign) {
            Write-Host '==> Sign installer' -ForegroundColor Cyan
            Invoke-Sign -SignTool $signtool -File $installer
        }
        Write-Host "Installer: $installer" -ForegroundColor Green
    }
}
else {
    Write-Warning 'Inno Setup (ISCC.exe) not found; skipped packaging. Published app is in /publish.'
}
