import json
import socket
import sys
import time
import urllib.request


BASE_URL = "https://api.sleeper.app/v1"

MATCHUP_DISPLAY_NAME_MAX_CHARS = 12

MATCHUP_NAME_ALIASES = {
    "The Grand Experiment": "Grand",
    "Buster Don'Tavian Vick": "Buster",
    "Sunnyvale 69ers": "Sunny",
    "Monty's Wedding Crashers": "Monty",
    "Gary's Goobers": "Goobers",
    "Ayahuasca Dream Team": "Ayahuas",
}

def get_json(path: str):
    """
    Request JSON data from the Sleeper API.

    Retry temporary timeouts before giving up.
    """
    url = f"{BASE_URL}/{path}"

    for attempt in range(1, 4):
        print(f"GET {url} (attempt {attempt}/3)")

        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                return json.load(response)

        except socket.timeout:
            if attempt == 3:
                raise

            print("Request timed out. Retrying in 2 seconds...")
            time.sleep(2)

def normalize_team_name(team_name):
    """
    Replace typographic apostrophes with standard keyboard apostrophes.
    """
    if not team_name:
        return team_name

    return (
        team_name
        .replace("‘", "'")
        .replace("’", "'")
    )

def get_matchup_display_name(team_name):
    """
    Create a stable abbreviated team name for compact matchup screens.

    Manual aliases take priority. Otherwise, names longer than the
    configured limit are shortened with three periods.
    """
    normalized_name = normalize_team_name(team_name)

    if not normalized_name:
        return "Unknown"

    manual_alias = MATCHUP_NAME_ALIASES.get(normalized_name)

    if manual_alias:
        return manual_alias

    if len(normalized_name) <= MATCHUP_DISPLAY_NAME_MAX_CHARS:
        return normalized_name

    visible_characters = MATCHUP_DISPLAY_NAME_MAX_CHARS - 3

    return (
        normalized_name[:visible_characters].rstrip()
        + "..."
    )

def get_scoreboard_data(
    matchup_id,
    matchup_pair,
    roster_display_by_id,
    week,
):
    """
    Convert one grouped matchup pair into a display-ready scoreboard.
    """
    if len(matchup_pair) != 2:
        raise ValueError(
            f"Matchup {matchup_id} must contain exactly two teams."
        )

    ordered_pair = sorted(
        matchup_pair,
        key=lambda team_record: team_record.get("roster_id"),
    )

    return {
        "matchup_id": matchup_id,
        "week": week,
        "left_team": get_matchup_team_data(
            ordered_pair[0],
            roster_display_by_id,
        ),
        "right_team": get_matchup_team_data(
            ordered_pair[1],
            roster_display_by_id,
        ),
    }

def get_roster_display_data(roster, users_by_id):
    """
    Convert one Sleeper roster into display-ready team information.
    """
    roster_id = roster.get("roster_id")
    owner_id = roster.get("owner_id")
    matching_user = users_by_id.get(owner_id)

    if not matching_user:
        fallback_name = f"Roster {roster_id}"

        return {
            "roster_id": roster_id,
            "team_name": fallback_name,
            "matchup_display_name": get_matchup_display_name(
                fallback_name
            ),
            "avatar_id": None,
            "avatar_url": None,
        }

    metadata = matching_user.get("metadata") or {}

    team_name = normalize_team_name(
        metadata.get("team_name")
        or matching_user.get("display_name")
        or f"Roster {roster_id}"
    )

    avatar_id = matching_user.get("avatar")

    if avatar_id:
        avatar_url = (
            "https://sleepercdn.com/avatars/thumbs/"
            f"{avatar_id}"
        )
    else:
        avatar_url = None

    return {
        "roster_id": roster_id,
        "team_name": team_name,
        "matchup_display_name": get_matchup_display_name(
            team_name
        ),
        "avatar_id": avatar_id,
        "avatar_url": avatar_url,
    }

def get_matchup_team_data(team_record, roster_display_by_id):
    """
    Combine one weekly matchup record with its display-ready roster data.
    """
    roster_id = team_record.get("roster_id")

    roster_display = roster_display_by_id.get(roster_id) or {}

    return {
        "roster_id": roster_id,
        "team_name": roster_display.get(
            "team_name",
            f"Roster {roster_id}",
        ),
        "matchup_display_name": roster_display.get(
            "matchup_display_name",
            f"Roster {roster_id}",
        ),
        "avatar_id": roster_display.get("avatar_id"),
        "avatar_url": roster_display.get("avatar_url"),
        "points": team_record.get("points") or 0,
    }

# ============================================================
# COMMAND-LINE ARGUMENTS
# ============================================================

if len(sys.argv) < 3:
    raise SystemExit(
        "Usage: python .\\controller\\test_matchups.py "
        "<current_league_id> <historical_week>"
    )

league_id = sys.argv[1]

try:
    historical_week = int(sys.argv[2])
except ValueError:
    raise SystemExit("historical_week must be a whole number.")


# ============================================================
# NFL AND LEAGUE DATA
# ============================================================

nfl_state = get_json("state/nfl")

print()
print("NFL state response:")
print(nfl_state)

league = get_json(f"league/{league_id}")

print()
print("Current league summary:")
print(f"  Name:               {league.get('name')}")
print(f"  League ID:          {league.get('league_id')}")
print(f"  Season:             {league.get('season')}")
print(f"  Status:             {league.get('status')}")
print(f"  Total rosters:      {league.get('total_rosters')}")
print(f"  Previous league ID: {league.get('previous_league_id')}")

previous_league_id = league.get("previous_league_id")

if not previous_league_id:
    raise SystemExit(
        "The current league does not include a previous_league_id."
    )

previous_league = get_json(
    f"league/{previous_league_id}"
)

print()
print("Previous league summary:")
print(f"  Name:          {previous_league.get('name')}")
print(f"  League ID:     {previous_league.get('league_id')}")
print(f"  Season:        {previous_league.get('season')}")
print(f"  Status:        {previous_league.get('status')}")
print(f"  Total rosters: {previous_league.get('total_rosters')}")


# ============================================================
# USER AND ROSTER LOOKUPS
# ============================================================

users = get_json(
    f"league/{previous_league_id}/users"
)

rosters = get_json(
    f"league/{previous_league_id}/rosters"
)

print()
print("Historical league identity data:")
print(f"  Users returned:   {len(users)}")
print(f"  Rosters returned: {len(rosters)}")

users_by_id = {}

for user in users:
    user_id = user.get("user_id")

    if user_id:
        users_by_id[user_id] = user

roster_display_by_id = {}

for roster in rosters:
    roster_display = get_roster_display_data(
        roster,
        users_by_id,
    )

    roster_id = roster_display.get("roster_id")

    roster_display_by_id[roster_id] = roster_display

print()
print("Roster display lookup:")

for roster_id in sorted(roster_display_by_id):
    roster_display = roster_display_by_id[roster_id]

    print(
        f"  roster_id={roster_id} "
        f"team_name={roster_display.get('team_name')} "
        f"matchup_display_name={roster_display.get('matchup_display_name')} "
        f"avatar_id={roster_display.get('avatar_id')}"
    )


# ============================================================
# HISTORICAL MATCHUP DATA
# ============================================================

matchups = get_json(
    f"league/{previous_league_id}/matchups/{historical_week}"
)

print()
print("Historical matchup response:")
print(f"  Week:         {historical_week}")
print(f"  Team records: {len(matchups)}")

if not matchups:
    raise SystemExit(
        "No matchup records were returned for the selected week."
    )

print()
print("Compact matchup records:")

for matchup in matchups:
    print(
        f"  matchup_id={matchup.get('matchup_id')} "
        f"roster_id={matchup.get('roster_id')} "
        f"points={matchup.get('points')}"
    )


# ============================================================
# GROUP MATCHUP RECORDS
# ============================================================

grouped_matchups = {}

for matchup in matchups:
    matchup_id = matchup.get("matchup_id")

    if matchup_id not in grouped_matchups:
        grouped_matchups[matchup_id] = []

    grouped_matchups[matchup_id].append(matchup)

print()
print("Readable grouped matchup pairs:")

for matchup_id in sorted(grouped_matchups):
    matchup_pair = grouped_matchups[matchup_id]

    print()
    print(f"  Matchup {matchup_id}:")

    for team_record in matchup_pair:
        roster_id = team_record.get("roster_id")
        roster_display = roster_display_by_id.get(roster_id) or {}

        team_name = roster_display.get(
            "team_name",
            f"Roster {roster_id}",
        )

        print(
            f"    {team_name}: "
            f"{team_record.get('points')}"
        )

print()
print("Matchup display-name preview:")

for roster_id in sorted(roster_display_by_id):
    roster_display = roster_display_by_id[roster_id]
    full_name = roster_display.get("team_name")

    short_name = get_matchup_display_name(
        full_name
    )

    print(
        f"  {full_name} "
        f"-> "
        f"{short_name}"
    )

print()
print("First normalized matchup team:")

first_matchup_team = get_matchup_team_data(
    matchups[0],
    roster_display_by_id,
)

print(first_matchup_team)

print()
print("First normalized scoreboard:")

first_matchup_id = sorted(grouped_matchups)[0]

first_scoreboard = get_scoreboard_data(
    first_matchup_id,
    grouped_matchups[first_matchup_id],
    roster_display_by_id,
    historical_week,
)

print(first_scoreboard)

scoreboards = []

for matchup_id in sorted(grouped_matchups):
    scoreboard = get_scoreboard_data(
        matchup_id,
        grouped_matchups[matchup_id],
        roster_display_by_id,
        historical_week,
    )

    scoreboards.append(scoreboard)

print()
print("Normalized scoreboard list:")

for scoreboard in scoreboards:
    left_team = scoreboard.get("left_team")
    right_team = scoreboard.get("right_team")

    print(
        f"  Matchup {scoreboard.get('matchup_id')}: "
        f"{left_team.get('matchup_display_name')} "
        f"{left_team.get('points')} "
        f"vs "
        f"{right_team.get('points')} "
        f"{right_team.get('matchup_display_name')}"
    )