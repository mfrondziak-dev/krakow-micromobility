{{ config(location='data/gold/mart_station_od_flows_hourly') }}

-- Origin-destination flows between parking hubs: each trip endpoint is
-- attributed to the nearest station within the snap radius.

{% set snap_radius_m = 200 %}

with stations as (

    select station_id, station_name, latitude, longitude
    from {{ ref('dim_stations') }}

),

trips as (

    select * from {{ ref('fct_vehicle_trips') }}

),

start_pick as (

    select
        vehicle_id,
        departed_at,
        station_id as start_station_id
    from (
        select
            t.vehicle_id,
            t.departed_at,
            s.station_id,
            {{ haversine_m('t.start_lat', 't.start_lon', 's.latitude', 's.longitude') }} as dist_m
        from trips t
        cross join stations s
    ) c
    where dist_m < {{ snap_radius_m }}
    qualify row_number() over (partition by vehicle_id, departed_at order by dist_m) = 1

),

end_pick as (

    select
        vehicle_id,
        departed_at,
        station_id as end_station_id
    from (
        select
            t.vehicle_id,
            t.departed_at,
            s.station_id,
            {{ haversine_m('t.end_lat', 't.end_lon', 's.latitude', 's.longitude') }} as dist_m
        from trips t
        cross join stations s
    ) c
    where dist_m < {{ snap_radius_m }}
    qualify row_number() over (partition by vehicle_id, departed_at order by dist_m) = 1

)

select
    date_trunc('hour', t.departed_at) as hour,
    ss.start_station_id,
    es.end_station_id,
    count(*) as trips_count,
    avg(t.distance_m) as avg_distance_m
from trips t
join start_pick ss
    on ss.vehicle_id = t.vehicle_id and ss.departed_at = t.departed_at
join end_pick es
    on es.vehicle_id = t.vehicle_id and es.departed_at = t.departed_at
where ss.start_station_id <> es.end_station_id
group by 1, 2, 3
