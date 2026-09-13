"""Unit test for the gaps-and-islands trip reconstruction model.

Run from the repository root (the test reads the compiled SQL):

    uv run --with duckdb python tests/test_trip_reconstruction.py

Synthetic scenario (polls every 60 s):
    rider    : 3 polls stationary at A, 4 polls riding ~100 m/poll east,
               3 polls stationary at B        -> ONE trip (~400 m, ~4 min)
    parked   : stationary the whole time       -> excluded
    jitter   : wobbles ~3 m around one spot    -> excluded (GPS noise)
    drifter  : single 40 m shift, then stops   -> excluded (< 50 m net)
    disabled : 500 m move while is_disabled    -> excluded
"""

import math
import pathlib
import tempfile

import duckdb

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMPILED = ROOT / "dbt-project" / "target" / "compiled" / "krakow_micromobility" / "models" / "02_silver" / "fct_vehicle_trips.sql"


def synthetic_rows():
    rows = []

    def add(vid, poll, lat, lon, disabled=False, reserved=False):
        rows.append((vid, 1789300000 + poll * 60, lat, lon, disabled, reserved))

    lat0, lon0 = 50.0614, 19.9366

    def move(lat, lon, dy_m, dx_m):
        return (lat + dy_m / 111_320.0,
                lon + dx_m / (111_320.0 * math.cos(math.radians(lat))))

    for p in range(1, 4):
        add("rider", p, lat0, lon0)
    for p in range(4, 8):
        lat0, lon0 = move(lat0, lon0, 0, 100)
        add("rider", p, lat0, lon0)
    for p in range(8, 11):
        add("rider", p, lat0, lon0)

    for p in range(1, 11):
        add("parked", p, 50.0500, 19.9200)
        la, lo = move(50.0500, 19.9200, 3 * ((p % 2) * 2 - 1), 0)
        add("jitter", p, la, lo)

    add("drifter", 1, 50.0400, 19.9100)
    la, lo = move(50.0400, 19.9100, 0, 40)
    for p in range(2, 11):
        add("drifter", p, la, lo)

    add("disabled_bike", 1, 50.0300, 19.9000)
    la, lo = move(50.0300, 19.9000, 0, 500)
    add("disabled_bike", 2, la, lo, disabled=True)

    return rows


def main() -> None:
    sql = COMPILED.read_text().replace(
        '"krakow"."main_silver"."fct_vehicle_snapshots"',
        "main_silver.fct_vehicle_snapshots",
    )

    with tempfile.TemporaryDirectory() as tmp:
        con = duckdb.connect(f"{tmp}/test.duckdb")
        con.execute("create schema main_silver")
        con.execute(
            "create table main_silver.fct_vehicle_snapshots ("
            "vehicle_id varchar, measured_at timestamp, lat double, lon double,"
            " is_disabled boolean, is_reserved boolean)"
        )
        con.executemany(
            "insert into main_silver.fct_vehicle_snapshots values"
            " (?, epoch_ms(?::bigint)::timestamp, ?, ?, ?, ?)",
            [(v, t * 1000, la, lo, d, r) for v, t, la, lo, d, r in synthetic_rows()],
        )
        trips = con.execute(sql).fetchall()

    print(f"reconstructed trips: {len(trips)}")
    for t in trips:
        print(t)

    rider = [t for t in trips if t[0] == "rider"]
    assert len(trips) == 1, f"expected exactly 1 trip, got {len(trips)}"
    assert 380 < rider[0][8] < 420, f"distance {rider[0][8]:.0f} m not ~400 m"
    assert 3 <= rider[0][7] <= 5, f"duration {rider[0][7]} min not ~4 min"
    print("ALL ASSERTIONS PASSED: 1 trip, ~400 m, ~4 min;"
          " parked/jitter/drifter/disabled correctly excluded")


if __name__ == "__main__":
    main()
