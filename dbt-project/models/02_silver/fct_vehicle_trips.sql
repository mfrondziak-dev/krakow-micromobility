-- Reconstructed rides for dockless vehicles.
--
-- Scooters report GPS continuously while riding, so a single ride appears
-- as a chain of small position deltas. A pairwise threshold would filter
-- out genuine ride segments. Instead we use a gaps-and-islands pattern:
-- consecutive observations whose displacement exceeds the GPS-jitter
-- threshold belong to the same trip; a stationary observation starts a
-- new group. Each group with net displacement above the trip threshold
-- AND a physically plausible average speed is one reconstructed ride.
-- The speed filter removes slow GPS-drift chains (vehicles inching around
-- a parking spot) that would otherwise masquerade as very long rides.

{% set jitter_m = 15 %}
{% set min_trip_m = 50 %}
{% set min_speed_kmh = 1.0 %}

with observations as (

    -- same last_reported can appear in several polls; keep one row
    select distinct
        vehicle_id,
        measured_at,
        lat,
        lon,
        is_disabled,
        is_reserved
    from {{ ref('fct_vehicle_snapshots') }}

),

steps as (

    select
        vehicle_id,
        measured_at,
        lat,
        lon,
        is_disabled,
        is_reserved,
        lag(lat) over w as prev_lat,
        lag(lon) over w as prev_lon
    from observations
    window w as (partition by vehicle_id order by measured_at)

),

flags as (

    select
        *,
        case
            when prev_lat is null then 1
            when {{ haversine_m('prev_lat', 'prev_lon', 'lat', 'lon') }} <= {{ jitter_m }} then 1
            else 0
        end as starts_new_group
    from steps

),

groups as (

    select
        *,
        sum(starts_new_group) over (
            partition by vehicle_id order by measured_at
            rows between unbounded preceding and current row
        ) as grp
    from flags

),

grouped as (

    select
        vehicle_id,
        grp,
        min(measured_at) as departed_at,
        max(measured_at) as arrived_at,
        arg_min(lat, measured_at) as start_lat,
        arg_min(lon, measured_at) as start_lon,
        arg_max(lat, measured_at) as end_lat,
        arg_max(lon, measured_at) as end_lon
    from groups
    where not is_disabled
      and not is_reserved
    group by vehicle_id, grp
    having count(*) >= 2

)

select
    vehicle_id,
    start_lat,
    start_lon,
    end_lat,
    end_lon,
    departed_at,
    arrived_at,
    date_diff('minute', departed_at, arrived_at) as duration_min,
    {{ haversine_m('start_lat', 'start_lon', 'end_lat', 'end_lon') }} as distance_m
from grouped
where {{ haversine_m('start_lat', 'start_lon', 'end_lat', 'end_lon') }} > {{ min_trip_m }}
  and date_diff('minute', departed_at, arrived_at) > 0
  and {{ haversine_m('start_lat', 'start_lon', 'end_lat', 'end_lon') }}
      / (date_diff('minute', departed_at, arrived_at) / 60.0)
      >= {{ min_speed_kmh }} * 1000
