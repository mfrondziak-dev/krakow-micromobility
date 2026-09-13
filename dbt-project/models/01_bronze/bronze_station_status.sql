{{
    config(location='data/bronze/bronze_station_status')
}}

-- Flatten GBFS station_status snapshots: one row per station per poll.
-- Source structure: data.stations[] -> {station_id, is_installed, is_renting,
-- is_returning, num_bikes_available, vehicle_types_available[], last_reported}

with source as (

    select
        unnest(data.stations) as station,
        filename
    from read_json_auto(
        'data/raw/gbfs/station_status/**/*.json',
        filename = true,
        union_by_name = true
    )

)

select
    station.station_id,
    station.is_installed,
    station.is_renting,
    station.is_returning,
    station.num_bikes_available,
    station.vehicle_types_available as vehicle_types_available,
    to_timestamp(station.last_reported) as reported_at_utc,
    cast(to_timestamp(station.last_reported) at time zone 'Europe/Warsaw' as timestamp)
        as reported_at_local,
    cast(
        date_trunc(
            'day',
            cast(to_timestamp(station.last_reported) at time zone 'Europe/Warsaw' as timestamp)
        ) as date
    ) as dt
from source
