"""Poll the Dott Kraków GBFS feed and store raw JSON snapshots.

Dynamic feeds (station_status, free_bike_status) are saved per poll with a
timestamped filename so the dbt Bronze layer can reconstruct the timeline.
Static feeds (station_information, vehicle_types, system_pricing_plans,
geofencing_zones) are refreshed once per day.

Usage:
    python ingestion/fetch_gbfs.py                 # one poll
    python ingestion/fetch_gbfs.py --loop 60      # poll every 60 s
"""

from __future__ import annotations

import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

BASE = "https://gbfs.api.ridedott.com/public/v2/krakow"
RAW = Path(__file__).resolve().parent.parent / "dbt-project" / "data" / "raw" / "gbfs"

DYNAMIC = ["station_status", "free_bike_status"]
STATIC = ["station_information", "vehicle_types", "system_pricing_plans", "geofencing_zones"]


def fetch(name: str) -> dict:
    response = requests.get(f"{BASE}/{name}.json", timeout=30)
    response.raise_for_status()
    return response.json()


def save(name: str, payload: dict, fetched_at: datetime, static: bool) -> Path:
    if static:
        day_dir = RAW / "static" / fetched_at.strftime("%Y-%m-%d")
    else:
        day_dir = RAW / name / fetched_at.strftime("%Y-%m-%d")
    day_dir.mkdir(parents=True, exist_ok=True)
    path = day_dir / f"{name}_{fetched_at.strftime('%Y%m%dT%H%M%S')}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return path


def poll() -> None:
    now = datetime.now(timezone.utc)
    for name in DYNAMIC + STATIC:
        try:
            payload = fetch(name)
            path = save(name, payload, now, static=name in STATIC)
            print(f"[{now:%H:%M:%S} UTC] {name} -> {path.name}")
        except requests.RequestException as exc:
            print(f"[{now:%H:%M:%S} UTC] {name} FAILED: {exc}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Poll Dott Kraków GBFS feeds")
    parser.add_argument("--loop", type=int, default=0, metavar="SECONDS",
                        help="poll continuously every SECONDS instead of once")
    args = parser.parse_args()

    while True:
        poll()
        if args.loop <= 0:
            break
        time.sleep(args.loop)


if __name__ == "__main__":
    main()
