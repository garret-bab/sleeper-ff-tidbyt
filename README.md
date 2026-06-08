# Sleeper Fantasy Football Tidbyt App

A season-long fantasy football display for Tidbyt devices using live league data from the Sleeper API.

The project currently renders and pushes a two-page league standings display to a physical Tidbyt. It is being developed incrementally, with live weekly matchup scoreboards planned as the next major feature.

## Current Features

### Live Sleeper League Standings

The app retrieves live league data from Sleeper and displays all fantasy teams across two Tidbyt screens.

Each standings page includes:

* Current ranking
* Fantasy-team name
* Wins
* Losses
* Ties, when applicable
* Automatic marquee scrolling for longer names
* A page indicator such as `1/2` or `2/2`

Wins are displayed in teal and losses are displayed in red for quick visual scanning.

### Automatic Sorting

Standings are ranked using:

1. Wins, descending
2. Losses, ascending
3. Total fantasy points scored, descending
4. Team name, alphabetically as a final fallback

The alphabetical fallback keeps preseason standings deterministic while every team remains tied at `0-0`.

### Dynamic Page Timing

Each standings page is rendered independently and pushed through the Tidbyt API.

The Starlark app calculates the animation length of each page based on its longest scrolling team name. It reports the recommended transition time to the PowerShell controller, which waits until the marquee cycle has completed before pushing the next page.

This prevents the next page from appearing:

* Before a long team name finishes scrolling
* Halfway through an active marquee animation
* After the marquee has already started a second unnecessary cycle

Each page remains briefly readable after the names return to their starting positions.

### Team-Name Normalization

Sleeper team names may contain typographic apostrophes or other formatting differences. The app normalizes apostrophes into standard keyboard characters before rendering.

For example:

```text
Example Team’s Name
```

becomes:

```text
Example Team's Name
```

This keeps matching and display behavior consistent.

### Display Aliases for Oversized Names

Some team names may be too long to complete a readable marquee cycle within the Tidbyt playback window.

The app supports compact display-only aliases for those edge cases. The original Sleeper team name remains unchanged internally for roster matching, featured-team selection, and API lookups.

## Planned Features

### Weekly Fantasy Matchup Scoreboards

The next development phase will add weekly matchup screens using Sleeper matchup data.

Planned scoreboard behavior:

* Retrieve the active NFL week automatically
* Group opponents by Sleeper `matchup_id`
* Display both fantasy-team names
* Display team icons or avatars
* Show live fantasy scores during active games
* Show final scores after games conclude
* Cycle through every league matchup automatically

### Featured Matchup Mode

A configurable featured-team setting is planned.

Expected behavior:

```text
Featured team left blank
        ↓
Cycle through every matchup

Featured team populated
        ↓
Display only the matchup involving that team
```

This will allow a user to pin one matchup while retaining the option to rotate through the full league scoreboard.

During private API-push development, the value will be configured locally. If the app is later packaged as a Tidbyt Community App, the same concept may be exposed as an install-time setting inside the Tidbyt mobile app.

### Pregame Projected Scores

Before the first NFL game of a fantasy week begins, the matchup screens may display projected final scores.

This will be added after the live scoreboard foundation is stable.

### Touchdown Alerts

Touchdown alerts are planned as a secondary enhancement after standings and live scoreboards are complete.

Potential alert behavior:

```text
TOUCHDOWN
PLAYER NAME
60 YD RUSH TD
+12.0 FPTS
```

The touchdown layer may use an external NFL play-by-play source in addition to Sleeper so the app can display richer event details such as:

* Player name
* Touchdown type
* Yardage
* Game clock
* Fantasy-point impact

The alert system would use a priority queue so scoring events temporarily interrupt the normal scoreboard rotation without losing other alerts during rapid scoring sequences.

## Project Structure

```text
sleeper-ff-tidbyt/
├── app/
│   ├── sleeper_ff.star
│   └── sleeper_ff.webp
│
├── config/
│   ├── settings.ps1
│   └── settings.example.ps1
│
├── scripts/
│   ├── render_once.ps1
│   ├── run_live.ps1
│   └── test_sleeper_api.ps1
│
├── .gitignore
└── README.md
```

### `app/sleeper_ff.star`

Main Tidbyt Starlark application.

Responsibilities currently include:

* Fetch Sleeper users and rosters
* Resolve fantasy-team names
* Normalize team names
* Build and sort standings
* Render two standings pages
* Calculate page-specific animation timing
* Apply display-only aliases when needed

### `scripts/test_sleeper_api.ps1`

Validates the Sleeper data layer before rendering.

The script prints:

* League name
* League ID
* Season
* NFL state
* Team count
* Standings data
* Configured team lookup result
* Weekly matchup availability

### `scripts/render_once.ps1`

Renders one standings page locally for visual inspection.

Example:

```powershell
.\scripts\render_once.ps1 -Page 1
```

### `scripts/run_live.ps1`

Runs the physical Tidbyt controller loop.

The script:

1. Renders standings Page 1
2. Reads the page-specific transition timing reported by Starlark
3. Pushes Page 1 to the Tidbyt
4. Waits for the marquee animation and final hold to complete
5. Repeats the process for Page 2
6. Continues cycling until stopped

## Requirements

### Software

* Windows PowerShell
* [Pixlet](https://github.com/tidbyt/pixlet)
* A Tidbyt device
* A Sleeper fantasy football league

### Required Configuration Values

Create a local file:

```text
config/settings.ps1
```

Use `config/settings.example.ps1` as the template.

Required values:

```powershell
$SleeperLeagueId = "YOUR_SLEEPER_LEAGUE_ID"
$MyTeamName = "YOUR_FANTASY_TEAM_NAME"

# Leave blank for normal rotation.
$FeaturedTeam = ""

# Leave blank to use the current NFL week automatically.
# A historical override will be useful during scoreboard testing.
$HistoricalWeekOverride = ""

$TidbytDeviceId = "YOUR_TIDBYT_DEVICE_ID"
$TidbytApiToken = "YOUR_TIDBYT_API_TOKEN"
$InstallationId = "sleeperff"

# Wait before retrying after a failed render or push.
$RetrySeconds = 5
```

The installation ID must be alphanumeric only:

```text
Valid:   sleeperff
Invalid: sleeper-ff
```

## Security

The local settings file is intentionally excluded from Git tracking:

```gitignore
config/settings.ps1
```

Do not commit your Tidbyt API token.

The safe template file:

```text
config/settings.example.ps1
```

should contain placeholders only.

Generated WebP files are also excluded from Git tracking:

```gitignore
*.webp
```

## Running the App

### Validate Sleeper API Data

```powershell
.\scripts\test_sleeper_api.ps1
```

### Render a Single Page Locally

```powershell
.\scripts\render_once.ps1 -Page 1
```

or:

```powershell
.\scripts\render_once.ps1 -Page 2
```

### Preview Through Localhost

```powershell
pixlet serve .\app\sleeper_ff.star
```

Then open:

```text
http://localhost:8080/?league_id=YOUR_SLEEPER_LEAGUE_ID&standings_page=1
```

### Push the Live Rotation to a Tidbyt

```powershell
.\scripts\run_live.ps1
```

Stop the loop with:

```text
Ctrl + C
```

## Development Status

### Completed

* Separate season-long project repository
* Sleeper API validation
* Fantasy-team lookup
* Unicode apostrophe normalization
* Two-page live standings display
* Deterministic sorting
* Tidbyt-compatible marquee scrolling
* Dynamic page-transition timing
* Physical Tidbyt API pushes
* Display-only alias support for oversized team names

### Next Steps

1. Add matchup data retrieval
2. Group weekly opponents by `matchup_id`
3. Build a single-matchup Tidbyt render
4. Add team avatars
5. Add full matchup rotation
6. Add featured-team filtering
7. Add historical-week testing
8. Add live score refresh behavior
9. Evaluate projected-score support
10. Evaluate touchdown-alert data sources

## Notes

This project is intentionally being developed in layers.

The current standings display is stable on a physical Tidbyt. Matchup scoreboards will be added next before work begins on secondary enhancements such as touchdown alerts.
