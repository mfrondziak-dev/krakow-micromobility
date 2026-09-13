{{ config(location='data/silver/dim_stations') }}

-- One row per station: static attributes from the latest station_information
-- snapshot, enriched with the latest observed availability.

with station_info as (

    select
        unnest(data.stations) as station,
        filename
    from read_json_auto(
        'data/raw/gbfs/static/*/station_information_*.json',
        filename = true,
        union_by_name = true
    )

),

latest_info as (

    select
        station.station_id,
        station.name as station_name,
        station.lat as latitude,
        station.lon as longitude,
        coalesce(
            list_sum(
                list_transform(
                    map_entries(
                        cast(station.vehicle_capacity as map(varchar, bigint))
                    ),
                    e -> e.value
                )
            ),
            0
        ) as capacity,
        row_number() over (
            partition by station.station_id
            order by regexp_extract(filename, '\d{8}T\d{6}', 0) desc
        ) as rn
    from station_info

)

select
    station_id,
    station_name,
    latitude,
    longitude,
    capacity
from latest_info
where rn = 1
