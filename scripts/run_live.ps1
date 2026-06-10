# ============================================================
# SLEEPER FANTASY FOOTBALL TIDBYT STARTUP WRAPPER
#
# Loads private local settings and launches the Python
# screen-queue controller.
# ============================================================

$ErrorActionPreference = "Stop"

$SettingsPath = Join-Path $PSScriptRoot "..\config\settings.ps1"
$ControllerFile = Join-Path $PSScriptRoot "..\controller\run_live.py"

if (-not (Test-Path $SettingsPath)) {
    throw "Missing config\settings.ps1."
}

if (-not (Test-Path $ControllerFile)) {
    throw "Missing controller\run_live.py."
}

. $SettingsPath

# Export local settings for the Python controller.
$env:SLEEPER_LEAGUE_ID = [string] $SleeperLeagueId
$env:MY_TEAM_NAME = [string] $MyTeamName
$env:FEATURED_TEAM = [string] $FeaturedTeam
$env:HISTORICAL_WEEK_OVERRIDE = [string] $HistoricalWeekOverride

$env:TIDBYT_DEVICE_ID = [string] $TidbytDeviceId
$env:TIDBYT_API_TOKEN = [string] $TidbytApiToken
$env:INSTALLATION_ID = [string] $InstallationId

$env:SHOW_STANDINGS = [string] $ShowStandings
$env:RETRY_SECONDS = [string] $RetrySeconds

# Prefer the standard Python command.
$PythonCommand = Get-Command python -ErrorAction SilentlyContinue

if ($null -ne $PythonCommand) {
    & python $ControllerFile
    exit $LASTEXITCODE
}

# Fall back to the Windows Python launcher.
$PyLauncher = Get-Command py -ErrorAction SilentlyContinue

if ($null -ne $PyLauncher) {
    & py -3 $ControllerFile
    exit $LASTEXITCODE
}

throw "Python was not found. Install Python or add it to PATH."
