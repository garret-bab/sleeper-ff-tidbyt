param(
    [ValidateSet(1, 2)]
    [int] $Page = 1
)

$ErrorActionPreference = "Stop"

$SettingsPath = Join-Path $PSScriptRoot "..\config\settings.ps1"
$StarFile = Join-Path $PSScriptRoot "..\app\sleeper_ff.star"
$WebpFile = Join-Path $PSScriptRoot "..\app\sleeper_ff.webp"

if (-not (Test-Path $SettingsPath)) {
    throw "Missing config\settings.ps1."
}

. $SettingsPath

if ([string]::IsNullOrWhiteSpace($SleeperLeagueId)) {
    throw "SleeperLeagueId is missing from config\settings.ps1."
}

Write-Host ""
Write-Host "=== Sleeper FF Tidbyt Local Render ===" -ForegroundColor Cyan
Write-Host "League ID:       $SleeperLeagueId"
Write-Host "Standings page:  $Page"
Write-Host ""

pixlet render `
    $StarFile `
    "league_id=$SleeperLeagueId" `
    "standings_page=$Page"

if ($LASTEXITCODE -ne 0) {
    throw "Pixlet render failed."
}

Write-Host ""
Write-Host "Render succeeded:" -ForegroundColor Green
Write-Host $WebpFile