load("render.star", "render")
load("http.star", "http")

# ============================================================
# DEFAULT CONFIGURATION
# ============================================================

DEFAULT_LEAGUE_ID = "1312098665363419136"
TEAMS_PER_PAGE = 4
FRAME_DELAY_MS = 100

# Keep the returned names stationary before changing pages.
PAGE_HOLD_FRAMES = 20

# Begin pushing the next page shortly after the hold begins.
# This leaves room for normal API and device latency.
SWITCH_BUFFER_FRAMES = 20

STANDINGS_NAME_ALIASES = {
    "Monty's Wedding Crashers": "Monty's Crashers",
}

# ============================================================
# HTTP HELPERS
# ============================================================

def get_json(url):
    """
    Fetch JSON data from Sleeper.
    Stop execution and show the failing URL if the request fails.
    """
    response = http.get(url)

    if response.status_code != 200:
        fail(
            "Sleeper request failed: HTTP %d URL: %s" %
            (response.status_code, url)
        )

    return response.json()


# ============================================================
# TEAM AND STANDINGS HELPERS
# ============================================================

def find_user(users, user_id):
    """
    Find the Sleeper league user associated with a roster owner.
    """
    for user in users:
        if str(user["user_id"]) == str(user_id):
            return user

    return None


def clean_team_name(team_name):
    """
    Convert typographic apostrophes into ordinary apostrophes while
    preserving the original capitalization from Sleeper.
    """
    if not team_name:
        return "Unknown Team"

    return (
        team_name
            .replace("‘", "'")
            .replace("’", "'")
    )


def get_team_name(roster, users):
    """
    Prefer the league-specific fantasy team name.

    If the manager did not set one, use the Sleeper display name.
    If the roster is unowned, fall back to a roster label.
    """
    owner_id = roster.get("owner_id")

    if not owner_id:
        return "ROSTER %s" % roster["roster_id"]

    user = find_user(users, owner_id)

    if not user:
        return "ROSTER %s" % roster["roster_id"]

    metadata = user.get("metadata") or {}
    team_name = metadata.get("team_name")

    if team_name:
        return clean_team_name(team_name)

    display_name = user.get("display_name")

    if display_name:
        return clean_team_name(display_name)

    return clean_team_name(user.get("username"))


def get_fantasy_points(roster):
    """
    Combine Sleeper's whole-number and decimal fantasy-point fields.

    Example:
    fpts = 123
    fpts_decimal = 45
    result = 123.45
    """
    settings = roster.get("settings") or {}

    whole_points = int(settings.get("fpts") or 0)
    decimal_points = int(settings.get("fpts_decimal") or 0)

    return whole_points + (decimal_points / 100.0)


def standings_sort_key(entry):
    """
    Rank teams by:
    1. Wins, descending
    2. Losses, ascending
    3. Total fantasy points, descending
    4. Team name, alphabetically

    The alphabetical fallback makes the preseason 0-0 standings
    deterministic while every team remains tied.
    """
    return (
        -entry["wins"],
        entry["losses"],
        -entry["points"],
        entry["team_name"],
    )


def build_standings(rosters, users):
    """
    Convert the Sleeper roster response into sorted standings rows.
    """
    standings = []

    for roster in rosters:
        settings = roster.get("settings") or {}

        standings.append({
            "roster_id": int(roster["roster_id"]),
            "team_name": get_team_name(roster, users),
            "wins": int(settings.get("wins") or 0),
            "losses": int(settings.get("losses") or 0),
            "ties": int(settings.get("ties") or 0),
            "points": get_fantasy_points(roster),
        })

    return sorted(
        standings,
        key = standings_sort_key,
    )


def get_record_text(entry):
    """
    Display a normal W-L record unless the team has a tie.
    """
    if entry["ties"] > 0:
        return "%d-%d-%d" % (
            entry["wins"],
            entry["losses"],
            entry["ties"],
        )

    return "%d-%d" % (
        entry["wins"],
        entry["losses"],
    )

def format_matchup_points(points):
    """
    Display fantasy scores with exactly two decimal places.

    Pixlet Starlark does not support Python-style formatting
    such as "%.2f", so build the decimal text manually.
    """
    scaled_points = int(
        (float(points) * 100) + 0.5
    )

    sign = ""

    if scaled_points < 0:
        sign = "-"
        scaled_points = -scaled_points

    whole_points = scaled_points // 100
    decimal_points = scaled_points % 100

    decimal_text = str(decimal_points)

    if decimal_points < 10:
        decimal_text = "0" + decimal_text

    return "%s%d.%s" % (
        sign,
        whole_points,
        decimal_text,
    )

# ============================================================
# VISUAL HELPERS
# ============================================================

def standings_header(page_number, total_pages):
    """
    Render the compact header at the top of the screen.
    """
    return render.Box(
        width = 64,
        height = 6,
        child = render.Row(
            children = [
                render.Box(
                    width = 48,
                    child = render.Text(
                        content = "STANDINGS",
                        font = "CG-pixel-3x5-mono",
                        color = "#00ceb8",
                    ),
                ),

                render.Box(
                    width = 16,
                    child = render.Text(
                        content = "%d/%d" % (
                            page_number,
                            total_pages,
                        ),
                        font = "CG-pixel-3x5-mono",
                        color = "#9a9a9a",
                    ),
                ),
            ],
        ),
    )

def standings_record_widget(entry):
    """
    Render wins and losses separately so the record is readable at a glance.
    """
    children = [
        render.Text(
            content = str(entry["wins"]),
            font = "CG-pixel-3x5-mono",
            color = "#00ceb8",
        ),

        render.Text(
            content = "-",
            font = "CG-pixel-3x5-mono",
            color = "#9a9a9a",
        ),

        render.Text(
            content = str(entry["losses"]),
            font = "CG-pixel-3x5-mono",
            color = "#ff5c5c",
        ),
    ]

    if entry["ties"] > 0:
        children.append(
            render.Text(
                content = "-",
                font = "CG-pixel-3x5-mono",
                color = "#9a9a9a",
            )
        )

        children.append(
            render.Text(
                content = str(entry["ties"]),
                font = "CG-pixel-3x5-mono",
                color = "#f5c451",
            )
        )

    return render.Row(
        children = children,
    )

def get_standings_display_name(team_name):
    """
    Use compact display aliases for team names that are too long
    to complete their marquee animation on the physical Tidbyt.

    The original Sleeper team name remains unchanged internally.
    """
    return STANDINGS_NAME_ALIASES.get(
        team_name,
        team_name,
    )

def standings_row(rank, entry):
    """
    Render one standings row.

    Width allocation:
    1 px   left margin
    8 px   ranking
    1 px   gap
    39 px  scrolling team name
    15 px  record
    ----------------
    64 px  total
    """
    return render.Box(
        width = 64,
        height = 6,
        child = render.Row(
            children = [
                # Explicit left margin.
                render.Box(width = 1),

                # Ranking.
                render.Box(
                    width = 8,
                    child = render.Text(
                        content = "%d." % rank,
                        font = "CG-pixel-3x5-mono",
                        color = "#9a9a9a",
                    ),
                ),

                # Gap between ranking and team name.
                render.Box(width = 1),

                # Compact team name with a longer pause before scrolling.
                render.Box(
                    width = 39,
                    height = 6,
                    child = render.Marquee(
                        width = 39,
                        align = "start",
                        delay = 20,
                        child = render.Text(
                            content = get_standings_display_name(
                                entry["team_name"],
                            ),
                            font = "CG-pixel-3x5-mono",
                            color = "#ffffff",
                        ),
                    ),
                ),

                # Fixed record area.
                render.Box(
                    width = 15,
                    child = standings_record_widget(entry),
                ),
            ],
        ),
    )

def render_matchup_page(
    left_name,
    left_points,
    right_name,
    right_points,
    week,
):
    """
    Render one static fantasy matchup screen.

    This first version intentionally excludes avatars.
    We are validating the text layout before adding images.
    """
    left_score_value = float(left_points)
    right_score_value = float(right_points)

    left_score_color = "#ffffff"
    right_score_color = "#ffffff"

    if left_score_value > right_score_value:
        left_score_color = ""#7CFC00""
        right_score_color = "#ff5c5c"
        
    elif right_score_value > left_score_value:
        left_score_color = "#ff5c5c"
        right_score_color = "#7CFC00"
    
    return render.Column(
        children = [
            render.Box(
                width = 64,
                height = 6,
                child = render.Text(
                    content = "MATCHUP  WEEK %s" % week,
                    font = "CG-pixel-3x5-mono",
                    color = "#00ceb8",
                ),
            ),

            render.Box(height = 2),

            render.Row(
                children = [
                    render.Box(
                        width = 64,
                        height = 6,
                        child = render.Row(
                            children = [
                                render.Box(
                                    width = 29,
                                    height = 6,
                                    child = render.Text(
                                        content = left_name,
                                        font = "CG-pixel-3x5-mono",
                                        color = "#ffffff",
                                    ),
                                ),

                                render.Box(width = 6),

                                render.Box(
                                    width = 29,
                                    height = 6,
                                    child = render.Text(
                                        content = right_name,
                                        font = "CG-pixel-3x5-mono",
                                        color = "#ffffff",
                                    ),
                                ),
                            ],
                        ),
                    ),
                ],
            ),

            render.Box(height = 2),

            render.Row(
                children = [
                    render.Box(
                        width = 64,
                        height = 6,
                        child = render.Row(
                            children = [
                                render.Box(
                                    width = 27,
                                    height = 6,
                                    child = render.Text(
                                        content = format_matchup_points(
                                            left_points,
                                        ),
                                        font = "CG-pixel-3x5-mono",
                                        color = left_score_color,
                                    ),
                                ),

                                render.Box(
                                    width = 10,
                                    height = 6,
                                    child = render.Text(
                                        content = "VS",
                                        font = "CG-pixel-3x5-mono",
                                        color = "#ffffff",
                                    ),
                                ),

                                render.Box(
                                    width = 27,
                                    height = 6,
                                    child = render.Text(
                                        content = format_matchup_points(
                                            right_points,
                                        ),
                                        font = "CG-pixel-3x5-mono",
                                        color = right_score_color,
                                    ),
                                ),
                            ],
                        ),
                    ),
                ],
            ),
        ],
    )

def render_standings_page(standings, page_number):
    """
    Render four ranked teams on one reusable standings page.
    """
    total_pages = (
        len(standings) + TEAMS_PER_PAGE - 1
    ) // TEAMS_PER_PAGE

    if total_pages < 1:
        total_pages = 1

    if page_number < 1 or page_number > total_pages:
        page_number = 1

    start_index = (
        page_number - 1
    ) * TEAMS_PER_PAGE

    end_index = start_index + TEAMS_PER_PAGE

    visible_standings = standings[
        start_index:end_index
    ]

    rows = [
        standings_header(
            page_number,
            total_pages,
        ),
    ]

    for index in range(len(visible_standings)):
        rows.append(
            standings_row(
                start_index + index + 1,
                visible_standings[index],
            )
        )

    return render.Column(
        children = rows,
    )

def render_single_standings_page(standings, page_number):
    """
    Render one standings page for direct API pushing.

    Print the recommended controller switch time so PowerShell
    can push the next page after the names return to their initial
    positions but before a second scroll cycle begins.
    """
    page = render_standings_page(
        standings,
        page_number,
    )

    page_with_hold = add_hold_after(
        page,
        PAGE_HOLD_FRAMES,
    )

    switch_after_frames = (
        page.frame_count() +
        SWITCH_BUFFER_FRAMES
    )

    switch_after_ms = (
        switch_after_frames *
        FRAME_DELAY_MS
    )

    print(
        "PAGE_SWITCH_AFTER_MS=%d" %
        switch_after_ms
    )

    return render.Root(
        delay = FRAME_DELAY_MS,
        child = page_with_hold,
    )

def add_hold_after(widget, hold_frames):
    """
    Extend a widget's animation by holding its final frame.

    The transparent animation controls the total frame count.
    The visible standings page remains on its final frame during
    the additional hold period.
    """
    transparent_frames = []

    for _ in range(
        widget.frame_count() + hold_frames
    ):
        transparent_frames.append(
            render.Box(
                width = 1,
                height = 1,
            )
        )

    return render.Stack(
        children = [
            widget,

            render.Animation(
                children = transparent_frames,
            ),
        ],
    )

def render_standings_rotation(standings):
    """
    Render both standings pages as one animated Tidbyt installation.

    Each page scrolls normally, returns to its initial position,
    remains readable for an additional 20 frames, and then switches.
    """
    page_one = render_standings_page(
        standings,
        1,
    )

    page_two = render_standings_page(
        standings,
        2,
    )

    return render.Root(
        delay = 100,
        show_full_animation = True,
        child = render.Sequence(
            children = [
                add_hold_after(
                    page_one,
                    PAGE_HOLD_FRAMES,
                ),

                add_hold_after(
                    page_two,
                    PAGE_HOLD_FRAMES,
                ),
            ],
        ),
    )

def main(config):
    league_id = config.get(
        "league_id",
        DEFAULT_LEAGUE_ID,
    )

    requested_screen = config.get(
    "screen",
    "standings",
    )   

    print("Requested screen:", requested_screen)

    requested_page = config.get(
        "standings_page",
        "",
    )

    if requested_page:
        standings_page = int(requested_page)
    else:
        standings_page = 0

    if requested_screen == "matchup":
        return render.Root(
            delay = FRAME_DELAY_MS,
            child = render_matchup_page(
                config.get("left_name", "LEFT"),
                config.get("left_points", "0"),
                config.get("right_name", "RIGHT"),
                config.get("right_points", "0"),
                config.get("week", "0"),
            ),
        )

    print("League ID:", league_id)

    if standings_page > 0:
        print("Requested standings page:", standings_page)
    else:
        print("Requested standings display: rotating pages")

    users = get_json(
        "https://api.sleeper.app/v1/league/%s/users" %
        league_id
    )

    rosters = get_json(
        "https://api.sleeper.app/v1/league/%s/rosters" %
        league_id
    )

    standings = build_standings(
        rosters,
        users,
    )

    print("Returned roster count:", len(standings))

    for index in range(len(standings)):
        entry = standings[index]

        print(
            "%d. %s %s %s" % (
                index + 1,
                entry["team_name"],
                get_record_text(entry),
                str(entry["points"]),
            )
        )

    if standings_page > 0:
        return render_single_standings_page(
            standings,
            standings_page,
        )

    return render_standings_rotation(
        standings,
    )