#requires -Version 5.1
<#
.SYNOPSIS
    Create a throwaway self-signed code-signing certificate to prove the build.ps1 signing pipeline.
.DESCRIPTION
    This is for PIPELINE TESTING ONLY. A self-signed cert makes Windows/SmartScreen still warn users
    (untrusted publisher) — it does NOT replace a real CA or Azure Trusted Signing certificate. Its
    only purpose is to confirm `build.ps1 -Sign` wires signtool up correctly end to end, so that a
    real certificate later is a drop-in.

    Creates a code-signing cert in the CurrentUser\My store. By default it also trusts the cert on
    THIS machine (adds it to CurrentUser\Root) so `signtool verify /pa` passes locally, and exports a
    PFX you can hand to build.ps1 via -CertPath. Prints the thumbprint for -CertThumbprint use.
.PARAMETER Subject
    Certificate subject. Defaults to a Display-Selector dev identity.
.PARAMETER PfxPath
    Where to export the PFX. Defaults to build/DisplaySelector-selfsigned.pfx (git-ignored — do not commit).
.PARAMETER Password
    PFX export password. If omitted, a prompt asks for one (SecureString).
.PARAMETER NoTrust
    Skip adding the cert to CurrentUser\Root. `signtool verify /pa` will then report the signature as
    untrusted (build.ps1 downgrades that to a warning), which mirrors what real users would see.
.EXAMPLE
    ./build/new-selfsigned-cert.ps1
    ./build/build.ps1 -Sign -CertThumbprint <printed-thumbprint>
.EXAMPLE
    # PFX flow (e.g. to mimic a CI secret):
    ./build/new-selfsigned-cert.ps1 -Password (Read-Host -AsSecureString)
    ./build/build.ps1 -Sign -CertPath ./build/DisplaySelector-selfsigned.pfx -CertPassword <pw>
#>
[CmdletBinding()]
param(
    [string]$Subject = 'CN=Display-Selector Dev (self-signed, testing only)',
    [string]$PfxPath = (Join-Path $PSScriptRoot 'DisplaySelector-selfsigned.pfx'),
    [System.Security.SecureString]$Password,
    [switch]$NoTrust
)

$ErrorActionPreference = 'Stop'

Write-Warning 'Self-signed cert = PIPELINE TESTING ONLY. Users still get an untrusted-publisher/SmartScreen warning.'

# Create a code-signing cert (EKU 1.3.6.1.5.5.7.3.3) in CurrentUser\My.
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $Subject `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeyExportPolicy Exportable `
    -KeyUsage DigitalSignature `
    -NotAfter (Get-Date).AddYears(3)

Write-Host "Created cert: $($cert.Subject)" -ForegroundColor Green
Write-Host "Thumbprint : $($cert.Thumbprint)" -ForegroundColor Green

if (-not $NoTrust) {
    # Trust it on this machine only so `signtool verify /pa` succeeds during pipeline testing.
    $root = Get-Item 'Cert:\CurrentUser\Root'
    $root.Open('ReadWrite')
    $root.Add($cert)
    $root.Close()
    Write-Host 'Added to CurrentUser\Root (trusted on this machine for verify).' -ForegroundColor Green
}

if (-not $Password) {
    $Password = Read-Host -Prompt 'PFX export password' -AsSecureString
}
Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $Password | Out-Null
Write-Host "Exported PFX: $PfxPath" -ForegroundColor Green

Write-Host ''
Write-Host 'Next, prove the pipeline with either:' -ForegroundColor Cyan
Write-Host "  ./build/build.ps1 -Sign -CertThumbprint $($cert.Thumbprint)"
Write-Host "  ./build/build.ps1 -Sign -CertPath `"$PfxPath`" -CertPassword <password>"
Write-Host ''
Write-Host 'To remove this test cert later:' -ForegroundColor Cyan
Write-Host "  Remove-Item Cert:\CurrentUser\My\$($cert.Thumbprint)"
if (-not $NoTrust) {
    Write-Host "  Remove-Item Cert:\CurrentUser\Root\$($cert.Thumbprint)"
}
