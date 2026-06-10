"""
Sleeper Fantasy Football Tidbyt screen-queue controller.

Current scope:
- Reproduce the existing two-page standings rotation.
- Use a normal round-robin queue for recurring screens.
- Create a priority-queue foundation for future scoring alerts.

Future scope:
- Weekly matchup screens
- Featured-team filtering
- Sleeper score-delta alerts
- External touchdown-event enrichment
"""

from __future__ import annotations

import heapq
import itertools
import os
import re
import subprocess
import sys
import time
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Deque, Dict, List, Optional, Tuple


# ============================================================
# FILE PATHS
# ========
REPO_ROOT = Path(__file__).resolve().parents[1]
STAR_FILE = REPO_ROOT / "app" / "sleeper_ff.star"
WEBP_FILE = REPO_ROOT / "app" / "sleeper_ff.webp"

PAGE_SWITCH_PATTERN = re.compile(r"PAGE_SWITCH_AFTER_MS=(\d+)")


# ============================================================
# SCREEN JOB MODEL
# ============================================================

@dataclass(frozen=True)
class ScreenJob:
    """One screen that can be rendered and pushed to the Tidbyt."""

    screen_type: str
    label: str
    render_args: Dict[str, str] = field(default_factory=dict)
    priority: int = 0
    recurring: bool = True
    duration_ms: Optional[int] = None


# ============================================================
# SCREEN SCHEDULER
# ============================================================

class ScreenScheduler:
    """Maintain a normal round-robin queue and a priority alert queue."""

    def __init__(self) -> None:
        self.normal_queue: Deque[ScreenJob] = deque()
        self.priority_queue: List[Tuple[int, int, ScreenJob]] = []
        self._sequence = itertools.count()

    def add_normal(self, job: ScreenJob) -> None:
        self.normal_queue.append(job)

    def add_priority(self, job: ScreenJob) -> None:
        heapq.heappush(
            self.priority_queue,
            (-job.priority, next(self._sequence), job),
        )

    def next_job(self) -> Tuple[ScreenJob, bool]:
        if self.priority_queue:
            _, _, job = heapq.heappop(self.priority_queue)
            return job, True

        if not self.normal_queue:
            raise RuntimeError("No screens are available in the display queue.")

        return self.normal_queue.popleft(), False

    def complete_job(self, job: ScreenJob, came_from_priority_queue: bool) -> None:
        if job.recurring and not came_from_priority_queue:
            self.normal_queue.append(job)

    def retry_job(self, job: ScreenJob, came_from_priority_queue: bool) -> None:
        if came_from_priority_queue:
            self.add_priority(job)
        else:
            self.normal_queue.appendleft(job)


# ============================================================
# SETTINGS
# ============================================================

def require_environment_value(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def parse_bool(value: Optional[str], default: bool) -> bool:
    if value is None or not value.strip():
        return default

    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on", "$true"}:
        return True
    if normalized in {"0", "false", "no", "off", "$false"}:
        return False

    raise ValueError(f"Invalid boolean value: {value}")


def load_settings() -> Dict[str, object]:
    installation_id = require_environment_value("INSTALLATION_ID")

    if not re.fullmatch(r"[a-zA-Z0-9]+", installation_id):
        raise ValueError(
            "INSTALLATION_ID must contain only letters and numbers. "
            "Example: sleeperff"
        )

    retry_seconds_text = os.environ.get("RETRY_SECONDS", "5").strip() or "5"

    return {
        "league_id": require_environment_value("SLEEPER_LEAGUE_ID"),
        "my_team_name": os.environ.get("MY_TEAM_NAME", "").strip(),
        "featured_team": os.environ.get("FEATURED_TEAM", "").strip(),
        "historical_week_override": os.environ.get("HISTORICAL_WEEK_OVERRIDE", "").strip(),
        "device_id": require_environment_value("TIDBYT_DEVICE_ID"),
        "api_token": require_environment_value("TIDBYT_API_TOKEN"),
        "installation_id": installation_id,
        "show_standings": parse_bool(os.environ.get("SHOW_STANDINGS"), default=True),
        "retry_seconds": max(1, int(retry_seconds_text)),
    }


# ============================================================
# PIXLET COMMANDS
# ============================================================

def run_command(command: List[str], environment: Dict[str, str]) -> Tuple[int, str]:
    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )

    output = completed.stdout or ""
    if output:
        print(output.rstrip())

    return completed.returncode, output


def render_screen(
    job: ScreenJob,
    settings: Dict[str, object],
    environment: Dict[str, str],
) -> int:
    command = [
        "pixlet",
        "render",
        str(STAR_FILE),
        f"league_id={settings['league_id']}",
    ]

    for key, value in job.render_args.items():
        command.append(f"{key}={value}")

    exit_code, output = run_command(command, environment)

    if exit_code != 0:
        raise RuntimeError(f"Pixlet render failed for {job.label}.")

    if not WEBP_FILE.exists():
        raise RuntimeError(f"Pixlet render completed, but {WEBP_FILE} was not found.")

    if job.duration_ms is not None:
        return job.duration_ms

    match = PAGE_SWITCH_PATTERN.search(output)
    if not match:
        raise RuntimeError("Could not find PAGE_SWITCH_AFTER_MS in Pixlet output.")

    return int(match.group(1))


def push_screen(
    job: ScreenJob,
    settings: Dict[str, object],
    environment: Dict[str, str],
) -> None:
    command = [
        "pixlet",
        "push",
        "--installation-id",
        str(settings["installation_id"]),
        str(settings["device_id"]),
        str(WEBP_FILE),
    ]

    exit_code, _ = run_command(command, environment)
    if exit_code != 0:
        raise RuntimeError(f"Pixlet push failed for {job.label}.")


# ============================================================
# QUEUE CONSTRUCTION
# ============================================================

def build_scheduler(settings: Dict[str, object]) -> ScreenScheduler:
    scheduler = ScreenScheduler()

    if settings["show_standings"]:
        scheduler.add_normal(
            ScreenJob(
                screen_type="standings",
                label="Standings page 1",
                render_args={"standings_page": "1"},
            )
        )
        scheduler.add_normal(
            ScreenJob(
                screen_type="standings",
                label="Standings page 2",
                render_args={"standings_page": "2"},
            )
        )

    if not scheduler.normal_queue:
        raise RuntimeError(
            "No normal screens were configured. "
            "ShowStandings is false, and matchup screens have not been added yet."
        )

    return scheduler


# ============================================================
# MAIN LOOP
# ============================================================

def main() -> int:
    try:
        settings = load_settings()
        scheduler = build_scheduler(settings)
    except (ValueError, RuntimeError) as error:
        print(f"Configuration error: {error}", file=sys.stderr)
        return 1

    environment = os.environ.copy()
    environment["TIDBYT_API_TOKEN"] = str(settings["api_token"])

    print()
    print("=== Sleeper FF Tidbyt Python Screen Queue ===")
    print(f"League ID:             {settings['league_id']}")
    print(f"Device ID:             {settings['device_id']}")
    print(f"Installation ID:       {settings['installation_id']}")
    print(f"Show standings:        {settings['show_standings']}")
    print(f"Featured team:         {settings['featured_team'] or '(cycle all matchups)'}")
    print()
    print("Normal queue:")
    for job in scheduler.normal_queue:
        print(f"  - {job.label}")
    print()
    print("Priority queue foundation: ready")
    print("Press Ctrl + C to stop.")
    print()

    while True:
        job, came_from_priority_queue = scheduler.next_job()
        timestamp = time.strftime("%H:%M:%S")

        try:
            print(f"[{timestamp}] Rendering {job.label}...")
            duration_ms = render_screen(job, settings, environment)

            print(f"[{timestamp}] Render succeeded. Pushing {job.label}...")
            push_screen(job, settings, environment)

            duration_seconds = duration_ms / 1000
            print(
                f"[{timestamp}] Push succeeded. "
                f"Displaying for approximately {duration_seconds:.1f} seconds."
            )
            print()

            time.sleep(duration_seconds)
            scheduler.complete_job(job, came_from_priority_queue)

        except KeyboardInterrupt:
            raise

        except Exception as error:
            print(f"[{timestamp}] Error: {error}", file=sys.stderr)
            print(
                f"[{timestamp}] Retrying in {settings['retry_seconds']} seconds.",
                file=sys.stderr,
            )
            print()

            scheduler.retry_job(job, came_from_priority_queue)
            time.sleep(int(settings["retry_seconds"]))


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print()
        print("Stopped.")
