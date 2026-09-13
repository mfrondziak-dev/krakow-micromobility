{{
    config(location='data/bronze/bronze_vehicle_status')
}}

-- Flatten GBFS free_bike_status snapshots: one row per vehicle per poll.
-- Source structure: data.bikes[] -> {bike_id, lat, lon, current_range_meters,
-- current_fuel_percent, is_disabled, is_reserved, pricing_plan_id,
-- vehicle_type_id, last_reported}

with source as (

    select
        unnest(data.bikes) as bike,
        filename
    from read_json_auto(
        'data/raw/gbfs/free_bike_status/**/*.json',
        filename = true,
        union_by_name = true
    )

)

select
    bike.bike_id as vehicle_id,
    bike.vehicle_type_id,
    bike.pricing_plan_id,
    bike.lat,
    bike.lon,
    bike.current_range_meters,
    bike.current_fuel_percent,
    bike.is_disabled,
    bike.is_reserved,
    to_timestamp(bike.last_reported) as reported_at_utc,
    cast(to_timestamp(bike.last_reported) at time zone 'Europe/Warsaw' as timestamp)
        as reported_at_local,
    cast(
        date_trunc(
            'day',
            cast(to_timestamp(bike.last_reported) at time zone 'Europe/Warsaw' as timestamp)
        ) as date
    ) as dt
from source
