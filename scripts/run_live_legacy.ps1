# ============================================================
# SLEEPER FANTASY FOOTBALL TIDBYT LIVE LOOP
#
# Direct API-push mode:
# Each standings page is rendered and pushed separately.
# The Starlark app calculates the correct transition timing
# based on the actual marquee animation length for that page.
# ============================================================

$ErrorActionPreference = "Stop"

$SettingsPath = Join-Path $PSScriptRoot "..\config\settings.ps1"
$StarFile = Join-Path $PSScriptRoot "..\app\sleeper_ff.star"
$WebpFile = Join-Path $PSScriptRoot "..\app\sleeper_ff.webp"

# ============================================================
# LOAD AND VALIDATE SETTINGS
# ============================================================

if (-not (Test-Path $SettingsPath)) {
    throw "Missing config\settings.ps1."
}

. $SettingsPath

if ([string]::IsNullOrWhiteSpace($SleeperLeagueId)) {
    throw "SleeperLeagueId is missing from config\settings.ps1."
}

if ([string]::IsNullOrWhiteSpace($TidbytDeviceId)) {
    throw "TidbytDeviceId is missing from config\settings.ps1."
}

if ([string]::IsNullOrWhiteSpace($TidbytApiToken)) {
    throw "TidbytApiToken is missing from config\settings.ps1."
}

if ([string]::IsNullOrWhiteSpace($InstallationId)) {
    throw "InstallationId is missing from config\settings.ps1."
}

if ($InstallationId -notmatch '^[a-zA-Z0-9]+$') {
    throw "InstallationId must contain only letters and numbers. Example: sleeperff"
}

if ($null -eq $RetrySeconds -or $RetrySeconds -lt 1) {
    $RetrySeconds = 5
}

$env:TIDBYT_API_TOKEN = $TidbytApiToken

# ============================================================
# SCREEN ROTATION
# ============================================================

$StandingsPages = @(1, 2)

Write-Host ""
Write-Host "=== Sleeper FF Tidbyt Live Loop ===" -ForegroundColor Cyan
Write-Host "League ID:             $SleeperLeagueId"
Write-Host "Device ID:             $TidbytDeviceId"
Write-Host "Installation ID:       $InstallationId"
Write-Host ""
Write-Host "Each page switches after its first completed marquee cycle." -ForegroundColor DarkGray
Write-Host "Press Ctrl + C to stop." -ForegroundColor Yellow
Write-Host ""

while ($true) {
    foreach ($Page in $StandingsPages) {
        $Timestamp = Get-Date -Format "HH:mm:ss"

        Write-Host "[$Timestamp] Rendering standings page $Page..."

        $RenderOutput = @(
            & pixlet render `
                $StarFile `
                "league_id=$SleeperLeagueId" `
                "standings_page=$Page" 2>&1
        )

        $RenderExitCode = $LASTEXITCODE

        $RenderOutput |
            ForEach-Object {
                Write-Host $_
            }

        if ($RenderExitCode -ne 0) {
            Write-Host "[$Timestamp] Render failed. Retrying in $RetrySeconds seconds." -ForegroundColor Red
            Write-Host ""

            Start-Sleep -Seconds $RetrySeconds
            continue
        }

        if (-not (Test-Path $WebpFile)) {
            Write-Host "[$Timestamp] Render completed, but the WebP file was not found. Retrying in $RetrySeconds seconds." -ForegroundColor Red
            Write-Host ""

            Start-Sleep -Seconds $RetrySeconds
            continue
        }

        $RenderText = $RenderOutput -join "`n"

        $SwitchMatch = [regex]::Match(
            $RenderText,
            'PAGE_SWITCH_AFTER_MS=(\d+)'
        )

        if (-not $SwitchMatch.Success) {
            Write-Host "[$Timestamp] Could not determine the page transition timing. Retrying in $RetrySeconds seconds." -ForegroundColor Red
            Write-Host ""

            Start-Sleep -Seconds $RetrySeconds
            continue
        }

        $SwitchAfterMilliseconds = [int] $SwitchMatch.Groups[1].Value
        $SwitchAfterSeconds = [math]::Round(
            $SwitchAfterMilliseconds / 1000,
            1
        )

        Write-Host "[$Timestamp] Render succeeded. Pushing page $Page to Tidbyt..."

        pixlet push `
            --installation-id $InstallationId `
            $TidbytDeviceId `
            $WebpFile

        if ($LASTEXITCODE -ne 0) {
            Write-Host "[$Timestamp] Push failed. Retrying in $RetrySeconds seconds." -ForegroundColor Red
            Write-Host ""

            Start-Sleep -Seconds $RetrySeconds
            continue
        }

        Write-Host "[$Timestamp] Push succeeded. Switching pages in approximately $SwitchAfterSeconds seconds." -ForegroundColor Green
        Write-Host ""

        Start-Sleep -Milliseconds $SwitchAfterMilliseconds
    }
}