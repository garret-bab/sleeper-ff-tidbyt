$ErrorActionPreference = "Stop"

$SettingsPath = Join-Path $PSScriptRoot "..\config\settings.ps1"

if (-not (Test-Path $SettingsPath)) {
    throw "Missing config\settings.ps1. Copy settings.example.ps1 and add your local values."
}

. $SettingsPath

if ([string]::IsNullOrWhiteSpace($SleeperLeagueId)) {
    throw "SleeperLeagueId is missing from config\settings.ps1."
}

if ([string]::IsNullOrWhiteSpace($MyTeamName)) {
    throw "MyTeamName is missing from config\settings.ps1."
}

$BaseUrl = "https://api.sleeper.app/v1"

function Get-SleeperJson {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $Uri = "$BaseUrl/$Path"
    Write-Host "GET $Uri" -ForegroundColor DarkGray

    try {
        return Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 20
    }
    catch {
        throw "Sleeper request failed for $Uri`n$($_.Exception.Message)"
    }
}
function Normalize-TeamName {
    param(
        [AllowNull()]
        [string] $TeamName
    )

    if ([string]::IsNullOrWhiteSpace($TeamName)) {
        return ""
    }

    $Normalized = $TeamName.Replace([char]0x2018, "'")
    $Normalized = $Normalized.Replace([char]0x2019, "'")
    $Normalized = $Normalized.Trim()
    $Normalized = $Normalized.ToLowerInvariant()

    return $Normalized
}
function Get-TeamName {
    param(
        [Parameter(Mandatory = $true)]
        $Roster,

        [Parameter(Mandatory = $true)]
        $UsersById
    )

    $OwnerId = [string] $Roster.owner_id

    if (-not $UsersById.ContainsKey($OwnerId)) {
        return "Roster $($Roster.roster_id)"
    }

    $User = $UsersById[$OwnerId]
    $CustomTeamName = [string] $User.metadata.team_name

    if (-not [string]::IsNullOrWhiteSpace($CustomTeamName)) {
        return $CustomTeamName
    }

    if (-not [string]::IsNullOrWhiteSpace([string] $User.display_name)) {
        return [string] $User.display_name
    }

    return [string] $User.username
}

function Get-FantasyPoints {
    param(
        [Parameter(Mandatory = $true)]
        $RosterSettings
    )

    $WholePoints = 0.0
    $DecimalPoints = 0.0

    if ($null -ne $RosterSettings.fpts) {
        $WholePoints = [double] $RosterSettings.fpts
    }

    if ($null -ne $RosterSettings.fpts_decimal) {
        $DecimalPoints = [double] $RosterSettings.fpts_decimal / 100
    }

    return [math]::Round($WholePoints + $DecimalPoints, 2)
}

Write-Host ""
Write-Host "=== Sleeper Fantasy Football API Test ===" -ForegroundColor Cyan
Write-Host ""

$League = Get-SleeperJson "league/$SleeperLeagueId"

if ($null -eq $League) {
    throw "No league was returned. Check the SleeperLeagueId value."
}

$Users = @(
    (Get-SleeperJson "league/$SleeperLeagueId/users") |
        ForEach-Object { $_ }
)

$Rosters = @(
    (Get-SleeperJson "league/$SleeperLeagueId/rosters") |
        ForEach-Object { $_ }
)

$NflState = Get-SleeperJson "state/nfl"

$UsersById = @{}

foreach ($User in $Users) {
    $UsersById[[string] $User.user_id] = $User
}

Write-Host ""
Write-Host "League:" -ForegroundColor Yellow
Write-Host "  Name:          $($League.name)"
Write-Host "  League ID:     $($League.league_id)"
Write-Host "  Season:        $($League.season)"
Write-Host "  Status:        $($League.status)"
Write-Host "  Total rosters: $($League.total_rosters)"

Write-Host ""
Write-Host "Current NFL state:" -ForegroundColor Yellow
Write-Host "  Season:       $($NflState.season)"
Write-Host "  Season type:  $($NflState.season_type)"
Write-Host "  Week:         $($NflState.week)"
Write-Host "  Display week: $($NflState.display_week)"

$Standings = foreach ($Roster in $Rosters) {
    [PSCustomObject] @{
        RosterId = [int] $Roster.roster_id
        Team     = Get-TeamName -Roster $Roster -UsersById $UsersById
        Wins     = [int] $Roster.settings.wins
        Losses   = [int] $Roster.settings.losses
        Ties     = [int] $Roster.settings.ties
        Points   = Get-FantasyPoints -RosterSettings $Roster.settings
    }
}

$SortedStandings = @(
    $Standings |
        Sort-Object `
            @{ Expression = "Wins"; Descending = $true }, `
            @{ Expression = "Points"; Descending = $true }
)

Write-Host ""
Write-Host "Standings data:" -ForegroundColor Yellow
$SortedStandings | Format-Table -AutoSize

$NormalizedMyTeamName = Normalize-TeamName $MyTeamName

$MyRoster = @(
    $SortedStandings |
        Where-Object {
            (Normalize-TeamName $_.Team) -eq $NormalizedMyTeamName
        }
)

Write-Host ""
Write-Host "Configured team lookup:" -ForegroundColor Yellow

if ($MyRoster.Count -eq 1) {
    Write-Host "  Found '$MyTeamName' as roster $($MyRoster[0].RosterId)." -ForegroundColor Green
}
elseif ($MyRoster.Count -gt 1) {
    throw "Multiple teams matched '$MyTeamName'. Team names must be unique."
}
else {
    Write-Host "  Could not find '$MyTeamName'." -ForegroundColor Red
    Write-Host "  Available team names:" -ForegroundColor Yellow

    foreach ($Standing in $SortedStandings) {
        Write-Host "    - $($Standing.Team)"
    }
}

if (-not [string]::IsNullOrWhiteSpace([string] $HistoricalWeekOverride)) {
    $SelectedWeek = [int] $HistoricalWeekOverride
    $WeekSource = "historical override"
}
else {
    $SelectedWeek = [int] $NflState.week
    $WeekSource = "current NFL state"
}

Write-Host ""
Write-Host "Weekly matchup request:" -ForegroundColor Yellow
Write-Host "  Selected week: $SelectedWeek ($WeekSource)"

$Matchups = @(
    (Get-SleeperJson "league/$SleeperLeagueId/matchups/$SelectedWeek") |
        Where-Object {
            $null -ne $_ -and
            $null -ne $_.roster_id
        }
)

if ($Matchups.Count -eq 0) {
    Write-Host "  No matchup records were returned for Week $SelectedWeek." -ForegroundColor DarkYellow
    Write-Host "  This may be expected during the offseason or before the schedule is available."
}
else {
    Write-Host "  Returned $($Matchups.Count) team matchup records." -ForegroundColor Green

    $Matchups |
        Select-Object matchup_id, roster_id, points |
        Sort-Object matchup_id, roster_id |
        Format-Table -AutoSize
}

Write-Host ""
Write-Host "API test complete." -ForegroundColor Cyan