"""Kraków micromobility exploration dashboard (Dott GBFS pipeline)."""

from pathlib import Path

import folium
import polars as pl
import plotly.express as px
import streamlit as st
from streamlit_folium import st_folium

GOLD = Path(__file__).resolve().parent.parent / "dbt-project" / "data" / "gold"

st.set_page_config(page_title="Kraków Micromobility", layout="wide")
st.title("Kraków shared e-scooters: from GBFS polls to business insights")

try:
    utilization = pl.read_parquet(GOLD / "mart_station_utilization_hourly.parquet")
    fleet = pl.read_parquet(GOLD / "mart_fleet_health_hourly.parquet")
    trips = pl.read_parquet(GOLD / "mart_trips_enriched.parquet")
except FileNotFoundError:
    st.error("Gold marts not found. Run the ingestion loop and `dbt run` first.")
    st.stop()

tab_map, tab_fleet, tab_revenue = st.tabs(["Stations", "Fleet health", "Revenue"])

with tab_map:
    import duckdb

    con = duckdb.connect(
        str(GOLD.parent.parent / "krakow.duckdb"), read_only=True
    )
    stations = con.execute(
        "SELECT station_id, station_name, latitude, longitude FROM silver.dim_stations"
    ).pl()
    con.close()

    latest = (
        utilization.sort("hour")
        .group_by("station_id")
        .last()
        .join(stations, on="station_id", how="inner")
    )
    m = folium.Map(location=[50.0614, 19.9366], zoom_start=12)
    for row in latest.iter_rows(named=True):
        color = "red" if row["avg_bikes_available"] == 0 else "green"
        folium.CircleMarker(
            location=[row["latitude"], row["longitude"]],
            radius=4,
            color=color,
            fill=True,
            tooltip=f"{row['station_name']} — {row['avg_bikes_available']:.1f} vehicles",
        ).add_to(m)
    st_folium(m, width=1100, height=500)

    station_pick = st.selectbox(
        "Station", sorted(stations.get_column("station_name").unique().to_list())
    )
    sid = (
        stations.filter(pl.col("station_name") == station_pick)
        .get_column("station_id")
        .first()
    )
    hourly = utilization.filter(pl.col("station_id") == sid).sort("hour")
    fig = px.line(
        hourly.to_pandas(),
        x="hour",
        y="avg_bikes_available",
        title=f"Average availability — {station_pick}",
    )
    st.plotly_chart(fig, use_container_width=True)

with tab_fleet:
    battery = (
        fleet.group_by("hour")
        .agg(
            (pl.col("avg_battery_pct") * pl.col("observations")).sum()
            / pl.col("observations").sum(),
            (pl.col("low_battery_share") * pl.col("observations")).sum()
            / pl.col("observations").sum(),
        )
        .sort("hour")
    )
    fig = px.line(
        battery.to_pandas(),
        x="hour",
        y=["avg_battery_pct", "low_battery_share"],
        title="Fleet battery health",
    )
    st.plotly_chart(fig, use_container_width=True)

with tab_revenue:
    revenue = (
        trips.with_columns(pl.col("departed_at").dt.hour().alias("hour_of_day"))
        .group_by("hour_of_day")
        .agg(pl.col("fare_pln").sum().alias("revenue_pln"), pl.len().alias("rides"))
        .sort("hour_of_day")
    )
    fig = px.bar(
        revenue.to_pandas(),
        x="hour_of_day",
        y="revenue_pln",
        title="Estimated revenue by hour (operator pricing)",
    )
    st.plotly_chart(fig, use_container_width=True)
