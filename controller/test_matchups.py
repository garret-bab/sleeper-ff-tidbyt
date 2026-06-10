import json
import socket
import sys
import time
import urllib.request


BASE_URL = "https://api.sleeper.app/v1"


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

nfl_state = get_json("state/nfl")

print()
print("NFL state response:")
print(nfl_state)

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
print("Keys available on the first matchup record:")
print(matchups[0].keys())

print()
print("Compact matchup records:")

for matchup in matchups:
    print(
        f"  matchup_id={matchup.get('matchup_id')} "
        f"roster_id={matchup.get('roster_id')} "
        f"points={matchup.get('points')}"
    )

    grouped_matchups = {}

for matchup in matchups:
    matchup_id = matchup.get("matchup_id")

    if matchup_id not in grouped_matchups:
        grouped_matchups[matchup_id] = []

    grouped_matchups[matchup_id].append(matchup)

print()
print("Grouped matchup pairs:")

for matchup_id in sorted(grouped_matchups):
    matchup_pair = grouped_matchups[matchup_id]

    print()
    print(f"  Matchup {matchup_id}:")

    for team_record in matchup_pair:
        print(
            f"    roster_id={team_record.get('roster_id')} "
            f"points={team_record.get('points')}"
        )